import { promptAction } from '@kit.ArkUI';
// ⚠️ 本文件同时要用 ArkUI 全局的 `Area` 类型（Canvas 的 .onAreaChange 回调参数，有 width/height）。
// 自家的「区域」实体也叫 Area，直接 `import { Area }` 会**遮蔽**那个全局类型，
// 真机编译直接报 10505001（Argument of type '(oldA: Area, newA: Area) => void' is not assignable…）。
// 所以这里用别名导入实体，把全局的 Area 留给 onAreaChange。
import { Area as CampusArea, Marker, NodeDraft, PhotoKind, Room, Track, TrackPhoto, TrackPoint, TrackTag, markerNameForNote, markerTypeForNote } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { photoUrl } from '../sensors/TrackMedia';
import { TrackRecorder } from '../sensors/TrackRecorder';
import { compassDir, fmtDuration, fmtTime } from '../common/Utils';
import { Theme } from '../common/Theme';
import { Chip, PillButton } from '../common/Widgets';
import { AreaTagGroup, RoomDraft, canPlanRooms, effectiveAreaId, groupClassroomTagsByArea, planRooms } from '../common/RoomPlan';
import { DrawStyle, FloorLevel, NodePin, TrackPlan, View3D, buildFloors, buildPlan, drawTrack3D, heightSourceLabel, pinFrom, weakAccuracyLimit, weakFix } from '../common/Track3D';
import { FloorProbe } from '../common/FloorMatch';
import { EditNodeDialog } from './CaptureDialogs';

/**
 * 视角预设（用户 2026-09-29 要求默认改成「去楼盘俯视那些沙盘模型」的观感）。
 *  - 楼盘：高俯角往斜下看 —— 平面布局占主导、高度只作一点竖向起伏，正好像看沙盘；
 *          90° 就完全看不见高度了，所以取 60° 而不是纯俯视。偏航小幅偏转让平面有立体感。
 *  - 侧视：低俯角，看竖向高度差最直观（原来的默认视角）
 */
const VIEW_MODEL_YAW: number = -30;
const VIEW_MODEL_PITCH: number = 60;
const VIEW_SIDE_YAW: number = -32;
const VIEW_SIDE_PITCH: number = 34;

/**
 * 俯仰角上限（度）。用户 2026-09-29 明确要求「不允许完全俯视」：
 * 到了 90° 就完全看不见高度，而且楼层图层会全部叠成一坨（正是他说的「太密集」）。
 * 72° 还看得出竖向起伏、又足够像俯视沙盘；想更平就把这个值调小，只改这一处。
 */
const PITCH_MAX: number = 72;

/** 三维画布配色：实色全部引用主题令牌，半透明色取自 Theme 的画布令牌（换主色只改 Theme 一处） */
const TRACK3D_STYLE: DrawStyle = {
  lineFade: Theme.CANVAS_LINE_FADE,
  start: Theme.GREEN,
  end: Theme.DANGER,
  pin: Theme.RED,
  pinEstimatedFill: Theme.CARD,
  pinText: Theme.RED,
  floor: Theme.CANVAS_FLOOR,
  floorStroke: Theme.CANVAS_FLOOR_STROKE,
  floorText: Theme.CANVAS_FLOOR_TEXT,
  labelBg: Theme.CANVAS_LABEL_BG
};

@Component
export struct TrackDetailPage {
  trackId: number = -1;
  onBack: () => void = () => {
  };
  /** 打开该轨迹的全屏相册页；startIndex=-1 表示从网格开始看 */
  onOpenGallery: (id: number, startIndex: number) => void = (id: number, startIndex: number) => {
  };
  @State track: Track | undefined = undefined;
  @State points: TrackPoint[] = [];
  @State tags: TrackTag[] = [];
  @State photos: TrackPhoto[] = [];
  /** 区域清单：节点的「所在建筑」和「生成房间」都按它显示/分楼（用别名类型，见文件头的说明） */
  @State areas: CampusArea[] = [];
  /**
   * 两个折叠开关（用户 2026-09-29 要求「详细信息、采样点可以收缩起来」）。
   * 统计只有 8 行、进来就要看，所以默认展开；采样点动辄几百条，默认收起 ——
   * 收起时那一整棵 ForEach 子树根本不会被建出来，长轨迹打开也顺带快了很多。
   */
  @State statsOpen: boolean = true;
  @State pointsOpen: boolean = false;
  @State plan: TrackPlan = {
    heightSource: 'none', samples: [], sampleTimes: [], accuracies: [], noGeoCount: 0,
    minZ: 0, maxZ: 0, zScale: 1, hasOrigin: false, lat0: 0, lng0: 0, altBase: 0, pBase: 0
  };
  @State pins: NodePin[] = [];
  /** 楼层图层：来自节点里手填的「楼层」（一个都没填时 Track3D 会退回按米数分层） */
  @State floors: FloorLevel[] = [];
  /** 已经画到立体图上的节点 id（列表里给这些节点标序号，与图上标签一一对应） */
  @State pinnedTagIds: number[] = [];
  /** 三维视角：偏航 / 俯仰（4°≈侧视，60°≈楼盘沙盘俯视，90°=正俯视）/ 缩放 */
  @State yawDeg: number = VIEW_MODEL_YAW;
  @State pitchDeg: number = VIEW_MODEL_PITCH;
  @State zoom: number = 1;
  private panBaseYaw: number = VIEW_MODEL_YAW;
  private panBasePitch: number = VIEW_MODEL_PITCH;
  private pinchBaseZoom: number = 1;

  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasW = 0;
  private canvasH = 0;

