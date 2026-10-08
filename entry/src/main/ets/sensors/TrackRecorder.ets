import { sensor } from '@kit.SensorServiceKit';
import { geoLocationManager } from '@kit.LocationKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { notificationManager } from '@kit.NotificationKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { Store } from '../data/Store';
import { INDOOR_UNKNOWN, TrackPointDraft } from '../data/Entities';
import { TogglePlan, planToggle } from '../common/IndoorState';
import { Ctx, fusedAzimuth } from '../common/Utils';
import { wifiSummary } from '../common/WifiSummary';
import { Vec3Sample, encodeSeries } from '../common/ImuFeatures';

const NOTIF_ID = 1001;

/**
 * 每个采样点保留多少个 AP（按 RSSI 降序、bssid 升序确定取前 N 个）。
 *
 * 2026-09-30 由 5 改成 40：原因是实测发现「最强 5 个」在同一地点相隔 30 秒的两次扫描之间
 * 重合 0 个（现场 150~200 个 AP、RSSI 大量并列），指纹完全不可复现。理由详见 refreshWifi()。
 * 想调可以只改这一个数；调小了会退回「随机抽几个」的老毛病。
 */
const WIFI_KEEP = 40;

/** 每秒窗口最多缓存多少帧 IMU（阶段 0）。防传感器回调频率失控把内存与每行撑爆；
 *  真正入库前还会被 ImuFeatures 抽稀到 IMU_MAX_PER_WINDOW（60）。 */
const IMU_BUF_CAP = 600;
/**
 * IMU 上报间隔，单位**纳秒**（1ms = 1,000,000ns）。20ms = 50Hz。
 *
 * ⚠️ 2026-10-04 真机实测：**两参数重载 `sensor.on(id, cb)` 走的是平台默认间隔 ≈160ms（约 6Hz）**，
 * 而步频是 1.5~2.5Hz —— 每个步态周期只有 2~3 个采样点，峰值检测直接失效（会混叠）。
 * 所以必须用三参数重载显式指定。50Hz 稳过步态所需，且低于每秒 60 的存储上限、不会被抽稀。
 */
const IMU_INTERVAL_NS = 20000000;
/** 加速度序列小数位（m/s²）；陀螺仪数值小一个量级，多留一位（rad/s）。 */
const ACCEL_SERIES_DECIMALS = 3;
const GYRO_SERIES_DECIMALS = 4;

/** 记录中的当前传感器快照（供拍照/标签关联） */
export interface RecSnapshot {
  latitude?: number;
  longitude?: number;
  altitude?: number;
  /**
   * 这次定位的精度（米）—— 2026-09-29 新增（第二十五轮）。室内拿到的常常是误差一两百米的
   * 网络定位，节点必须把这个精度一并存下来，否则它会和实测坐标长得一样地摆在图上：
   * 而节点正是航位推算要当锚点用的东西，锚点不干净后面就全错。
   */
  accuracy?: number;
  headingDeg?: number;
  pressureHpa?: number;
}

/**
 * 轨迹记录器（≈ Android 版 TrackRecorder + RecordingService）：
 * 每秒采样一次 定位+气压+地磁+WiFi 摘要，每 5 秒批量落库；
 * 用 LOCATION 型长时任务 + 常驻通知保持后台记录。单例，页面间共享。
 */
export class TrackRecorder {
  private static inst: TrackRecorder | null = null;
  static get(): TrackRecorder {
    if (!TrackRecorder.inst) {
      TrackRecorder.inst = new TrackRecorder();
    }
    return TrackRecorder.inst;
  }

  private running = false;
  private trackId = -1;
  /** 当前开着的室内外段 id（-1 = 没有）；由 toggleIndoor 关闭并新开 */
  private segmentId = -1;
  /** 当前室内外状态（INDOOR_UNKNOWN / INDOOR_OUT / INDOOR_IN） */
  private indoor: number = INDOOR_UNKNOWN;
  private t0 = 0;
  private pointCount = 0;
  /** 本次记录已打的拐点数（2026-10-05 新增） */
  private cornerCount = 0;
  private buffer: TrackPointDraft[] = [];
  private sampleTimer = -1;
  private elapsedTimer = -1;
  private wifiTimer = -1;

  private lastLoc: geoLocationManager.Location | null = null;
  private lastPressure: number | undefined = undefined;
  private lastMag: number[] = [0, 0, 0];
  private hasMag = false;
  private lastAccel: number[] = [0, 0, 0];
  private hasAccel = false;
  private lastHeading: number | undefined = undefined;
  /** 本秒窗口内缓存的原始 IMU 帧（阶段 0 新增，见 common/ImuFeatures） */
  private accelBuf: Vec3Sample[] = [];
  private gyroBuf: Vec3Sample[] = [];
  /** 本秒窗口的起点（毫秒）：编码时以 `Date.now() - windowStartMs` 作样本的相对偏移 */
  private windowStartMs = 0;
  private lastWifi = '';
  private lastWifiCount = 0;

