import { promptAction } from '@kit.ArkUI';
import { sensor } from '@kit.SensorServiceKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { Area, Marker, PlaceScan, PlaceScanDraft, Room, Track, TrackTag, WifiPoint } from '../data/Entities';
import { Store } from '../data/Store';
import { ApSample, parseWifiSummary, wifiSummary } from '../common/WifiSummary';
import {
  Landmark, LandmarkIdentity, LandmarkSeed, LocatorState, PLACE_HALF_WINDOW_S, PLACE_TOP_N,
  PlaceEstimate, PlaceIndex, PlaceMatch, SessionScore, confidenceLabel, crossSessionScores,
  landmarkBaseName, landmarkKeyOf, makeIndex, matchOnce, mergeLandmarks, mergeScans,
  newLocatorState, stepLocator, windowObservations
} from '../common/PlaceMatch';
import { captureSnapshot, Snapshot } from '../sensors/SensorSnapshotter';
import { fmtDateTime } from '../common/Utils';
import { Theme } from '../common/Theme';
import { Chip, PillButton, ThickButton } from '../common/Widgets';
import { BindPlaceDialog, PlaceOption } from './PlaceDialogs';

/** 实时扫描周期（毫秒）。scan() 之后要等一会儿才拿得到结果，见 readScan */
const TICK_MS = 3000;
/** scan() 到 getScanInfoList() 之间的等待（与 TrackRecorder.refreshWifi 同一做法） */
const SCAN_WAIT_MS = 1600;
/** 静止扫描持续多久、每几秒扫一次 */
const STILL_SECONDS = 15;
const STILL_STEP_MS = 3000;
/** 扫描保存的 AP 个数（与采样点的 WIFI_KEEP 一致） */
const SCAN_KEEP = 40;
/** 认不出时才去问一次 GPS；两次之间的最小间隔，免得室内反复空转 */
const GPS_COOLDOWN_MS = 60000;
/** 好定位的门限（米）；室内拿到的常是 100~200 m 的网络定位，那种不显示 */
const GPS_GOOD_M = 20;

/** 地点清单里的一行 */
interface PlaceRow {
  key: string;
  label: string;
  sub: string;
  /** 有跨会话结构指纹（= 被跨会话强化过） */
  strong: boolean;
}

/**
 * 「我在哪」（2026-10-08 新增）。
 *
 * 做的事：把 App 里已经录过的节点变成**指纹地图**，然后拿当前的 WiFi 扫描去认位置。
 * 算法与参数全部来自 `common/PlaceMatch`（纯逻辑、已用真实数据验证过：
 * 9 个门的顺序 9/9、负向验证 0/958）。这一页只负责取数据、跑传感器、把结论说清楚。
 *
 * 三条刻意的设计：
 *  1. **不承诺米级坐标**。给的是「最近的是哪个地点」。室内没有可用定位，指纹能回答的
 *     本来就是「你在哪个点附近」；连续坐标要靠航位推算，那条已被两次真实数据证伪。
 *  2. **认不出来时的说法要诚实**：「认不出（最接近的是 X）」比硬给一个错的答案强得多。
 *     XP/虚荣指标一概没有，这是采集工具。
 *  3. **静止扫描不是调试按钮**。它是「跨会话还能不能认出来」这个生死问题的唯一答案来源，
 *     也是「多来几次把地点压实」的入口（绑定后作为新会话参与建图）。
 */
@Component
export struct WhereAmIPage {
  onBack: () => void = () => {
  };

  // ---------- 地图状态 ----------
  @State mapReady: boolean = false;
  @State building: boolean = false;
  @State landmarkCount: number = 0;
  @State fingerCount: number = 0;
  @State sessionCount: number = 0;
  @State strongCount: number = 0;
  @State placesOpen: boolean = false;
  @State places: PlaceRow[] = [];

  // ---------- 当前判定 ----------
  @State estMatched: boolean = false;
  @State estLabel: string = '';
  @State estFloor: string = '';
  @State estBuilding: string = '';
  @State estScore: number = 0;
  @State estMargin: number = 0;
  @State estRunner: string = '';
  @State estCommon: number = 0;
  @State estBestLabel: string = '';
  @State apCount: number = 0;
  @State pressFloor: string = '';
  @State pressBuilding: string = '';
  @State pressHpa: string = '';
  @State gpsText: string = '';
  @State hint: string = '';