  /**
   * 「修改节点」对话框（用户 2026-09-29 要求：标记错了要能在 APP 里改）。
   * 控制器与「当前正在编辑的节点」都复用同一份，靠提供者在每次打开时取最新值 ——
   * 直接传值的话，控制器只创建一次，之后点别的节点拿到的还是第一个节点。
   * boundRoomId 是编辑中那个节点当前绑定的房间（异步查出来的，所以要在打开对话框**之前**填好，
   * 否则对话框里的房间下拉会预选不上）。
   */
  private editingTag: TrackTag | undefined = undefined;
  private boundRoomId: number = -1;
  private editDialog: CustomDialogController | null = null;

  private reload = (): void => {
    Store.getTrack(this.trackId).then((t: Track | undefined) => {
      if (t) {
        this.track = t;
      }
    });
    Store.listPoints(this.trackId).then((pts: TrackPoint[]) => {
      this.points = pts;
      this.rebuild3D(pts, this.tags);
    });
    Store.listTrackTags(this.trackId).then((ts: TrackTag[]) => {
      this.tags = ts;
      this.rebuild3D(this.points, ts);
    });
    Store.listTrackPhotos(this.trackId).then((ps: TrackPhoto[]) => {
      this.photos = ps;
    });
    Store.listAreas().then((as: CampusArea[]) => {
      this.areas = as;
    });
  };

  /** 图上标签文字：序号 + 类型 + 楼层 + 备注（序号与下面的节点列表一致） */
  private pinLabel(index: number, g: TrackTag): string {
    let s = `${index + 1} ${g.tagType}`;
    if (g.floor.length > 0) {
      s += ` ${g.floor}`;
    }
    const note: string = g.note.trim();
    if (note.length > 0) {
      s += ` · ${note.length > 10 ? `${note.substring(0, 10)}…` : note}`;
    }
    return s;
  }

  /** 节点在列表里的序号（从 1 开始），与图上标签的序号一致 */
  private nodeNumber(tagId: number): number {
    return this.tags.findIndex((t: TrackTag) => t.id === tagId) + 1;
  }

  /** 重算三维数据：轨迹平面 → 节点标注（与轨迹共用原点与高度基准） */
  private rebuild3D(pts: TrackPoint[], tags: TrackTag[]): void {
    const p: TrackPlan = buildPlan(pts);
    this.plan = p;
    // 图层跟着**实际填过的楼层**走（用户要求），不再按高度米数切
    this.floors = buildFloors(tags, p);
    const out: NodePin[] = [];
    const ids: number[] = [];
    for (let i = 0; i < tags.length; i++) {
      const g: TrackTag = tags[i];
      const pin = pinFrom(g.latitude, g.longitude, g.altitude, g.accuracy, g.timeMs,
        this.pinLabel(i, g), p);
      if (pin !== undefined) {
        out.push(pin);
        ids.push(g.id);
      }
    }
    this.pins = out;
    this.pinnedTagIds = ids;
    this.draw3d();
  }

  /** 位置是按时间推算出来的节点数量（没定位的 + 定位精度太差的，两者都算「没有可用定位」） */
  private estimatedPinCount(): number {
    let c = 0;
    for (const p of this.pins) {
      if (p.estimated === true) {
        c++;
      }
    }
    return c;
  }

  /**
   * 定位精度偏弱的采样点数（= 图上画淡的那些）。
   * 直接数 plan.accuracies 而不是 this.points：前者只含**真正画到图上**的点，
   * 免得把被排除掉的网络定位点也算进来。
   */
  private weakTrackCount(): number {
    let c = 0;
    for (const a of this.plan.accuracies) {
      if (weakFix(a)) {
        c++;
      }
    }
    return c;
  }

  // ---------- 区域显示 ----------

  /** 轨迹本身归属的区域 id（未分区/旧数据用 0 表示） */
  private trackAreaId(): number {
    const aId: number | undefined = this.track ? this.track.areaId : undefined;
    return aId === undefined ? UNASSIGNED_AREA_ID : aId;
  }

  private areaLabelOfId(id: number): string {
    if (id <= 0) {
      return '未分区';
    }
    for (const a of this.areas) {
      if (a.id === id) {
        return a.name;
      }
    }
    return `区域 #${id}`;
  }

