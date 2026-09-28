import { promptAction } from '@kit.ArkUI';
import { Area, Room, Track } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { TrackRecorder } from '../sensors/TrackRecorder';
import { RecordingBanner } from './RecordingBanner';
import { StartTrackDialog } from './TrackList';
import { Exporter } from '../common/Exporter';
import { fmtDuration, fmtTime } from '../common/Utils';
import { Theme } from '../common/Theme';
import { PillButton, ThickButton } from '../common/Widgets';

@CustomDialog
struct AddRoomDialog {
  controller?: CustomDialogController;
  onSave?: (name: string, note: string) => void;
  @State name: string = '';
  @State note: string = '';

  build() {
    Column({ space: 14 }) {
      Text('添加房间').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
      TextInput({ placeholder: '房间名称（如：301 会议室）' })
        .fontSize(13.5)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((v: string) => {
          this.name = v;
        })
      TextInput({ placeholder: '备注（选填）' })
        .fontSize(13.5)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((v: string) => {
          this.note = v;
        })
      Row({ space: 10 }) {
        Column() {
          ThickButton({
            label: '取消',
            kind: 'ghost',
            compact: true,
            onTap: (): void => {
              this.controller?.close();
            }
          })
        }.layoutWeight(1)

        Column() {
          ThickButton({
            label: '保存并打开',
            kind: 'primary',
            compact: true,
            disabled: this.name.trim().length === 0,
            onTap: (): void => {
              this.controller?.close();
              if (this.onSave) {
                this.onSave(this.name.trim(), this.note.trim());
              }
            }
          })
        }.layoutWeight(1.4)
      }.width('100%')
    }
    .padding(18)
    .width('100%')
    .backgroundColor(Theme.CARD)
  }
}

/** 区域详情：该区域的房间 + 轨迹，支持开始记录 / 勾选导出 / 删除区域 */
@Component
export struct AreaDetailPage {
  areaId: number = UNASSIGNED_AREA_ID;
  onBack: () => void = () => {
  };
  onOpenRoom: (id: number) => void = (id: number) => {
  };
  onOpenTrack: (id: number) => void = (id: number) => {
  };
  @State area: Area | undefined = undefined;
  @State rooms: Room[] = [];
  @State tracks: Track[] = [];
  @State heartbeat: number = 0;
  /** 勾选导出模式：轨迹行显示复选框，可全选后只导出选中的几条 */
  @State selectMode: boolean = false;
  @State selectedIds: number[] = [];
  private timer: number = -1;

  private areaName(): string {
    if (this.areaId === UNASSIGNED_AREA_ID) {
      return '未分区';
    }
    return this.area ? this.area.name : '区域';
  }

  private isUnassigned(): boolean {
    return this.areaId === UNASSIGNED_AREA_ID;
  }

  private reload = (): void => {
    if (this.isUnassigned()) {
      this.area = {
        id: UNASSIGNED_AREA_ID,
        name: '未分区',
        note: '升级前的旧数据，尚未归属任何区域',
        roomCount: 0,
        trackCount: 0,
        createdAt: 0
      };
    } else {
      Store.getArea(this.areaId).then((a: Area | undefined) => {
        if (a) {
          this.area = a;
        }
      });
    }
    Store.listRooms(this.areaId).then((r: Room[]) => {
      this.rooms = r;
    });
    Store.listTracksInArea(this.areaId).then((t: Track[]) => {
      this.tracks = t;
    });
  };

  aboutToAppear(): void {
    this.reload();
    Store.subscribe(this.reload);
    this.timer = setInterval(() => {
      this.heartbeat++;
    }, 500);
  }