  // ---------- 静止扫描 ----------
  @State scanning: boolean = false;
  @State scanLeft: number = 0;
  @State scanCollected: number = 0;

  // ---------- 记录 ----------
  @State scans: PlaceScan[] = [];
  @State scores: SessionScore[] = [];

  private index: PlaceIndex[] = [];
  private landmarks: Landmark[] = [];
  private locState: LocatorState = newLocatorState();
  private pressureHpa: number | undefined = undefined;
  private lastGpsAt: number = 0;
  private tickTimer: number = -1;
  private scanStepTimer: number = -1;
  private pending: boolean = false;
  private captured: string[] = [];
  private roomNames: string[] = [];
  private roomIds: number[] = [];
  private areaNames: string[] = [];
  private areaIds: number[] = [];

  private pressureCb = (d: sensor.BarometerResponse): void => {
    this.pressureHpa = d.pressure;
  };

  // ---------------------------------------------------------------- 生命周期

  aboutToAppear(): void {
    try {
      sensor.on(sensor.SensorId.BAROMETER, this.pressureCb);
    } catch (e) {
    }
    this.reloadRefs().then(() => {
      this.buildMap();
    }).catch(() => {
      this.buildMap();
    });
    this.reloadScans();
    this.tickTimer = setInterval(() => {
      this.tickWifi();
    }, TICK_MS);
    this.tickWifi();
  }

  aboutToDisappear(): void {
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    this.stopStillScan();
    try {
      sensor.off(sensor.SensorId.BAROMETER, this.pressureCb);
    } catch (e) {
    }
  }

  // ---------------------------------------------------------------- 名称表

  /** 房间/区域的名字表（节点标签要用「房间号 · 楼层 · 建筑」） */
  private reloadRefs(): Promise<void> {
    return Store.listRooms().then((rooms: Room[]) => {
      const rn: string[] = [];
      const ri: number[] = [];
      for (const r of rooms) {
        rn.push(r.code.length > 0 ? r.code : r.name);
        ri.push(r.id);
      }
      this.roomNames = rn;
      this.roomIds = ri;
      return Store.listAreas().then((areas: Area[]) => {
        const an: string[] = [];
        const ai: number[] = [];
        for (const a of areas) {
          an.push(a.name);
          ai.push(a.id);
        }
        this.areaNames = an;
        this.areaIds = ai;
      });
    });
  }

  private roomNameOf(id: number): string {
    for (let i = 0; i < this.roomIds.length; i++) {
      if (this.roomIds[i] === id) {
        return this.roomNames[i];
      }
    }
    return '';
  }

  private areaNameOf(id: number): string {
    for (let i = 0; i < this.areaIds.length; i++) {
      if (this.areaIds[i] === id) {
        return this.areaNames[i];
      }
    }
    return '';
  }

  /** 建筑名简化：只留开头的编号（「AC1 楊建文學術樓」→「AC1」），一行放得下 */
  private shortBuilding(name: string): string {
    if (name.length === 0) {
      return '';
    }
    const sp: number = name.indexOf(' ');
    return sp > 0 ? name.substring(0, sp) : name;
  }

  // ---------------------------------------------------------------- 建图

  /**
   * 建指纹地图：所有轨迹的节点 → 每个节点取它前后 6 秒的采样点当模板。
   *
   * 为什么在端上重建而不是读 PC 生成的 place_map.json：用户选的是「只用 App 里已录的节点自建」
   * —— 出门在外手机就是全部，不该依赖有没有带电脑。代价是只能认录过节点的地方，
   * 这一点在界面上写清楚了。
   */
  private buildMap(): void {
    if (this.building) {
      return;
    }
    this.building = true;
    this.hint = '正在建立指纹地图…';
    Store.listAllMarkers().then((markers: Marker[]) => {
      return Store.listRooms().then((rooms: Room[]) => {
        // markerId → roomId 的表（节点的房间绑定走的是 markerId）
        const mid: number[] = [];
        const mrid: number[] = [];
        for (const m of markers) {
          mid.push(m.id);
          mrid.push(m.roomId);
        }
        return Store.listTracks().then((tracks: Track[]) => {
          return this.collectSeeds(tracks, mid, mrid);
        });
      });
    }).then((seeds: LandmarkSeed[]) => {
      this.landmarks = mergeLandmarks(seeds);
      this.index = makeIndex(this.landmarks, PLACE_TOP_N, false);
      this.locState = newLocatorState();
      let finger = 0;
      let strong = 0;
      for (const c of this.index) {
        finger++;
        if (c.structuralOnly) {
          strong++;
        }
      }
      let sessions: number[] = [];
      for (const lm of this.landmarks) {
        for (const s of lm.sessions) {
          if (sessions.indexOf(s) < 0) {
            sessions.push(s);
          }
        }
      }
      this.landmarkCount = this.landmarks.length;
      this.fingerCount = finger;
      this.strongCount = strong;
      this.sessionCount = sessions.length;
      this.places = this.buildPlaceRows();
      this.mapReady = true;
      this.building = false;
      this.hint = '';
    }).catch((e: Error) => {
      this.building = false;
      this.hint = `建图失败：${e.message}`;
    });
  }