  private pressureCb = (d: sensor.BarometerResponse): void => {
    this.lastPressure = d.pressure;
  };
  private magCb = (d: sensor.MagneticFieldResponse): void => {
    this.lastMag = [d.x, d.y, d.z];
    this.hasMag = true;
  };
  private accelCb = (d: sensor.AccelerometerResponse): void => {
    this.lastAccel = [d.x, d.y, d.z];
    this.hasAccel = true;
    this.pushImu(this.accelBuf, d.x, d.y, d.z);
  };
  private gyroCb = (d: sensor.GyroscopeResponse): void => {
    this.pushImu(this.gyroBuf, d.x, d.y, d.z);
  };

  /** 把一帧原始 IMU 压进当前秒窗口的缓冲（阶段 0）。未记录或超出上限一律丢弃。 */
  private pushImu(buf: Vec3Sample[], x: number, y: number, z: number): void {
    if (!this.running || buf.length >= IMU_BUF_CAP) {
      return;
    }
    const s: Vec3Sample = { t: Math.max(0, Date.now() - this.windowStartMs), x: x, y: y, z: z };
    buf.push(s);
  }
  private locCb = (loc: geoLocationManager.Location): void => {
    this.lastLoc = loc;
  };

  isRunning(): boolean {
    return this.running;
  }

  /** 当前轨迹 id；未在记录时返回 -1 */
  getTrackId(): number {
    return this.trackId;
  }

  /** 本次记录已采样的点数（录制横幅显示，给用户「数据在动」的反馈） */
  getPointCount(): number {
    return this.pointCount;
  }

  /** 本次记录已打的拐点数（录制横幅显示） */
  getCornerCount(): number {
    return this.cornerCount;
  }

  /**
   * 按下「拐点」那一刻的朝向。
   *
   * 刻意**不复用 `this.lastHeading`**：它是每秒在 `sample()` 里算一次的，而拐角处恰恰是
   * 朝向变化最快的地方，复用最多会滞后 1 秒（走路 ≈1.2 米）。这里拿最新的加速度/地磁
   * （50Hz 在刷新）当场算一次。
   */
  instantHeading(): number | undefined {
    if (this.hasAccel && this.hasMag) {
      return fusedAzimuth(this.lastAccel, this.lastMag);
    }
    return this.lastHeading;
  }

  /**
   * 一键打「拐点」：只记**按下这一刻**的时刻与朝向，不弹对话框、不调相机、不留照片。
   * 为什么不能走「记录节点」那条流程（那要填表 + 拍照，时间戳会偏 15~25 米），
   * 见 Entities.TrackCorner 的说明。返回写入的行 id；未在记录时返回 -1。
   */
  async markCorner(): Promise<number> {
    if (!this.running) {
      return -1;
    }
    const id: number = await Store.insertTrackCorner(this.trackId, Date.now(), this.instantHeading());
    this.cornerCount++;
    return id;
  }

  /**
   * 切一下「室内 / 室外」（2026-10-08 新增）。
   *
   * 状态循环：未标 → 室内 → 室外 → 未标。实现就是**关掉当前段、开一段新的**——
   * 段边界＝用户按下这一刻，时间戳是精确的（这也是为什么它不走「记录节点」那条要填表
   * 拍照的流程：那样时间戳会偏 15~25 米，跟拐点同一个道理）。
   *
   * 开录时不问室内外、默认「未标」：整趟没按过按钮就是未标，这是诚实的；
   * 默认成「室外」会把「忘了按」和「真的在室外」混成一样。
   *
   * 返回切换后的状态；未在记录时返回 INDOOR_UNKNOWN。
   */
  async toggleIndoor(): Promise<number> {
    if (!this.running) {
      return INDOOR_UNKNOWN;
    }
    const plan: TogglePlan = planToggle(this.segmentId, this.indoor, Date.now());
    if (plan.closeId >= 0) {
      try {
        await Store.closeSegment(plan.closeId, plan.atMs);
      } catch (e) {
      }
    }
    this.indoor = plan.next;
    try {
      this.segmentId = await Store.insertSegment(this.trackId, plan.atMs, this.indoor);
    } catch (e) {
      this.segmentId = -1;
    }
    AppStorage.setOrCreate('rm_indoor', this.indoor);
    return this.indoor;
  }

  /** 当前室内外状态（INDOOR_*）。界面按钮用它决定显示什么、再按一下切到哪。 */
  currentIndoor(): number {
    return this.indoor;
  }