  aboutToDisappear(): void {
    Store.unsubscribe(this.reload);
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private addRoomDialog: CustomDialogController = new CustomDialogController({
    builder: AddRoomDialog({
      onSave: (name: string, note: string): void => {
        const n = name.trim();
        if (n.length === 0) {
          return;
        }
        Store.insertRoom(n, note.trim(), this.areaId).then((id: number) => {
          this.onOpenRoom(id);
        });
      }
    }),
    customStyle: false
  });

  private startDialog: CustomDialogController | null = null;

  /** 打开时动态构造（成员初始化阶段 this.areaId 可能尚未赋值，须在点击时读取） */
  private openStartDialog(): void {
    this.startDialog = new CustomDialogController({
      builder: StartTrackDialog({
        defaultAreaId: this.areaId,
        onStart: (name: string, areaId: number): void => {
          TrackRecorder.get().start(name, areaId).catch(() => {
            promptAction.showToast({ message: '启动记录失败' });
          });
        }
      }),
      customStyle: false
    });
    this.startDialog.open();
  }

  // ---------- 导出 ----------
  // 原来右上角还有一个「导出」按钮（整区一键打包），与「选择导出 → 全选」重复，
  // 已按用户要求删掉：导出统一走勾选模式，全选即等于整区导出。

  private enterSelect(): void {
    this.selectedIds = [];
    this.selectMode = true;
  }

  private exitSelect(): void {
    this.selectMode = false;
    this.selectedIds = [];
  }

  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleSelect(id: number): void {
    const next: number[] = this.selectedIds.slice();
    const i: number = next.indexOf(id);
    if (i >= 0) {
      next.splice(i, 1);
    } else {
      next.push(id);
    }
    // 数组重新赋值，@State 才会通知刷新
    this.selectedIds = next;
  }

  private allSelected(): boolean {
    return this.tracks.length > 0 && this.selectedIds.length >= this.tracks.length;
  }

  private toggleSelectAll(): void {
    if (this.allSelected()) {
      this.selectedIds = [];
      return;
    }
    const ids: number[] = [];
    for (const t of this.tracks) {
      ids.push(t.id);
    }
    this.selectedIds = ids;
  }

  private exportSelected(): void {
    const ids: number[] = this.selectedIds.slice();
    if (ids.length === 0) {
      promptAction.showToast({ message: '请先勾选要导出的轨迹' });
      return;
    }
    const name = this.areaName();
    promptAction.showToast({ message: `正在打包所选 ${ids.length} 条轨迹…` });
    Exporter.exportTracksZip(ids, this.areaId, name).then((zipName: string) => {
      promptAction.showToast({ message: `已导出 ${zipName}` });
      this.exitSelect();
    }).catch((e: Error) => {
      promptAction.showToast({ message: e.message });
    });
  }

  private deleteArea(): void {
    promptAction.showDialog({
      title: `删除区域「${this.areaName()}」`,
      message: `房间 ${this.rooms.length} 个 · 轨迹 ${this.tracks.length} 条。\n移入未分区：保留全部数据；彻底删除：数据与照片将全部丢失。`,
      buttons: [
        { text: '取消', color: Theme.INK2 },
        { text: '移入未分区', color: Theme.INK },
        { text: '彻底删除', color: Theme.DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        Store.moveAreaToUnassigned(this.areaId).then(() => {
          promptAction.showToast({ message: '已移入未分区' });
          this.onBack();
        });
      } else if (res.index === 2) {
        // 若正在记录该区域的轨迹，先停止，避免写入已删除的轨迹
        const rec = TrackRecorder.get();
        if (rec.isRunning()) {
          rec.stop().catch(() => {
          });
        }
        Store.deleteAreaCascade(this.areaId).then(() => {
          promptAction.showToast({ message: '区域已删除' });
          this.onBack();
        });
      }
    }).catch(() => {
    });
  }

  private trackSub(t: Track): string {
    const end = t.endedAt !== undefined ? t.endedAt : t.startedAt;
    let s =
      `${fmtTime(t.startedAt)} · 时长 ${fmtDuration(Math.floor((end - t.startedAt) / 1000))} · ${t.pointCount} 点`;
    if (t.endedAt === undefined) {
      s += ' · 进行中';
    }
    return s;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 顶栏
        Row({ space: 8 }) {
          PillButton({
            label: '‹ 返回',
            onTap: (): void => {
              this.onBack();
            }
          })
          Column({ space: 1 }) {
            Text(this.areaName())
              .fontSize(Theme.F_TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.INK)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`房间 ${this.rooms.length} · 轨迹 ${this.tracks.length}`)
              .fontSize(Theme.F_META)
              .fontColor(Theme.INK2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (!this.isUnassigned()) {
            PillButton({
              label: '删除',
              kind: 'danger',
              onTap: (): void => {
                this.deleteArea();
              }
            })
          }
        }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 10 })

        RecordingBanner()

        Scroll() {
          Column({ space: Theme.GAP }) {
            // 房间
            Column({ space: 10 }) {
              Row() {
                Text(`房间（${this.rooms.length}）`).fontSize(Theme.F_SECTION)
                  .fontWeight(FontWeight.Bold).fontColor(Theme.INK)
                Blank()
                PillButton({
                  label: '添加房间',
                  onTap: (): void => {
                    this.addRoomDialog.open();
                  }
                })
              }.width('100%')
              if (this.rooms.length === 0) {
                Text('该区域还没有房间').fontSize(13).fontColor(Theme.INK2).width('100%')
              }
              ForEach(this.rooms, (r: Room) => {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(r.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.INK)
                      .width('100%')
                    Text(r.note.length > 0 ? r.note : '点击打开，可添加前门/后门等标记')
                      .fontSize(Theme.F_META)
                      .fontColor(Theme.INK2)
                      .width('100%')
                  }.layoutWeight(1)
                  Text('›').fontSize(18).fontColor(Theme.INK3)
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .onClick(() => {
                  this.onOpenRoom(r.id);
                })
              }, (r: Room) => r.id + '')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD)
            .border({ width: 2, color: Theme.LINE })

            // 轨迹
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Text(this.selectMode
                  ? `已选 ${this.selectedIds.length} / ${this.tracks.length}`
                  : `轨迹（${this.tracks.length}）`)
                  .fontSize(Theme.F_SECTION)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.INK)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.selectMode) {
                  PillButton({
                    label: this.allSelected() ? '取消全选' : '全选',
                    onTap: (): void => {
                      this.toggleSelectAll();
                    }
                  })
                  PillButton({
                    label: '取消',
                    onTap: (): void => {
                      this.exitSelect();
                    }
                  })
                } else if (this.tracks.length > 0) {
                  // 「开始记录」只在右下角 FAB 上保留一处（这里原来重复了一个，已删）
                  PillButton({
                    label: '选择导出',
                    onTap: (): void => {
                      this.enterSelect();
                    }
                  })
                }
              }.width('100%')