  /** 逐条轨迹取采样点与节点，拼成地标素材（串行，别一次把所有轨迹的点都读进内存） */
  private collectSeeds(tracks: Track[], markerIds: number[], markerRoomIds: number[]): Promise<LandmarkSeed[]> {
    const seeds: LandmarkSeed[] = [];
    let chain: Promise<void> = Promise.resolve();
    for (const t of tracks) {
      chain = chain.then((): Promise<void> => {
        return Store.listWifiPoints(t.id).then((pts: WifiPoint[]) => {
          return Store.listTrackTags(t.id).then((tags: TrackTag[]) => {
            for (const g of tags) {
              const roomId: number = this.roomOfMarker(g.markerId, markerIds, markerRoomIds);
              const building: string = this.areaNameOf(g.areaId === undefined ? -1 : (g.areaId as number));
              const identity: LandmarkIdentity = {
                roomId: roomId,
                note: g.note,
                tagType: g.tagType,
                floor: g.floor,
                building: building,
                trackId: t.id,
                tagId: g.id
              };
              const base: string = landmarkBaseName(identity, this.roomNameOf(roomId));
              const label: string = this.labelOf(base, g.floor, building);
              const seed: LandmarkSeed = {
                key: landmarkKeyOf(identity),
                label: label,
                floor: g.floor,
                building: building,
                sessionId: t.id,
                observations: windowObservations(pts, g.timeMs, PLACE_HALF_WINDOW_S)
              };
              seeds.push(seed);
            }
          });
        });
      });
    }
    // 静止扫描里「绑过地点」的那些也算一次到访（会话 id 用一个不会与轨迹 id 撞的开区间）
    chain = chain.then((): Promise<void> => {
      return Store.listPlaceScans(200).then((scans: PlaceScan[]) => {
        for (const s of scans) {
          if (s.boundKey.length === 0) {
            continue;
          }
          const aps: ApSample[] = parseWifiSummary(s.wifiTop);
          if (aps.length === 0) {
            continue;
          }
          const seed: LandmarkSeed = {
            key: s.boundKey,
            label: s.boundLabel,
            floor: '',
            building: '',
            // 会话 id：用负的一次性区间，避免与轨迹 id 撞车（轨迹 id 是正的自增）
            sessionId: -s.id,
            observations: [{ aps: aps, pressureHpa: s.pressureHpa }]
          };
          seeds.push(seed);
        }
      });
    });
    return chain.then((): LandmarkSeed[] => seeds);
  }

  private roomOfMarker(markerId: number | undefined, markerIds: number[], roomIds: number[]): number {
    if (markerId === undefined || markerId <= 0) {
      return -1;
    }
    for (let i = 0; i < markerIds.length; i++) {
      if (markerIds[i] === markerId) {
        return roomIds[i];
      }
    }
    return -1;
  }

  private labelOf(base: string, floor: string, building: string): string {
    const parts: string[] = [base];
    if (floor.length > 0) {
      parts.push(floor);
    }
    const short: string = this.shortBuilding(building);
    if (short.length > 0) {
      parts.push(short);
    }
    return parts.join(' · ');
  }

