import { promptAction } from '@kit.ArkUI';
import { Area, Room, Track } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { TrackRecorder } from '../sensors/TrackRecorder';
import { RecordingBanner } from './RecordingBanner';
import { StartTrackDialog } from './TrackList';
import { Exporter } from '../common/Exporter';
import { fmtDuration, fmtTime } from '../common/Utils';

@CustomDialog
struct AddRoomDialog {
  controller?: CustomDialogController;
  onSave?: (name: string, note: string) => void;
  @State name: string = '';
  @State note: string = '';

  build() {
    Column({ space: 12 }) {
      Text('添加房间').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
      TextInput({ placeholder: '房间名称（如：301 会议室）' })
        .onChange((v: string) => {
          this.name = v;
        })
      TextInput({ placeholder: '备注（可选）' })
        .onChange((v: string) => {
          this.note = v;
        })
      Row({ space: 12 }) {
        Button('取消').onClick(() => {
          this.controller?.close();
        })
        Button('保存并打开')
          .enabled(this.name.trim().length > 0)
          .onClick(() => {
            this.controller?.close();
            if (this.onSave) {
              this.onSave(this.name.trim(), this.note.trim());
            }
          })
      }.width('100%').justifyContent(FlexAlign.End)
    }.padding(16).width('100%')
  }
}

/** 区域详情：该区域的房间 + 轨迹，支持开始记录 / 批量导出 / 删除区域 */
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

  private exportZip(): void {
    const name = this.areaName();
    promptAction.showToast({ message: `正在打包「${name}」的数据…` });
    Exporter.exportAreaZip(this.areaId, name).then((zipName: string) => {
      promptAction.showToast({ message: `已导出 ${zipName}` });
    }).catch((e: Error) => {
      promptAction.showToast({ message: e.message });
    });
  }

  private deleteArea(): void {
    promptAction.showDialog({
      title: `删除区域「${this.areaName()}」`,
      message: `房间 ${this.rooms.length} 个 · 轨迹 ${this.tracks.length} 条。\n移入未分区：保留全部数据；彻底删除：数据与照片将全部丢失。`,
      buttons: [
        { text: '取消', color: '#0A59F7' },
        { text: '移入未分区', color: '#99000000' },
        { text: '彻底删除', color: '#E84026' }
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
        Row() {
          Button('‹ 返回').fontSize(14).onClick(() => {
            this.onBack();
          })
          Text(this.areaName())
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ left: 12 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Button('导出').fontSize(12).onClick(() => {
            this.exportZip();
          })
          if (!this.isUnassigned()) {
            Button('删除').fontSize(12).fontColor('#E84026').margin({ left: 8 }).onClick(() => {
              this.deleteArea();
            })
          }
        }.width('100%').padding({ left: 8, right: 12, top: 10, bottom: 10 })
        Divider()

        RecordingBanner()

        Scroll() {
          Column({ space: 12 }) {
            // 房间
            Column({ space: 8 }) {
              Row() {
                Text(`房间（${this.rooms.length}）`).fontSize(16).fontWeight(FontWeight.Medium)
                Blank()
                Button('添加房间').fontSize(13).onClick(() => {
                  this.addRoomDialog.open();
                })
              }.width('100%')
              if (this.rooms.length === 0) {
                Text('该区域还没有房间').fontSize(13).fontColor('#99000000').width('100%')
              }
              ForEach(this.rooms, (r: Room) => {
                Row() {
                  Column({ space: 4 }) {
                    Text(r.name).fontSize(15).width('100%')
                    Text(r.note.length > 0 ? r.note : '点击打开，可添加前门/后门等标记')
                      .fontSize(12)
                      .fontColor('#99000000')
                      .width('100%')
                  }.layoutWeight(1)
                  Text('›').fontSize(18).fontColor('#99000000')
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .onClick(() => {
                  this.onOpenRoom(r.id);
                })
              }, (r: Room) => r.id + '')
            }.width('100%').padding(16).backgroundColor('#FFF7F7F7').borderRadius(12)

            // 轨迹
            Column({ space: 8 }) {
              Row() {
                Text(`轨迹（${this.tracks.length}）`).fontSize(16).fontWeight(FontWeight.Medium)
                Blank()
                if (this.isUnassigned()) {
                  Text('须在具体区域中记录轨迹')
                    .fontSize(12)
                    .fontColor('#99000000')
                } else {
                  Button('开始记录').fontSize(13).onClick(() => {
                    this.openStartDialog();
                  })
                }
              }.width('100%')
              if (this.tracks.length === 0) {
                Text(this.isUnassigned()
                  ? '未分区没有轨迹'
                  : '该区域还没有轨迹，点「开始记录」采集（途中可拍照/打标签）')
                  .fontSize(13)
                  .fontColor('#99000000')
                  .width('100%')
              }
              ForEach(this.tracks, (t: Track) => {
                Row() {
                  Column({ space: 4 }) {
                    Text(t.name).fontSize(15).width('100%')
                    Text(this.trackSub(t)).fontSize(12).fontColor('#99000000').width('100%')
                  }.layoutWeight(1)
                  Text('›').fontSize(18).fontColor('#99000000')
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .onClick(() => {
                  this.onOpenTrack(t.id);
                })
              }, (t: Track) => t.id + '')
            }.width('100%').padding(16).backgroundColor('#FFF7F7F7').borderRadius(12)

            if (this.area && this.area.note.length > 0 && !this.isUnassigned()) {
              Text(this.area.note).fontSize(12).fontColor('#66000000').width('100%')
            }
          }.padding(16).width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }.width('100%').height('100%')

      // FAB：未分区不允许开始记录；记录中横幅自带停止按钮（心跳重建驱动刷新）
      ForEach([this.heartbeat], (h: number) => {
        if (!AppStorage.get<boolean>('rm_recording') && !this.isUnassigned()) {
          Button('开始记录').margin(16).onClick(() => {
            this.openStartDialog();
          })
        }
      }, (h: number) => h + '')
    }.width('100%').height('100%')
  }
}
