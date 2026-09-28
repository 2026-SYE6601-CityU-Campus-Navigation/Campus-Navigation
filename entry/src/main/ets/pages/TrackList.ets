import { promptAction } from '@kit.ArkUI';
import { Area, Track } from '../data/Entities';
import { Store } from '../data/Store';
import { TrackRecorder } from '../sensors/TrackRecorder';
import { RecordingBanner } from './RecordingBanner';
import { defaultTrackName, fmtDuration, fmtTime } from '../common/Utils';

@CustomDialog
export struct StartTrackDialog {
  controller?: CustomDialogController;
  onStart?: (name: string, areaId: number) => void;
  /** 预选区域 id（从区域详情页进入时传入）；-1 表示不预选 */
  defaultAreaId: number = -1;
  @State name: string = '';
  @State areas: Area[] = [];
  @State selAreaId: number = -1;
  @State selIndex: number = 0;

  aboutToAppear(): void {
    this.name = defaultTrackName();
    Store.listAreas().then((list: Area[]) => {
      this.areas = list;
      if (list.length === 0) {
        this.selAreaId = -1;
        this.selIndex = 0;
        return;
      }
      let idx = 0;
      for (let i = 0; i < list.length; i++) {
        if (list[i].id === this.defaultAreaId) {
          idx = i;
          break;
        }
      }
      this.selIndex = idx;
      this.selAreaId = list[idx].id;
    });
  }

  private areaOptions(): Array<SelectOption> {
    const out: SelectOption[] = [];
    for (const a of this.areas) {
      out.push({ value: a.name });
    }
    return out;
  }

  build() {
    Column({ space: 12 }) {
      Text('开始记录轨迹').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
      TextInput({ text: this.name, placeholder: '轨迹名称' })
        .onChange((v: string) => {
          this.name = v;
        })
      Text('所在区域（必选）').fontSize(14).width('100%')
      if (this.areas.length === 0) {
        Text('还没有区域，请先在首页新建区域').fontSize(12).fontColor('#E84026').width('100%')
      } else {
        Select(this.areaOptions())
          .selected(this.selIndex)
          .onSelect((index: number, value: string) => {
            this.selIndex = index;
            this.selAreaId = this.areas[index].id;
          })
          .width('100%')
      }
      Text('开始后每秒采样 定位 + 气压 + 地磁 + 朝向 + WiFi，每 5 秒自动保存；途中可拍照、打标签')
        .fontSize(12)
        .fontColor('#99000000')
        .width('100%')
      Row({ space: 12 }) {
        Button('取消').onClick(() => {
          this.controller?.close();
        })
        Button('开始')
          .enabled(this.name.trim().length > 0 && this.areas.length > 0)
          .onClick(() => {
            this.controller?.close();
            if (this.onStart) {
              this.onStart(this.name.trim(), this.selAreaId);
            }
          })
      }.width('100%').justifyContent(FlexAlign.End)
    }.padding(16).width('100%')
  }
}

@Component
export struct TrackListPage {
  onBack: () => void = () => {
  };
  onOpenTrack: (id: number) => void = (id: number) => {
  };
  @State tracks: Track[] = [];
  @State heartbeat: number = 0;
  private timer: number = -1;

  private reload = (): void => {
    Store.listTracks().then((t: Track[]) => {
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

  private startDialog: CustomDialogController = new CustomDialogController({
    builder: StartTrackDialog({
      defaultAreaId: -1,
      onStart: (name: string, areaId: number): void => {
        TrackRecorder.get().start(name, areaId).catch(() => {
          promptAction.showToast({ message: '启动记录失败' });
        });
      }
    }),
    customStyle: false
  });

  private trackSub(t: Track): string {
    const end = t.endedAt !== undefined ? t.endedAt : t.startedAt;
    const area = t.areaName !== undefined ? t.areaName : '未分区';
    let s =
      `[${area}] ${fmtTime(t.startedAt)} · 时长 ${fmtDuration(Math.floor((end - t.startedAt) / 1000))} · ${t.pointCount} 点`;
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
          Text('轨迹记录').fontSize(18).fontWeight(FontWeight.Medium).margin({ left: 12 })
          Blank()
        }.width('100%').padding({ left: 8, right: 12, top: 10, bottom: 10 })
        Divider()

        RecordingBanner()

        if (this.tracks.length === 0 && !AppStorage.get<boolean>('rm_recording')) {
          Column() {
            Blank()
            Text('还没有轨迹，点击右下角开始记录').fontColor('#99000000')
            Blank()
          }.width('100%').layoutWeight(1)
        } else {
          List() {
            ForEach(this.tracks, (t: Track) => {
              ListItem() {
                Row() {
                  Column({ space: 4 }) {
                    Text(t.name).fontSize(16).width('100%')
                    Text(this.trackSub(t)).fontSize(13).fontColor('#99000000').width('100%')
                  }.layoutWeight(1)
                  Button('删除').fontSize(12).fontColor('#E84026').onClick(() => {
                    Store.deleteTrack(t.id).then(() => {
                      promptAction.showToast({ message: '已删除轨迹' });
                    });
                  })
                }.width('100%').padding({ left: 16, right: 12, top: 12, bottom: 12 })
              }.onClick(() => {
                this.onOpenTrack(t.id);
              })
            }, (t: Track) => t.id + '')
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 0.5, color: '#1A000000' })
        }
      }.width('100%').height('100%')

      // 记录中横幅自带停止按钮，FAB 只在未记录时显示（心跳重建驱动刷新）
      ForEach([this.heartbeat], (h: number) => {
        if (!AppStorage.get<boolean>('rm_recording')) {
          Button('开始记录').margin(16).onClick(() => {
            this.startDialog.open();
          })
        }
      }, (h: number) => h + '')
    }.width('100%').height('100%')
  }
}