  private buildPlaceRows(): PlaceRow[] {
    const out: PlaceRow[] = [];
    for (const lm of this.landmarks) {
      const sub: string = `${lm.aps.length} 个 AP · ${lm.sessions.length} 次到访`
        + (lm.structural.length > 0 ? ` · 跨会话稳定 ${lm.structural.length}` : '');
      const row: PlaceRow = {
        key: lm.key, label: lm.label, sub: sub, strong: lm.structural.length > 0
      };
      out.push(row);
    }
    return out;
  }

  // ---------------------------------------------------------------- 实时扫描与判定

  private tickWifi(): void {
    if (this.pending || this.scanning || !this.mapReady) {
      return;
    }
    this.pending = true;
    try {
      wifiManager.scan();
    } catch (e) {
    }
    setTimeout(() => {
      this.readScan();
    }, SCAN_WAIT_MS);
  }

  /** 读上次 scan() 的结果 → 打分 → 更新界面 */
  private readScan(): void {
    let summary: string = '';
    let count: number = 0;
    try {
      const list = wifiManager.getScanInfoList();
      const bs: string[] = list.map((i: wifiManager.WifiScanInfo) => i.bssid);
      const rs: number[] = list.map((i: wifiManager.WifiScanInfo) => i.rssi);
      summary = wifiSummary(bs, rs, SCAN_KEEP);
      count = list.length;
    } catch (e) {
      summary = '';
    }
    this.pending = false;
    this.apCount = count;
    if (summary.length === 0 || this.index.length === 0) {
      return;
    }
    const sample: ApSample[] = parseWifiSummary(summary);
    const est: PlaceEstimate = stepLocator(this.locState, this.index, sample, this.pressureHpa, PLACE_TOP_N);
    this.applyEstimate(est);
    if (!est.matched) {
      this.maybeAskGps();
    }
  }

  private applyEstimate(est: PlaceEstimate): void {
    this.estMatched = est.matched;
    this.estLabel = est.label;
    this.estFloor = est.floor;
    this.estBuilding = this.shortBuilding(est.building);
    this.estScore = est.score;
    this.estMargin = est.margin;
    this.estRunner = est.runnerLabel;
    this.estCommon = est.common;
    this.estBestLabel = est.bestLabel;
    this.pressFloor = est.pressureFloor;
    this.pressBuilding = this.shortBuilding(est.pressureBuilding);
    this.pressHpa = est.pressureHpa === undefined ? '' : `${(est.pressureHpa as number).toFixed(1)} hPa`;
  }

  /**
   * 认不出的时候才去问一次 GPS —— 室外没有可比对的指纹（也可能压根没录过那个地方），
   * 这时 GPS 是唯一有意义的答案。室内拿到的多半是一两百米的网络定位，那种直接说「不可用」。
   */
  private maybeAskGps(): void {
    const now: number = Date.now();
    if (now - this.lastGpsAt < GPS_COOLDOWN_MS) {
      return;
    }
    this.lastGpsAt = now;
    captureSnapshot(4000).then((s: Snapshot) => {
      if (s.accuracy === undefined) {
        this.gpsText = '没有定位（室内正常）';
        return;
      }
      const acc: number = s.accuracy;
      this.gpsText = acc <= GPS_GOOD_M
        ? `GPS ±${acc.toFixed(0)} m（室外可用）`
        : `GPS ±${acc.toFixed(0)} m（网络定位，太差，不采用）`;
    }).catch(() => {
      this.gpsText = '';
    });
  }

  // ---------------------------------------------------------------- 静止扫描（跨会话验证 + 强化地点）

  private startStillScan(): void {
    if (this.scanning) {
      return;
    }
    if (this.index.length === 0) {
      promptAction.showToast({ message: '还没有可比对的地点：先去录一条带节点的轨迹' });
      return;
    }
    this.scanning = true;
    this.captured = [];
    this.scanLeft = STILL_SECONDS;
    this.scanCollected = 0;
    promptAction.showToast({ message: `站定别走动，扫描 ${STILL_SECONDS} 秒…` });
    this.stillStep();
    this.scanStepTimer = setInterval(() => {
      this.scanLeft = this.scanLeft - 3;
      if (this.scanLeft <= 0) {
        this.finishStillScan();
        return;
      }
      this.stillStep();
    }, STILL_STEP_MS);
  }

  private stopStillScan(): void {
    if (this.scanStepTimer >= 0) {
      clearInterval(this.scanStepTimer);
      this.scanStepTimer = -1;
    }
    this.scanning = false;
  }