  /** 节点实际归属的区域名（节点自己写的优先，没写就沿用轨迹的区域）；空 = 没有区域 */
  private nodeAreaLabel(g: TrackTag): string {
    const id: number = effectiveAreaId(g, this.trackAreaId());
    return id <= 0 ? '' : this.areaLabelOfId(id);
  }

  /** 节点区域简称（如 AC1）：只在「和轨迹自身的区域不同」时返回，避免单楼轨迹里满屏重复 */
  private nodeAreaShort(g: TrackTag): string {
    const label: string = this.nodeAreaLabel(g);
    if (label.length === 0 || label === this.areaLabelOfId(this.trackAreaId())) {
      return '';
    }
    const parts: string[] = label.split(' ');
    return parts.length > 0 ? parts[0] : label;
  }

  // ---------- 按轨迹生成房间 ----------

  /** 能不能生成房间：至少有一个「教室」节点归到了真实区域（未分区/没选区域的不能建房） */
  private canGenerateRooms(): boolean {
    return canPlanRooms(this.tags, this.trackAreaId());
  }

  /**
   * 一键按轨迹建房间：只有「教室」节点会建房（用户确认的口径）。
   * 2026-09-29 起**按节点各自的区域分楼建**：一条跨楼轨迹里，AC1 的教室建进 AC1、
   * AC2 的建进 AC2，同名只在本楼里算重复。生成前把「哪栋楼建哪几间」列出来给人确认。
   */
  private generateRooms(): void {
    const track: Track | undefined = this.track;
    if (track === undefined) {
      return;
    }
    const groups: AreaTagGroup[] = groupClassroomTagsByArea(this.tags, this.trackAreaId());
    if (groups.length === 0) {
      promptAction.showToast({ message: '没有可新建的房间：「教室」节点都还没归到具体区域' });
      return;
    }
    const drafts: RoomDraft[] = [];
    let pending: Promise<void> = Promise.resolve();
    for (const g of groups) {
      pending = pending.then((): Promise<void> => {
        return Store.listRooms(g.areaId).then((rooms: Room[]) => {
          const names: string[] = [];
          for (const r of rooms) {
            names.push(r.name);
          }
          const part: RoomDraft[] = planRooms(g.tags, names, track.name, g.areaId);
          for (const d of part) {
            drafts.push(d);
          }
        });
      });
    }
    pending.then((): void => {
      if (drafts.length === 0) {
        promptAction.showToast({ message: '没有可新建的房间：同名房间在该楼里已经存在' });
        return;
      }
      this.confirmCreateRooms(drafts);
    }).catch((e: Error) => {
      promptAction.showToast({ message: `生成房间失败：${e.message}` });
    });
  }

  /** 生成前确认：按楼分组列出要建的房间名（同名房间由 RoomPlan 在那栋楼里去重） */
  private confirmCreateRooms(drafts: RoomDraft[]): void {
    const lines: string[] = [];
    const seen: number[] = [];
    let shown = 0;
    for (const d of drafts) {
      if (seen.indexOf(d.areaId) < 0) {
        seen.push(d.areaId);
        lines.push(`【${this.areaLabelOfId(d.areaId)}】`);
      }
      // 只列前 14 间，避免对话框被撑爆
      if (shown < 14) {
        lines.push(`  · ${d.name}`);
        shown++;
      }
    }
    if (drafts.length > shown) {
      lines.push(`  … 还有 ${drafts.length - shown} 间`);
    }
    promptAction.showDialog({
      title: `建 ${drafts.length} 个房间（${seen.length} 栋楼）`,
      message: `${lines.join('\n')}\n\n只有「教室」节点会建房，各建到节点自己所属的建筑区域；`
        + `同名房间在该楼里自动跳过。`,
      buttons: [
        { text: '取消', color: Theme.INK2 },
        { text: `创建 ${drafts.length} 个`, color: Theme.RED }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        this.createRooms(drafts);
      }
    }).catch(() => {
    });
  }

  /** 逐个落库（串行，避免并发写库），有坐标的一并写入房间基准点 */
  private createRooms(drafts: RoomDraft[]): void {
    let pending: Promise<void> = Promise.resolve();
    for (const d of drafts) {
      pending = pending.then((): Promise<void> => {
        return Store.insertRoom(d.name, d.note, d.areaId).then((id: number) => {
          if (d.latitude !== undefined || d.longitude !== undefined) {
            return Store.updateRoomBase(id, d.latitude, d.longitude, d.altitude);
          }
          return Promise.resolve();
        });
      });
    }
    pending.then(() => {
      promptAction.showToast({ message: `已创建 ${drafts.length} 个房间` });
    }).catch((e: Error) => {
      promptAction.showToast({ message: `建房间失败：${e.message}` });
    });
  }

  // ---------- 事后修正节点（用户 2026-09-29 要求） ----------

