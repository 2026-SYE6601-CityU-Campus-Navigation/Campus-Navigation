import { promptAction } from '@kit.ArkUI';
import { PhotoKind, Room, Track, TrackPhoto, TrackPoint, TrackTag } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { photoUrl } from '../sensors/TrackMedia';
import { compassDir, fmtDuration, fmtTime } from '../common/Utils';
import { Theme } from '../common/Theme';
import { Chip, PillButton } from '../common/Widgets';
import { RoomDraft, countClassroomTags, planRooms } from '../common/RoomPlan';
import { DrawStyle, NodePin, TrackPlan, View3D, buildPlan, drawTrack3D, heightSourceLabel, pinFrom } from '../common/Track3D';

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
  @State plan: TrackPlan = {
    heightSource: 'none', samples: [], sampleTimes: [], noGeoCount: 0, minZ: 0, maxZ: 0, zScale: 1,
    hasOrigin: false, lat0: 0, lng0: 0, altBase: 0, pBase: 0
  };
  @State pins: NodePin[] = [];
  /** 已经画到立体图上的节点 id（列表里给这些节点标序号，与图上标签一一对应） */
  @State pinnedTagIds: number[] = [];
  /** 三维视角：偏航 / 俯仰（4°≈侧视，90°=正俯视）/ 缩放 */
  @State yawDeg: number = -32;
  @State pitchDeg: number = 34;
  @State zoom: number = 1;
  private panBaseYaw: number = -32;
  private panBasePitch: number = 34;
  private pinchBaseZoom: number = 1;

  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasW = 0;
  private canvasH = 0;

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
    const out: NodePin[] = [];
    const ids: number[] = [];
    for (let i = 0; i < tags.length; i++) {
      const g: TrackTag = tags[i];
      const pin = pinFrom(g.latitude, g.longitude, g.altitude, g.timeMs, this.pinLabel(i, g), p);
      if (pin !== undefined) {
        out.push(pin);
        ids.push(g.id);
      }
    }
    this.pins = out;
    this.pinnedTagIds = ids;
    this.draw3d();
  }

  /** 位置是按时间推算出来的节点数量（室内没有定位的节点） */
  private estimatedPinCount(): number {
    let c = 0;
    for (const p of this.pins) {
      if (p.estimated === true) {
        c++;
      }
    }
    return c;
  }

  // ---------- 按轨迹生成房间 ----------

  /** 能不能生成房间：得有「教室」节点，且轨迹已归属某个区域（未分区不能建房） */
  private canGenerateRooms(): boolean {
    const aId: number | undefined = this.track ? this.track.areaId : undefined;
    if (aId === undefined || aId === UNASSIGNED_AREA_ID) {
      return false;
    }
    return countClassroomTags(this.tags) > 0;
  }

  /**
   * 一键按轨迹建房间：只有「教室」节点会建房（用户确认的口径），
   * 生成前先把房间名列出来给人确认，同名房间由 RoomPlan 自动跳过。
   */
  private generateRooms(): void {
    const track: Track | undefined = this.track;
    if (track === undefined) {
      return;
    }
    const aId: number | undefined = track.areaId;
    if (aId === undefined || aId === UNASSIGNED_AREA_ID) {
      promptAction.showToast({ message: '未分区的轨迹不能建房间，请先把轨迹归入区域' });
      return;
    }
    const areaId: number = aId;
    Store.listRooms(areaId).then((rooms: Room[]) => {
      const names: string[] = [];
      for (const r of rooms) {
        names.push(r.name);
      }
      const drafts: RoomDraft[] = planRooms(this.tags, names, track.name);
      if (drafts.length === 0) {
        promptAction.showToast({ message: '没有可新建的房间：要么没有「教室」节点，要么同名房间已存在' });
        return;
      }
      const preview: string[] = [];
      const shown: number = drafts.length > 12 ? 12 : drafts.length;
      for (let i = 0; i < shown; i++) {
        preview.push(`· ${drafts[i].name}`);
      }
      if (drafts.length > shown) {
        preview.push(`… 还有 ${drafts.length - shown} 个`);
      }
      promptAction.showDialog({
        title: `按这条轨迹建 ${drafts.length} 个房间`,
        message: `${preview.join('\n')}\n\n只有「教室」节点会建房，同名房间自动跳过。`,
        buttons: [
          { text: '取消', color: Theme.INK2 },
          { text: `创建 ${drafts.length} 个`, color: Theme.RED }
        ]
      }).then((res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index === 1) {
          this.createRooms(drafts, areaId);
        }
      }).catch(() => {
      });
    });
  }

  /** 逐个落库（串行，避免并发写库），有坐标的一并写入房间基准点 */
  private createRooms(drafts: RoomDraft[], areaId: number): void {
    let pending: Promise<void> = Promise.resolve();
    for (const d of drafts) {
      pending = pending.then((): Promise<void> => {
        return Store.insertRoom(d.name, d.note, areaId).then((id: number) => {
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
    drawTrack3D(this.ctx, this.plan, this.pins, view, this.canvasW, this.canvasH, TRACK3D_STYLE);
  }

  private clampPitch(v: number): number {
    if (v < 4) {
      return 4;
    }
    if (v > 90) {
      return 90;
    }
    return v;
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
            Text('统计').fontSize(Theme.F_SECTION).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
              .width('100%')
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
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.CARD)
          .borderRadius(Theme.R_CARD)
          .border({ width: 2, color: Theme.LINE })

          // 三维轨迹图：可拖动旋转、双指缩放，节点名标在对应位置
          if (this.plan.samples.length >= 2) {
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Chip({ text: '轨迹立体图', kind: 'tag', iconKey: 'floor' })
                Blank()
                PillButton({
                  label: '3D',
                  kind: this.pitchDeg < 80 ? 'solid' : 'plain',
                  onTap: (): void => {
                    this.pitchDeg = 34;
                    this.draw3d();
                  }
                })
                PillButton({
                  label: '俯视',
                  kind: this.pitchDeg >= 80 ? 'solid' : 'plain',
                  onTap: (): void => {
                    this.pitchDeg = 90;
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

              Text('按住拖动旋转视角 · 双指缩放 · 节点名标在对应位置')
                .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              Text(this.heightReadout()).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              if (this.plan.zScale < 0.999) {
                Text(`为看清平面走向，图中的竖向已压到真实高度的 ${Math.round(this.plan.zScale * 100)}%；`
                  + `上面的高差与高度层上的数字仍是真实值`)
                  .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              }
              if (this.plan.noGeoCount > 0) {
                Text(`有 ${this.plan.noGeoCount} 个采样点没有定位（室内正常），未画进图里`)
                  .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
              }
              if (this.estimatedPinCount() > 0) {
                Text(`${this.estimatedPinCount()} 个节点没有定位，位置按时间就近推算（空心圆），不是实测坐标`)
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
                ? '序号与图上标签一致；「生成房间」会把教室节点建成区域里的房间'
                : '序号与图上标签一致')
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
                    }
                    if (g.note.length > 0) {
                      Text(g.note).fontSize(13.5).fontColor(Theme.INK).width('100%')
                    }
                    Text(this.nodeSub(g)).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }.width('100%')
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

          // 逐点采样
          Column({ space: 0 }) {
            Text(`采样点（${this.points.length}）`).fontSize(Theme.F_SECTION)
              .fontWeight(FontWeight.Bold).fontColor(Theme.INK).width('100%')
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