  /** 静止扫描期间的一次取样 */
  private stillStep(): void {
    try {
      wifiManager.scan();
    } catch (e) {
    }
    setTimeout(() => {
      if (!this.scanning) {
        return;
      }
      let summary: string = '';
      try {
        const list = wifiManager.getScanInfoList();
        const bs: string[] = list.map((i: wifiManager.WifiScanInfo) => i.bssid);
        const rs: number[] = list.map((i: wifiManager.WifiScanInfo) => i.rssi);
        summary = wifiSummary(bs, rs, SCAN_KEEP);
        this.apCount = list.length;
      } catch (e) {
      }
      if (summary.length > 0) {
        this.captured.push(summary);
        this.scanCollected = this.captured.length;
      }
    }, SCAN_WAIT_MS);
  }

  /**
   * 扫描结束：把这几秒的扫描**合并成一条更强的指纹**（均值 RSSI，与建模板同一做法），
   * 当场算一次匹配，然后把「指纹 + 匹配结果」一起落库。绑定放到之后再做
   * （站着的时候不该弹框耽误事，而且绑定是个冷静的决定）。
   */
  private finishStillScan(): void {
    const parts: string[] = this.captured.slice();
    this.stopStillScan();
    if (parts.length === 0) {
      promptAction.showToast({ message: '没扫到任何 AP，重试一次' });
      return;
    }
    const merged: string = mergeScans(parts, SCAN_KEEP);
    const sample: ApSample[] = parseWifiSummary(merged);
    const m: PlaceMatch | undefined = matchOnce(this.index, sample, PLACE_TOP_N);
    const draft: PlaceScanDraft = {
      atMs: Date.now(),
      wifiTop: merged,
      wifiCount: sample.length,
      pressureHpa: this.pressureHpa,
      matchedKey: m === undefined ? '' : m.key,
      matchedLabel: m === undefined ? '' : m.label,
      score: m === undefined ? 0 : m.score,
      margin: m === undefined ? 0 : m.margin,
      runnerLabel: m === undefined ? '' : m.runnerLabel,
      commonAp: m === undefined ? 0 : m.common,
      boundKey: '',
      boundLabel: ''
    };
    Store.insertPlaceScan(draft).then(() => {
      this.reloadScans();
      const verdict: string = m === undefined
        ? '用了 0 个 AP 匹配'
        : `匹配 ${m.label}（重合 ${m.score.toFixed(2)}，用了 ${m.common} 个共同 AP）`;
      promptAction.showToast({ message: `已记录：${verdict}` });
    }).catch((e: Error) => {
      promptAction.showToast({ message: `记录失败：${e.message}` });
    });
  }

  private reloadScans(): void {
    Store.listPlaceScans(30).then((ss: PlaceScan[]) => {
      this.scans = ss;
      this.scores = crossSessionScores(ss);
    });
  }

  private openBind(scan: PlaceScan): void {
    const opts: PlaceOption[] = [];
    // 把「这次匹配到的」排在最前面，其余的按原顺序
    for (const lm of this.landmarks) {
      if (scan.matchedKey.length > 0 && lm.key === scan.matchedKey) {
        const o: PlaceOption = {
          key: lm.key, label: lm.label,
          sub: `${lm.aps.length} 个 AP · ${lm.sessions.length} 次到访`
        };
        opts.push(o);
      }
    }
    for (const lm of this.landmarks) {
      if (scan.matchedKey.length > 0 && lm.key === scan.matchedKey) {
        continue;
      }
      const o: PlaceOption = {
        key: lm.key, label: lm.label,
        sub: `${lm.aps.length} 个 AP · ${lm.sessions.length} 次到访`
      };
      opts.push(o);
    }
    if (opts.length === 0) {
      promptAction.showToast({ message: '还没有可选的地点' });
      return;
    }
    const dialog: CustomDialogController = new CustomDialogController({
      builder: BindPlaceDialog({
        options: opts,
        matchedKey: scan.matchedKey,
        onPick: (key: string, label: string): void => {
          Store.setPlaceScanBinding(scan.id, key, label).then(() => {
            this.reloadScans();
            this.buildMap();
            promptAction.showToast({ message: key.length > 0 ? `已绑定到 ${label}，地图已重建` : '已改为不绑定' });
          }).catch((e: Error) => {
            promptAction.showToast({ message: `绑定失败：${e.message}` });
          });
        }
      }),
      customStyle: false
    });
    dialog.open();
  }