  /** 当前传感器快照（供轨迹途中拍照/打标签时关联定位与朝向） */
  getSnapshot(): RecSnapshot {
    const loc = this.lastLoc;
    const snap: RecSnapshot = {
      latitude: loc ? loc.latitude : undefined,
      longitude: loc ? loc.longitude : undefined,
      altitude: loc ? loc.altitude : undefined,
      accuracy: loc ? loc.accuracy : undefined,
      headingDeg: this.lastHeading,
      pressureHpa: this.lastPressure
    };
    return snap;
  }

  async start(name: string): Promise<void> {
    if (this.running) {
      return;
    }
    // 2026-10-08：不再接收 areaId —— 轨迹不归属区域了（见 Entities.Track）。
    // 谁属于哪栋楼由节点自己带；室内/室外另开一段（track_segments）。
    // t0 自己取再传给 insertTrack，好让第一段的起点与轨迹起点严格相等。
    const t0: number = Date.now();
    this.trackId = await Store.insertTrack(name, t0);
    this.t0 = t0;
    this.pointCount = 0;
    this.cornerCount = 0;
    this.buffer = [];
    this.accelBuf = [];
    this.gyroBuf = [];
    this.windowStartMs = Date.now();
    this.running = true;

    // 开第一段「未标」。开录时不问室内外（见 StartTrackDialog 的说明）。
    this.indoor = INDOOR_UNKNOWN;
    try {
      this.segmentId = await Store.insertSegment(this.trackId, t0, this.indoor);
    } catch (e) {
      this.segmentId = -1;
    }

    AppStorage.setOrCreate('rm_recording', true);
    AppStorage.setOrCreate('rm_rec_track_name', name);
    AppStorage.setOrCreate('rm_elapsed', 0);
    AppStorage.setOrCreate('rm_indoor', this.indoor);

    try {
      sensor.on(sensor.SensorId.BAROMETER, this.pressureCb);
    } catch (e) {
    }
    try {
      sensor.on(sensor.SensorId.MAGNETIC_FIELD, this.magCb);
    } catch (e) {
    }
    // 阶段 0：显式给采样间隔（第三参数，单位纳秒）。理由见 IMU_INTERVAL_NS 的注释。
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, this.accelCb, { interval: IMU_INTERVAL_NS });
    } catch (e) {
    }
    // 陀螺仪用于朝向积分。GYROSCOPE 权限已在 module.json5 声明、并在 EntryAbility 申请。
    try {
      sensor.on(sensor.SensorId.GYROSCOPE, this.gyroCb, { interval: IMU_INTERVAL_NS });
    } catch (e) {
    }
    const req: geoLocationManager.ContinuousLocationRequest = {
      interval: 1,
      locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION
    };
    try {
      geoLocationManager.on('locationChange', req, this.locCb);
    } catch (e) {
    }

    this.refreshWifi();
    this.wifiTimer = setInterval(() => {
      this.refreshWifi();
    }, 30000);
    this.sampleTimer = setInterval(() => {
      this.sample();
    }, 1000);
    this.elapsedTimer = setInterval(() => {
      AppStorage.setOrCreate('rm_elapsed', Math.floor((Date.now() - this.t0) / 1000));
    }, 1000);

    this.startBackground(name);
  }

  async stop(): Promise<void> {
    if (!this.running) {
      return;
    }
    this.running = false;
    if (this.sampleTimer >= 0) {
      clearInterval(this.sampleTimer);
      this.sampleTimer = -1;
    }
    if (this.elapsedTimer >= 0) {
      clearInterval(this.elapsedTimer);
      this.elapsedTimer = -1;
    }
    if (this.wifiTimer >= 0) {
      clearInterval(this.wifiTimer);
      this.wifiTimer = -1;
    }
    try {
      sensor.off(sensor.SensorId.BAROMETER, this.pressureCb);
    } catch (e) {
    }
    try {
      sensor.off(sensor.SensorId.MAGNETIC_FIELD, this.magCb);
    } catch (e) {
    }
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER, this.accelCb);
    } catch (e) {
    }
    try {
      sensor.off(sensor.SensorId.GYROSCOPE, this.gyroCb);
    } catch (e) {
    }
    try {
      geoLocationManager.off('locationChange', this.locCb);
    } catch (e) {
    }

    const batch = this.buffer;
    this.buffer = [];
    try {
      await Store.insertPoints(batch);
    } catch (e) {
    }
    try {
      await Store.finishTrack(this.trackId, Date.now(), this.pointCount);
    } catch (e) {
    }

    AppStorage.setOrCreate('rm_recording', false);
    AppStorage.setOrCreate('rm_rec_track_name', '');
    AppStorage.setOrCreate('rm_elapsed', 0);
    // 段的收尾（把开着的段写上 endMs）已经在 Store.finishTrack 里做了 ——
    // 放在那儿是为了「结束录制」无论从哪条路径走都不会留下永远延伸的段。
    this.indoor = INDOOR_UNKNOWN;
    this.segmentId = -1;
    AppStorage.setOrCreate('rm_indoor', INDOOR_UNKNOWN);
    this.stopBackground();
  }

  private sample(): void {
    const now: number = Date.now();
    const loc = this.lastLoc;
    // 朝向：加速度+地磁融合方位角，GPS direction 兜底
    let headingDeg: number | undefined = undefined;
    if (this.hasAccel && this.hasMag) {
      headingDeg = fusedAzimuth(this.lastAccel, this.lastMag);
    }
    if (headingDeg === undefined && loc && loc.direction !== undefined) {
      headingDeg = loc.direction;
    }
    this.lastHeading = headingDeg;
    // 阶段 0：把这一秒缓存的原始 IMU 序列编码进采样点，然后清空缓冲、推进窗口起点。
    // 「先编码、再清空、最后推进起点」的顺序不能换：换顺序样本的相对偏移就错位了。
    const accelSeries: string = encodeSeries(this.accelBuf, ACCEL_SERIES_DECIMALS);
    const gyroSeries: string = encodeSeries(this.gyroBuf, GYRO_SERIES_DECIMALS);
    this.accelBuf = [];
    this.gyroBuf = [];
    this.windowStartMs = now;
    const pt: TrackPointDraft = {
      trackId: this.trackId,
      timeMs: now,
      latitude: loc ? loc.latitude : undefined,
      longitude: loc ? loc.longitude : undefined,
      altitude: loc ? loc.altitude : undefined,
      accuracy: loc ? loc.accuracy : undefined,
      pressureHpa: this.lastPressure,
      magneticX: this.hasMag ? this.lastMag[0] : undefined,
      magneticY: this.hasMag ? this.lastMag[1] : undefined,
      magneticZ: this.hasMag ? this.lastMag[2] : undefined,
      headingDeg: headingDeg,
      wifiCount: this.lastWifiCount,
      wifiTop: this.lastWifi,
      accelSeries: accelSeries,
      gyroSeries: gyroSeries
    };
    this.buffer.push(pt);
    this.pointCount++;
    if (this.buffer.length >= 5) {
      const batch = this.buffer;
      this.buffer = [];
      Store.insertPoints(batch).catch(() => {
      });
    }
  }

  private refreshWifi(): void {
    try {
      wifiManager.scan();
    } catch (e) {
    }
    setTimeout(() => {
      try {
        const list = wifiManager.getScanInfoList();
        // 2026-09-30（第二十九轮）：从「取最强的 5 个」改成「取 40 个」。
        // 实测证据（独树阳光里两条同路线轨迹）：**同一个地方、相隔 30 秒的两次扫描，
        // 最强的 5 个 AP 重合 0 个** —— 现场可见 150~200 个 AP、RSSI 大量并列，
        // 「前 5 名」等于随机抓 5 个，指纹因此完全不可复现。
        // 取哪几个、怎么排序的规则抽到了 common/WifiSummary.ets（这样能离线单测）：
        // **按 (rssi 降序, bssid 升序) 确定地取前 N 个**，bssid 兜底不能省。
        // 代价：这条摘要从 ~100 字符涨到 ~900 字符（一条 400 点的轨迹约 350 KB），
        // 换来的是「WiFi 指纹到底能不能用」这个问题的答案。
        const bs: string[] = list.map((i: wifiManager.WifiScanInfo) => i.bssid);
        const rs: number[] = list.map((i: wifiManager.WifiScanInfo) => i.rssi);
        this.lastWifi = wifiSummary(bs, rs, WIFI_KEEP);
        this.lastWifiCount = list.length;
      } catch (e) {
      }
    }, 1500);
  }

  private async startBackground(name: string): Promise<void> {
    try {
      const context = Ctx.ui;
      if (!context) {
        return;
      }
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: 'hk.edu.cityu.campusnav', abilityName: 'EntryAbility' }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      // HarmonyOS 6（API 21）：LOCATION 长时任务改用字符串数组形式申请
      await backgroundTaskManager.startBackgroundRunning(context, ['location'], agent);
    } catch (e) {
    }
    try {
      await notificationManager.publish({
        id: NOTIF_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: '正在记录轨迹', text: `「${name}」· 点击返回应用` }
        }
      });
    } catch (e) {
    }
  }

  private stopBackground(): void {
    try {
      notificationManager.cancel(NOTIF_ID);
    } catch (e) {
    }
    try {
      if (Ctx.ui) {
        backgroundTaskManager.stopBackgroundRunning(Ctx.ui);
      }
    } catch (e) {
    }
  }
}