  /**
   * 点节点行 → 打开修改对话框。
   * 先把这个节点当前绑定的房间查出来（靠节点记的 markerId），再开对话框 ——
   * 异步查，所以对话框要等查到才开，否则房间下拉会预选不上。
   */
  private openEdit(g: TrackTag): void {
    this.editingTag = g;
    this.boundRoomId = -1;
    const mk: number = g.markerId === undefined ? 0 : g.markerId;
    if (mk > 0) {
      Store.getMarker(mk).then((m: Marker | undefined) => {
        this.boundRoomId = m === undefined ? -1 : m.roomId;
        this.openEditNow();
      }).catch(() => {
        this.openEditNow();
      });
    } else {
      this.openEditNow();
    }
  }

  private openEditNow(): void {
    if (this.editDialog === null) {
      this.editDialog = new CustomDialogController({
        builder: EditNodeDialog({
          tagProvider: (): TrackTag | undefined => {
            return this.editingTag;
          },
          boundRoomProvider: (): number => {
            return this.boundRoomId;
          },
          trackAreaIdProvider: (): number => {
            return this.trackAreaId();
          },
          onSave: (tagId: number, draft: NodeDraft): void => {
            this.applyEdit(tagId, draft);
          },
          onDelete: (tagId: number): void => {
            this.confirmDeleteTag(tagId);
          }
        }),
        customStyle: false
      });
    }
    this.editDialog.open();
  }

  /**
   * 落库修改：先改节点本身，再让「房间标记」跟上（见 Store.syncTagMarker 的三种情况）。
   * 顺带把这个节点填的楼层学进楼层高度索引 —— 手改过的楼层是最可信的样本。
   */
  private applyEdit(tagId: number, draft: NodeDraft): void {
    let found: TrackTag | undefined = undefined;
    for (const t of this.tags) {
      if (t.id === tagId) {
        found = t;
        break;
      }
    }
    if (found === undefined) {
      promptAction.showToast({ message: '节点已不在了，可能刚被删掉' });
      return;
    }
    const old: TrackTag = found;
    const markerName: string = markerNameForNote(draft.note, draft.tagType);
    const markerType: string = markerTypeForNote(draft.note);
    const oldMarker: number = old.markerId === undefined ? 0 : old.markerId;
    Store.updateTrackTag(old.id, draft.tagType, draft.note, draft.floor, draft.areaId)
      .then((): Promise<number> => {
        return Store.syncTagMarker(old.id, oldMarker, draft.roomId, markerName, markerType,
          old.latitude, old.longitude, old.altitude, old.pressureHpa);
      })
      .then((markerId: number) => {
        if (draft.floor.length > 0 && draft.areaId > 0) {
          const probe: FloorProbe = { pressureHpa: old.pressureHpa, altitude: old.altitude };
          Store.learnFloorHeight(draft.areaId, draft.floor, probe).catch(() => {
          });
        }
        const roomPart: string = draft.roomId > 0 ? ` · 已绑到「${draft.roomName}」` : '';
        promptAction.showToast({ message: `已更新节点「${draft.tagType}」${roomPart}` });
      })
      .catch((e: Error) => {
        promptAction.showToast({ message: `修改失败：${e.message}` });
      });
  }