              if (this.selectMode) {
                Text('勾选后导出，只打包选中的轨迹（含照片与 gallery.html 索引）')
                  .fontSize(Theme.F_META)
                  .fontColor(Theme.INK2)
                  .width('100%')
                Column() {
                  ThickButton({
                    label: `导出所选（${this.selectedIds.length}）`,
                    kind: 'accent',
                    compact: true,
                    disabled: this.selectedIds.length === 0,
                    onTap: (): void => {
                      this.exportSelected();
                    }
                  })
                }.width('100%')
              }

              if (this.tracks.length === 0) {
                Text(this.isUnassigned()
                  ? '未分区没有轨迹'
                  : '该区域还没有轨迹，点右下角「开始记录」采集（途中可记录节点 / 拍风景照）')
                  .fontSize(13)
                  .fontColor(Theme.INK2)
                  .width('100%')
              }
              ForEach(this.tracks, (t: Track) => {
                Row({ space: 10 }) {
                  if (this.selectMode) {
                    Stack() {
                      if (this.isSelected(t.id)) {
                        Text('✓')
                          .fontSize(14)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Theme.ON_RED)
                      }
                    }
                    .width(22)
                    .height(22)
                    .borderRadius(7)
                    .backgroundColor(this.isSelected(t.id) ? Theme.RED : Theme.CARD)
                    .border({
                      width: 2,
                      color: this.isSelected(t.id) ? Theme.RED_DEEP : Theme.LINE
                    })
                  }
                  Column({ space: 3 }) {
                    Text(t.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.INK)
                      .width('100%')
                    Text(this.trackSub(t)).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                  }.layoutWeight(1)
                  if (!this.selectMode) {
                    Text('›').fontSize(18).fontColor(Theme.INK3)
                  }
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .onClick(() => {
                  if (this.selectMode) {
                    this.toggleSelect(t.id);
                  } else {
                    this.onOpenTrack(t.id);
                  }
                })
              }, (t: Track) => t.id + '')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD)
            .border({ width: 2, color: Theme.LINE })

            if (this.area && this.area.note.length > 0 && !this.isUnassigned()) {
              Text(this.area.note).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
            }
          }.padding({ left: Theme.PAD, right: Theme.PAD, bottom: 90 }).width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }.width('100%').height('100%')

      // FAB：未分区不允许开始记录；勾选导出模式下隐藏；记录中横幅自带停止按钮（心跳重建驱动刷新）
      ForEach([this.heartbeat], (h: number) => {
        if (!AppStorage.get<boolean>('rm_recording') && !this.isUnassigned() && !this.selectMode) {
          Button('开始记录')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.ON_RED)
            .backgroundColor(Theme.RED)
            .borderRadius(20)
            .height(54)
            .margin(Theme.PAD)
            .onClick(() => {
              this.openStartDialog();
            })
        }
      }, (h: number) => h + '')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