  private confirmDeleteScan(scan: PlaceScan): void {
    promptAction.showDialog({
      title: '删掉这条扫描记录？',
      message: '只删这一条记录，不影响指纹地图（地图是从轨迹与绑定重建的）。',
      buttons: [
        { text: '取消', color: Theme.INK2 },
        { text: '删除', color: Theme.DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index !== 1) {
        return;
      }
      Store.deletePlaceScan(scan.id).then(() => {
        this.reloadScans();
        this.buildMap();
      }).catch((e: Error) => {
        promptAction.showToast({ message: `删除失败：${e.message}` });
      });
    }).catch(() => {
    });
  }

  // ---------------------------------------------------------------- 文案

  /** 大字那一行：确认了就给地点名，没确认就如实说「认不出」 */
  private bigText(): string {
    if (!this.mapReady) {
      return this.building ? '正在建立指纹地图…' : '还没有指纹地图';
    }
    if (this.estMatched) {
      return this.estLabel;
    }
    if (this.estBestLabel.length > 0) {
      return `认不出（最接近的是 ${this.estBestLabel}）`;
    }
    return '认不出';
  }

  private subText(): string {
    if (this.estMatched) {
      const parts: string[] = [];
      if (this.estFloor.length > 0) {
        parts.push(this.estFloor);
      }
      if (this.estBuilding.length > 0) {
        parts.push(this.estBuilding);
      }
      return parts.length > 0 ? parts.join(' · ') : '（这个地点没填楼层/建筑）';
    }
    if (this.pressFloor.length > 0) {
      return `气压看像是在 ${this.pressFloor}${this.pressBuilding.length > 0 ? ` · ${this.pressBuilding}` : ''}（不是地点结论）`;
    }
    return '还没有可靠的依据';
  }

  private evidenceText(): string {
    const parts: string[] = [];
    if (this.apCount > 0) {
      parts.push(`扫到 ${this.apCount} 个 AP`);
    }
    if (this.estScore > 0) {
      parts.push(`最佳重合 ${this.estScore.toFixed(2)}（${confidenceLabel(this.estScore)}）`
        + `，共同 AP ${this.estCommon} 个，领先次选 ${this.estMargin.toFixed(2)}`);
    }
    if (this.estRunner.length > 0) {
      parts.push(`次选：${this.estRunner}`);
    }
    if (this.pressHpa.length > 0) {
      parts.push(`气压 ${this.pressHpa}`);
    }
    if (this.gpsText.length > 0) {
      parts.push(this.gpsText);
    }
    return parts.length > 0 ? parts.join(' · ') : '等第一次扫描…';
  }

  private scanRowSub(s: PlaceScan): string {
    const when: string = fmtDateTime(s.atMs);
    const got: string = s.matchedKey.length > 0
      ? `匹配 ${s.matchedLabel}（${s.score.toFixed(2)}）`
      : '没认出来';
    const bind: string = s.boundKey.length > 0 ? ` · 已绑定 ${s.boundLabel}` : '';
    return `${when} · ${s.wifiCount} 个 AP · ${got}${bind}`;
  }

  // ---------------------------------------------------------------- 界面

  build() {
    Column() {
      Row({ space: 10 }) {
        PillButton({
          label: '‹ 返回',
          onTap: (): void => {
            this.onBack();
          }
        })
        Column({ space: 2 }) {
          Text('我在哪').fontSize(Theme.F_TITLE).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
          Text(this.mapReady
            ? `${this.landmarkCount} 个地点（${this.fingerCount} 个有指纹）· ${this.sessionCount} 次到访`
            : '正在准备指纹地图')
            .fontSize(Theme.F_META).fontColor(Theme.INK2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        PillButton({
          label: '重建地图',
          onTap: (): void => {
            this.buildMap();
          }
        })
      }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 10 })

      Scroll() {
        Column({ space: Theme.GAP }) {
          // ── 当前位置（主角）────────────────────────────────
          Column({ space: 8 }) {
            Text('当前位置').fontSize(Theme.F_META).fontColor(Theme.ON_RED_SOFT)
            Text(this.bigText())
              .fontSize(22).fontWeight(FontWeight.Bold).fontColor(Theme.ON_RED)
              .width('100%').maxLines(2)
            Text(this.subText())
              .fontSize(13).fontColor(Theme.ON_RED).width('100%')
            Text(this.evidenceText())
              .fontSize(Theme.F_META).fontColor(Theme.ON_RED_SOFT).width('100%')
            Row({ space: 8 }) {
              Circle({ width: 8, height: 8 })
                .fill(this.estMatched ? Theme.GREEN : Theme.YELLOW)
              Text(this.estMatched ? '已确认' : '未确认')
                .fontSize(Theme.F_META).fontColor(Theme.ON_RED_SOFT)
              Blank()
              Text(`${this.pressureHpa === undefined ? '气压 —' : `${this.pressureHpa.toFixed(1)} hPa`}`)
                .fontSize(Theme.F_META).fontColor(Theme.ON_RED_SOFT)
            }.width('100%')
          }
          .width('100%')
          .padding(18)
          .backgroundColor(Theme.RED)
          .borderRadius(Theme.R_HERO)
          .border({ width: { bottom: 5 }, color: { bottom: Theme.RED_DEEP } })

          // ── 静止扫描（跨会话验证 + 强化地点）────────────────
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Chip({ text: '原地静止扫描', kind: 'floor', iconKey: 'floor' })
              Blank()
              Text(`${STILL_SECONDS} 秒`)
                .fontSize(Theme.F_META).fontColor(Theme.INK2)
            }.width('100%')
            Text('站定不动、按一下，会把这几秒的扫描合并成一条更结实的指纹存起来。'
              + '它有两个用处：① 隔 2 小时 / 隔天再扫一次，就能回答「地址轮换了还能不能认出来」'
              + '——这是整套指纹方案的前提；② 事后把某次扫描绑到某个地点，它就会作为一次新的到访参与建图，'
              + '那个地点的指纹会更结实（认不出来时也能绑：你知道自己在哪，App 不知道）。')
              .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
            Row({ space: 10 }) {
              Column() {
                ThickButton({
                  label: this.scanning ? `扫描中…还剩 ${this.scanLeft} 秒` : '开始静止扫描',
                  kind: this.scanning ? 'ghost' : 'accent',
                  compact: true,
                  onTap: (): void => {
                    this.startStillScan();
                  }
                })
              }.layoutWeight(1.6)
              Column() {
                ThickButton({
                  label: '重建地图',
                  kind: 'ghost',
                  compact: true,
                  onTap: (): void => {
                    this.buildMap();
                  }
                })
              }.layoutWeight(1)
            }.width('100%')
            if (this.scanning) {
              Text(`已收集 ${this.scanCollected} 次扫描`)
                .fontSize(Theme.F_META).fontColor(Theme.BLUE_DEEP).width('100%')
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.CARD)
          .borderRadius(Theme.R_CARD)
          .border({ width: 2, color: Theme.LINE })

          // ── 跨会话成绩（那个生死问题的答案）──────────────────
          if (this.scores.length > 0) {
            Column({ space: 8 }) {
              Text('同一地点的跨会话成绩').fontSize(Theme.F_SECTION)
                .fontWeight(FontWeight.Bold).fontColor(Theme.INK).width('100%')
              Text('只看「绑过地点」的扫描：分母是绑到该地点的次数，分子是其中真的认出它的次数。'
                + '全部来自同一次走动不算数 —— 换天/换时段还能认出来，这个方案才立得住。')
                .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              ForEach(this.scores, (s: SessionScore) => {
                Row({ space: 8 }) {
                  Text(s.label)
                    .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(Theme.INK)
                    .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${s.hit}/${s.total} 次认对`)
                    .fontSize(13)
                    .fontColor(s.hit === s.total ? Theme.GREEN_DEEP : Theme.DANGER)
                  Blank()
                  Text(fmtDateTime(s.lastMs)).fontSize(Theme.F_META).fontColor(Theme.INK3)
                }.width('100%')
              }, (s: SessionScore) => s.key)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD)
            .border({ width: 2, color: Theme.LINE })
          }

          // ── 地图里有哪些地点 ────────────────────────────
          Column({ space: 0 }) {
            Row({ space: 8 }) {
              Text(`指纹地图（${this.landmarkCount} 个地点）`).fontSize(Theme.F_SECTION)
                .fontWeight(FontWeight.Bold).fontColor(Theme.INK)
              Blank()
              Text(this.placesOpen ? '收起 ▾' : '展开 ▸')
                .fontSize(Theme.F_META).fontWeight(FontWeight.Bold).fontColor(Theme.RED)
            }
            .width('100%')
            .onClick(() => {
              this.placesOpen = !this.placesOpen;
            })
            if (this.placesOpen) {
              Text(`来自 ${this.sessionCount} 次到访（一次轨迹算一次）· ${this.strongCount} 个地点已经有跨会话稳定指纹。`
                + '⚠️ 指纹与这台手机的 App 安装绑定：重装 App 或改包名会让全部指纹作废。')
                .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%').margin({ top: 8 })
              ForEach(this.places, (p: PlaceRow) => {
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(p.label)
                      .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(Theme.INK)
                      .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (p.strong) {
                      Chip({ text: '跨会话', kind: 'ok', iconKey: '' })
                    }
                  }.width('100%')
                  Text(p.sub).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              }, (p: PlaceRow) => p.key)
            } else {
              Text(this.landmarkCount === 0
                ? '还没有地点：先去录一条轨迹并在里面打几个节点（顺带写上备注或绑上房间，这样它才能跨会话认出来）'
                : '展开可以看到每个地点有多少个 AP、到访过几次')
                .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%').margin({ top: 8 })
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.CARD)
          .borderRadius(Theme.R_CARD)
          .border({ width: 2, color: Theme.LINE })

          // ── 扫描记录 ────────────────────────────────
          Column({ space: 10 }) {
            Text(`扫描记录（${this.scans.length}）`).fontSize(Theme.F_SECTION)
              .fontWeight(FontWeight.Bold).fontColor(Theme.INK).width('100%')
            if (this.scans.length === 0) {
              Text('还没有记录。走到某个门口站定，按上面的「开始静止扫描」。')
                .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
            }
            ForEach(this.scans, (s: PlaceScan) => {
              Column({ space: 6 }) {
                Text(this.scanRowSub(s))
                  .fontSize(13).fontColor(Theme.INK).width('100%')
                if (s.runnerLabel.length > 0 && s.matchedKey.length > 0) {
                  Text(`次选：${s.runnerLabel}（领先 ${s.margin.toFixed(2)}）`)
                    .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                }
                Row({ space: 8 }) {
                  PillButton({
                    label: s.boundKey.length > 0 ? '改绑定' : '绑定到地点',
                    onTap: (): void => {
                      this.openBind(s);
                    }
                  })
                  PillButton({
                    label: '删除',
                    kind: 'danger',
                    onTap: (): void => {
                      this.confirmDeleteScan(s);
                    }
                  })
                  Blank()
                }.width('100%')
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
            }, (s: PlaceScan) => s.id + '')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.CARD)
          .borderRadius(Theme.R_CARD)
          .border({ width: 2, color: Theme.LINE })

          // ── 这个功能的边界（必须写在界面上）─────────────────
          Column({ space: 6 }) {
            Text('这个功能能说什么、不能说什么').fontSize(Theme.F_SECTION)
              .fontWeight(FontWeight.Bold).fontColor(Theme.INK).width('100%')
            Text('· 给的是「最近的是哪个地点」（例如某个门 / 某个节点）＋楼层，不是连续坐标。'
              + '室内没有可用定位，指纹本来也只能回答「你在哪个点附近」。')
              .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
            Text('· 只能认「录过节点的地点」。没打过点的地方、以及整栋没去过的楼，认不出来是正常的。')
              .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
            Text('· 无名节点（没备注、没绑房间的）不会跨会话合并 —— 一趟里可能有三个都叫「门 4/F」。'
              + '想让某个地点结实起来，给它写个备注或绑个房间。')
              .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
            Text('· 指纹只在这台手机、这次安装内有效。换手机、重装 App、改包名都会让它作废。')
              .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
            if (this.hint.length > 0) {
              Text(this.hint).fontSize(Theme.F_META).fontColor(Theme.BLUE_DEEP).width('100%')
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.CARD_SOFT)
          .borderRadius(Theme.R_CARD)
          .border({ width: 2, color: Theme.LINE })
        }.padding({ left: Theme.PAD, right: Theme.PAD, bottom: 24 }).width('100%')
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