  /** 删除节点前确认（照片会一起删掉，不可恢复） */
  private confirmDeleteTag(tagId: number): void {
    promptAction.showDialog({
      title: '删除这个节点？',
      message: '它和它拍的照片会一起删掉，删了就找不回来了。',
      buttons: [
        { text: '取消', color: Theme.INK2 },
        { text: '删除', color: Theme.DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index !== 1) {
        return;
      }
      // 删除成功后 Store 会 notify，页面照常刷新（reload 已订阅）
      Store.deleteTrackTag(tagId).then(() => {
        promptAction.showToast({ message: '节点已删除' });
      }).catch((e: Error) => {
        promptAction.showToast({ message: `删除失败：${e.message}` });
      });
    }).catch(() => {
    });
  }

  /**
   * 删除整条轨迹（用户 2026-09-29 要求「轨迹记录可以单独删除」）。
   * 采样点、节点、照片都会一起删掉且不可恢复，所以必须确认；
   * 删完直接返回列表 —— 留在详情页只会看到一片空白，还以为没删掉。
   */
  private confirmDeleteTrack(): void {
    const name: string = this.track ? this.track.name : `轨迹 ${this.trackId}`;
    promptAction.showDialog({
      title: '删除这条轨迹？',
      message: `「${name}」\n${this.points.length} 个采样点、${this.tags.length} 个节点、`
        + `${this.photos.length} 张照片会一起删掉，删了就找不回来了。`,
      buttons: [
        { text: '取消', color: Theme.INK2 },
        { text: '删除', color: Theme.DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index !== 1) {
        return;
      }
      // 正在记录的那条不能删：记录线程还在往里写采样点，删掉会留下一条写不进去的野记录
      if (TrackRecorder.get().getTrackId() === this.trackId) {
        promptAction.showToast({ message: '这条轨迹正在记录中，先停止记录再删' });
        return;
      }
      Store.deleteTrack(this.trackId).then(() => {
        promptAction.showToast({ message: '已删除轨迹' });
        this.onBack();
      }).catch((e: Error) => {
        promptAction.showToast({ message: `删除失败：${e.message}` });
      });
    }).catch(() => {
    });
  }

  aboutToAppear(): void {
    this.reload();
    Store.subscribe(this.reload);
  }
  aboutToDisappear(): void {
    Store.unsubscribe(this.reload);
  }

  private draw3d(): void {
    if (this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    const view: View3D = { yawDeg: this.yawDeg, pitchDeg: this.pitchDeg, zoom: this.zoom };
    drawTrack3D(this.ctx, this.plan, this.pins, this.floors, view, this.canvasW, this.canvasH,
      TRACK3D_STYLE);
  }

  private clampPitch(v: number): number {
    if (v < 4) {
      return 4;
    }
    // 上限 PITCH_MAX：不允许拖到完全俯视（用户 2026-09-29 要求）
    if (v > PITCH_MAX) {
      return PITCH_MAX;
    }
    return v;
  }

  /** 当前俯角是否接近某个预设（用来把对应的视角按钮点亮） */
  private nearPitch(target: number): boolean {
    return Math.abs(this.pitchDeg - target) < 6;
  }

  private heightReadout(): string {
    if (this.plan.heightSource === 'none') {
      return heightSourceLabel(this.plan.heightSource);
    }
    const range = Math.round(this.plan.maxZ - this.plan.minZ);
    return `高差 ${range >= 0 ? '+' : ''}${range} m · ${heightSourceLabel(this.plan.heightSource)}`;
  }

  private nodePhotos(tagId: number): TrackPhoto[] {
    return this.photos.filter((ph: TrackPhoto) => {
      return ph.kind === PhotoKind.NODE && ph.tagId === tagId;
    });
  }

  private sceneryPhotos(): TrackPhoto[] {
    return this.photos.filter((ph: TrackPhoto) => {
      return ph.kind === PhotoKind.SCENERY;
    });
  }

  private photoIndex(ph: TrackPhoto): number {
    return this.photos.findIndex((x: TrackPhoto) => x.id === ph.id);
  }

  private pointSub(p: TrackPoint): string {
    let s = p.latitude !== undefined
      ? `${(p.latitude as number).toFixed(5)}, ${(p.longitude as number).toFixed(5)}` : '无 GPS';
    // 精度差的点标出来：实测里室内那张「定位」常常是误差一两百米的网络定位，
    // 它在列表里看着像坐标，其实不能用（3D 图里已经不画了，这里也如实标一下）
    if (p.accuracy !== undefined) {
      s += p.accuracy <= 50 ? `（±${p.accuracy.toFixed(0)} m）` : `（±${p.accuracy.toFixed(0)} m，未采用）`;
    }
    if (p.headingDeg !== undefined) {
      s += `  ·  朝 ${p.headingDeg.toFixed(0)}° ${compassDir(p.headingDeg)}`;
    }
    if (p.magneticX !== undefined) {
      const x = p.magneticX;
      const y = p.magneticY as number;
      const z = p.magneticZ as number;
      const mm = Math.sqrt(x * x + y * y + z * z);
      s += `  ·  |B|=${mm.toFixed(0)} µT`;
    }
    s += `  ·  WiFi ${p.wifiCount} 个`;
    return s;
  }

  private nodeSub(g: TrackTag): string {
    let s = fmtTime(g.timeMs);
    if (g.headingDeg !== undefined) {
      s += ` · 朝 ${g.headingDeg.toFixed(0)}° ${compassDir(g.headingDeg)}`;
    }
    if (g.latitude !== undefined && g.longitude !== undefined) {
      s += ` · ${g.latitude.toFixed(5)}, ${g.longitude.toFixed(5)}`;
    }
    // 精度也标出来（与采样点同一套写法）：室内那种一两百米的网络定位既不画在图上
    // （pinFrom 会退成按时间推算的空心圆），这里也要如实说，别让它看着像实测坐标
    if (g.accuracy !== undefined) {
      s += g.accuracy <= 50 ? `（±${g.accuracy.toFixed(0)} m）` : `（±${g.accuracy.toFixed(0)} m，未采用）`;
    }
    if (g.altitude !== undefined) {
      s += ` · ${g.altitude.toFixed(1)} m`;
    }
    return s;
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 10 }) {
        PillButton({
          label: '‹ 返回',
          onTap: (): void => {
            this.onBack();
          }
        })
        Text(this.track ? this.track.name : '轨迹详情')
          .fontSize(Theme.F_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.photos.length > 0) {
          PillButton({
            label: `相册 ${this.photos.length}`,
            kind: 'solid',
            onTap: (): void => {
              this.onOpenGallery(this.trackId, -1);
            }
          })
        }
        // 整条轨迹的删除（与列表页的删除按钮同一种样式，确认框也一致）
        PillButton({
          label: '删除',
          kind: 'danger',
          onTap: (): void => {
            this.confirmDeleteTrack();
          }
        })
      }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: Theme.GAP }) {
          // 统计
          //
          // ⚠️ 这里的每一行都**刻意直接写出来**，没有用「带参数的 @Builder」。
          // 原因：@Builder 默认按值传参，**按值传递时参数变化不会引起 Builder 内的 UI 刷新**
          // （要做成刷新的得按引用传对象）。轨迹数据是异步加载的，页面第一帧 this.track 还是
          // undefined，那一次渲染算出来的 '-' / '进行中' 就被永久固定住了 —— 真机上的表现就是
          // 统计卡片一直是空的。页面标题能正常显示轨迹名（那是内联表达式，会刷新），只有这个卡片不刷新，
          // 这就是差别所在。以后重构别再改回 @Builder，除非改用按引用传参。
          Column({ space: 7 }) {
            // 点标题整行收起/展开（用户 2026-09-29 要求）。用文字而不是图标：不用新增资源、
            // 也不会像箭头那样在小字号下看不清；「收起 / 展开」本身就把当前状态说清楚了。
            Row({ space: 8 }) {
              Text('统计').fontSize(Theme.F_SECTION).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
              Blank()
              Text(this.statsOpen ? '收起 ▾' : '展开 ▸')
                .fontSize(Theme.F_META)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.RED)
            }
            .width('100%')
            .onClick(() => {
              this.statsOpen = !this.statsOpen;
            })

            if (this.statsOpen) {
              Row() {
                Text('区域').fontSize(13).fontColor(Theme.INK2).width(72)
                Text(this.track
                  ? (this.track.areaName !== undefined ? this.track.areaName : '未分区') : '-')
                  .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%')
              Row() {
                Text('开始').fontSize(13).fontColor(Theme.INK2).width(72)
                Text(this.track ? fmtTime(this.track.startedAt) : '-')
                  .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%')
              Row() {
                Text('结束').fontSize(13).fontColor(Theme.INK2).width(72)
                Text(this.track && this.track.endedAt !== undefined
                  ? fmtTime(this.track.endedAt as number) : (this.track ? '进行中' : '-'))
                  .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%')
              Row() {
                Text('时长').fontSize(13).fontColor(Theme.INK2).width(72)
                Text(this.track
                  ? fmtDuration(Math.floor(((this.track.endedAt !== undefined
                    ? this.track.endedAt : Date.now()) - this.track.startedAt) / 1000)) : '-')
                  .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%')
              Row() {
                Text('采样点').fontSize(13).fontColor(Theme.INK2).width(72)
                Text(`${this.points.length}`)
                  .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%')
              Row() {
                Text('节点').fontSize(13).fontColor(Theme.INK2).width(72)
                Text(`${this.tags.length}`)
                  .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%')
              Row() {
                Text('照片').fontSize(13).fontColor(Theme.INK2).width(72)
                Text(`${this.photos.length - this.sceneryPhotos().length} 张节点照 · ${this.sceneryPhotos().length} 张风景照`)
                  .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%')
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.CARD)
          .borderRadius(Theme.R_CARD)
          .border({ width: 2, color: Theme.LINE })

          // 三维轨迹图：可拖动旋转、双指缩放，节点名标在对应位置
          if (this.plan.samples.length >= 2) {
            Column({ space: 10 }) {
              Row({ space: 6 }) {
                Chip({ text: '轨迹立体图', kind: 'tag', iconKey: 'floor' })
                Blank()
                PillButton({
                  label: '楼盘',
                  kind: this.nearPitch(VIEW_MODEL_PITCH) ? 'solid' : 'plain',
                  onTap: (): void => {
                    this.yawDeg = VIEW_MODEL_YAW;
                    this.pitchDeg = VIEW_MODEL_PITCH;
                    this.draw3d();
                  }
                })
                PillButton({
                  label: '侧视',
                  kind: this.nearPitch(VIEW_SIDE_PITCH) ? 'solid' : 'plain',
                  onTap: (): void => {
                    this.yawDeg = VIEW_SIDE_YAW;
                    this.pitchDeg = VIEW_SIDE_PITCH;
                    this.draw3d();
                  }
                })
              }.width('100%')

              Canvas(this.ctx)
                .width('100%')
                .height(260)
                .backgroundColor(Theme.CARD_SOFT)
                .borderRadius(Theme.R_THUMB)
                .border({ width: 2, color: Theme.LINE })
                .onReady(() => {
                  this.draw3d();
                })
                .onAreaChange((oldA: Area, newA: Area) => {
                  this.canvasW = Number(newA.width);
                  this.canvasH = Number(newA.height);
                  this.draw3d();
                })
                .gesture(
                  GestureGroup(GestureMode.Parallel,
                    PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
                      .onActionStart(() => {
                        this.panBaseYaw = this.yawDeg;
                        this.panBasePitch = this.pitchDeg;
                      })
                      .onActionUpdate((event: GestureEvent) => {
                        this.yawDeg = this.panBaseYaw + event.offsetX * 0.4;
                        this.pitchDeg = this.clampPitch(this.panBasePitch - event.offsetY * 0.3);
                        this.draw3d();
                      }),
                    PinchGesture({ fingers: 2 })
                      .onActionStart(() => {
                        this.pinchBaseZoom = this.zoom;
                      })
                      .onActionUpdate((event: GestureEvent) => {
                        const z = this.pinchBaseZoom * event.scale;
                        this.zoom = z < 0.5 ? 0.5 : (z > 4 ? 4 : z);
                        this.draw3d();
                      })
                  )
                )

              Text('默认楼盘沙盘视角（最高 72°，不允许完全俯视）· 按住拖动旋转 · 双指缩放 · '
                + '四边的东南西北跟着视角转（只按偏航，与地图的用法一致）')
                .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')

              // 楼层图层的来源说明：让用户知道层数是跟着自己填的楼层走的
              if (this.floors.length > 0) {
                Text(`楼层图层 ${this.floors.length} 层：${this.floors.map((f: FloorLevel) => f.name).join(' / ')}`
                  + '（来自节点里填的楼层）')
                  .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              } else {
                Text('节点里都没填楼层，图层暂按高度每 2 m 切一层；填上楼层的节点会按楼层显示')
                  .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              }
              Text(this.heightReadout()).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              // 线型图例：为什么有些段是淡的（用户 2026-09-30 要求分级显示可信度）
              Text(`轨迹线按定位可信度分级：精度好于 ${weakAccuracyLimit()} m 的实心，差于它的画淡`
                + (this.weakTrackCount() > 0 ? `（这条有 ${this.weakTrackCount()} 个点偏弱，多半在室内）` : '')
                + `；差于 50 m 的（网络定位）不画`)
                .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              if (this.plan.zScale < 0.999) {
                Text(`为看清平面走向，图中的竖向已压到真实高度的 ${Math.round(this.plan.zScale * 100)}%；`
                  + `上面的高差与高度层上的数字仍是真实值`)
                  .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              }
              if (this.plan.noGeoCount > 0) {
                Text(`有 ${this.plan.noGeoCount} 个采样点没有可用定位（室内常见），未画进图里；`
                  + `室内拿到的「定位」常常是误差一两百米的网络定位，这种也不采用（下面的列表里仍然有）`)
                  .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              }
              if (this.estimatedPinCount() > 0) {
                Text(`${this.estimatedPinCount()} 个节点没有可用定位（没拿到定位，或精度差于 50 m），`
                  + `位置按时间就近推算（空心圆），不是实测坐标`)
                  .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              }
              if (this.tags.length > 0 && this.pins.length < this.tags.length) {
                Text(`${this.tags.length - this.pins.length} 个节点摆不到图上（这条轨迹没有可用的定位原点），`
                  + `下面的节点列表里仍然看得到`)
                  .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD)
            .border({ width: 2, color: Theme.LINE })
          }

          // 节点：每个节点 = 标记 + 照片
          if (this.tags.length > 0) {
            Column({ space: 12 }) {
              Row({ space: 8 }) {
                Text(`节点（${this.tags.length}）`).fontSize(Theme.F_SECTION)
                  .fontWeight(FontWeight.Bold).fontColor(Theme.INK)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.canGenerateRooms()) {
                  PillButton({
                    label: '生成房间',
                    kind: 'accent',
                    onTap: (): void => {
                      this.generateRooms();
                    }
                  })
                } else {
                  Text('标记 + 照片').fontSize(Theme.F_META).fontColor(Theme.INK2)
                }
              }.width('100%')

              Text(this.canGenerateRooms()
                ? '序号与图上标签一致；点某一行可以改它的类型 / 楼层 / 区域 / 所在房间，也能删掉；'
                  + '「生成房间」会把教室节点按各自所属建筑建成房间'
                : '序号与图上标签一致；点某一行可以改它的类型 / 楼层 / 区域 / 所在房间，也能删掉')
                .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')

              ForEach(this.tags, (g: TrackTag) => {
                Row({ space: 12 }) {
                  if (this.nodePhotos(g.id).length > 0) {
                    Image(photoUrl(this.nodePhotos(g.id)[0].filePath))
                      .width(76)
                      .height(76)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(Theme.R_THUMB)
                      .onClick(() => {
                        this.onOpenGallery(this.trackId, this.photoIndex(this.nodePhotos(g.id)[0]));
                      })
                  } else {
                    Column() {
                      Text('无照片').fontSize(10).fontColor(Theme.INK2)
                    }
                    .width(76)
                    .height(76)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(Theme.PLACEHOLDER)
                    .borderRadius(Theme.R_THUMB)
                  }

                  Column({ space: 5 }) {
                    Row({ space: 6 }) {
                      if (this.pinnedTagIds.indexOf(g.id) >= 0) {
                        Column() {
                          Text(`${this.nodeNumber(g.id)}`)
                            .fontSize(11)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(Theme.ON_RED)
                        }
                        .width(18)
                        .height(18)
                        .justifyContent(FlexAlign.Center)
                        .backgroundColor(Theme.RED)
                        .borderRadius(Theme.R_CHIP)
                      }
                      Chip({ text: g.tagType, kind: 'tag', iconKey: g.tagType })
                      if (g.floor.length > 0) {
                        Chip({ text: g.floor, kind: 'floor', iconKey: 'floor' })
                      }
                      if (this.nodeAreaShort(g).length > 0) {
                        Chip({ text: this.nodeAreaShort(g), kind: 'plain', iconKey: 'floor' })
                      }
                    }
                    if (g.note.length > 0) {
                      Text(g.note).fontSize(13.5).fontColor(Theme.INK).width('100%')
                    }
                    Text(this.nodeSub(g)).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
                // 点整行（照片除外：照片自己的 onClick 会先接住，点到就去相册）→ 打开「修改节点」。
                // 用户 2026-09-29 挑的入口方式：标记错了直接在原地改，不用重新采。
                .onClick(() => {
                  this.openEdit(g);
                })
              }, (g: TrackTag) => g.id + '')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD)
            .border({ width: 2, color: Theme.LINE })
          }

          // 风景照：宣传美化用，不属于节点
          if (this.sceneryPhotos().length > 0) {
            Column({ space: 12 }) {
              Row({ space: 6 }) {
                Chip({ text: '风景照', kind: 'scene', iconKey: 'scene' })
                Text(`${this.sceneryPhotos().length} 张 · 不参与节点`)
                  .fontSize(Theme.F_META).fontColor(Theme.INK2)
                Blank()
              }.width('100%')
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.sceneryPhotos(), (ph: TrackPhoto) => {
                  Column({ space: 4 }) {
                    Image(photoUrl(ph.filePath))
                      .width(84)
                      .height(84)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(Theme.R_THUMB)
                      .onClick(() => {
                        this.onOpenGallery(this.trackId, this.photoIndex(ph));
                      })
                    Text(fmtTime(ph.timeMs)).fontSize(10).fontColor(Theme.INK2)
                  }.alignItems(HorizontalAlign.Start).margin({ right: 8, bottom: 8 })
                }, (ph: TrackPhoto) => ph.id + '')
              }.width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD)
            .border({ width: 2, color: Theme.LINE })
          }

          // 逐点采样（默认收起，见 pointsOpen 的注释）
          Column({ space: 0 }) {
            Row({ space: 8 }) {
              Text(`采样点（${this.points.length}）`).fontSize(Theme.F_SECTION)
                .fontWeight(FontWeight.Bold).fontColor(Theme.INK)
              Blank()
              Text(this.pointsOpen ? '收起 ▾' : '展开 ▸')
                .fontSize(Theme.F_META)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.RED)
            }
            .width('100%')
            .onClick(() => {
              this.pointsOpen = !this.pointsOpen;
            })

            if (this.pointsOpen) {
              ForEach(this.points, (p: TrackPoint) => {
                Column({ space: 4 }) {
                  Row() {
                    Text(fmtTime(p.timeMs)).fontSize(13).fontColor(Theme.INK)
                    Blank()
                    Text(p.pressureHpa !== undefined ? `${p.pressureHpa.toFixed(1)} hPa` : '')
                      .fontSize(12)
                      .fontColor(Theme.INK2)
                  }.width('100%')
                  Text(this.pointSub(p)).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                  if (p.wifiTop.length > 0) {
                    Text(`AP: ${p.wifiTop}`)
                      .fontSize(Theme.F_META)
                      .fontColor(Theme.INK2)
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }.width('100%').padding({ top: 8, bottom: 8 })
              }, (p: TrackPoint) => p.id + '')
            } else {
              // 收起状态给一句话说清「展开能看到什么」，不然只剩标题会以为没内容
              Text(this.points.length === 0
                ? '这条轨迹还没有采样点'
                : `每秒一条，共 ${this.points.length} 条：定位（含 ±精度）、气压、地磁、朝向、WiFi 个数与 AP 名单`)
                .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%').margin({ top: 8 })
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.CARD)
          .borderRadius(Theme.R_CARD)
          .border({ width: 2, color: Theme.LINE })
        }.padding({ left: Theme.PAD, right: Theme.PAD, bottom: 24 }).width('100%')
      }.layoutWeight(1).width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
