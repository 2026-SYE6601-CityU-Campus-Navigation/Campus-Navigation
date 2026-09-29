import { promptAction } from '@kit.ArkUI';
import { Area, Track } from '../data/Entities';
import { Store } from '../data/Store';
import { TrackRecorder } from '../sensors/TrackRecorder';
import { RecordingBanner } from './RecordingBanner';
import { defaultTrackName, fmtDuration, fmtTime } from '../common/Utils';
import { Theme } from '../common/Theme';
import { PillButton, ThickButton } from '../common/Widgets';

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
    Column({ space: 14 }) {
      Text('开始记录轨迹').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
      TextInput({ text: this.name, placeholder: '轨迹名称' })
        .fontSize(13.5)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((v: string) => {
          this.name = v;
        })

      Text('所在区域（必选）').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
      if (this.areas.length === 0) {
        Text('还没有区域，请先在首页新建区域').fontSize(Theme.F_META).fontColor(Theme.DANGER).width('100%')
      } else {
        Select(this.areaOptions())
          .selected(this.selIndex)
          .value(this.areas[this.selIndex >= 0 ? this.selIndex : 0].name)
          .font({ size: 13.5 })
          .width('100%')
          .onSelect((index: number, value: string) => {
            this.selIndex = index;
            this.selAreaId = this.areas[index].id;
          })
      }

      Text('开始后每秒采样 定位 + 气压 + 地磁 + 朝向 + WiFi，每 5 秒自动保存；途中可记录节点（标记+照片）、拍风景照')
        .fontSize(Theme.F_META)
        .fontColor(Theme.INK2)
        .width('100%')

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
          // 刻意不做 disabled：区域列表是异步加载的，对话框首次渲染时 areas 还是空的，
          // 一旦被算成禁用态就会出现「按钮是灰的、怎么点都没反应」，而且没有任何提示。
          // 改成点按时校验 + 明确提示，按钮永远是可按的，问题也能自己说清楚。
          ThickButton({
            label: '开始记录',
            kind: 'primary',
            compact: true,
            onTap: (): void => {
              if (this.name.trim().length === 0) {
                promptAction.showToast({ message: '请先给这条轨迹起个名字' });
                return;
              }
              if (this.areas.length === 0) {
                promptAction.showToast({ message: '还没有区域，请先在首页新建区域' });
                return;
              }
              this.controller?.close();
              if (this.onStart) {
                this.onStart(this.name.trim(), this.selAreaId);
              }
            }
          })
        }.layoutWeight(1.3)
      }.width('100%')
    }
    .padding(18)
    .width('100%')
    .backgroundColor(Theme.CARD)
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
        Row({ space: 10 }) {
          PillButton({
            label: '‹ 返回',
            onTap: (): void => {
              this.onBack();
            }
          })
          Column({ space: 2 }) {
            Text('全部轨迹').fontSize(Theme.F_TITLE).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
            Text(`共 ${this.tracks.length} 条`)
              .fontSize(Theme.F_META)
              .fontColor(Theme.INK2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 10 })

        RecordingBanner()

        if (this.tracks.length === 0 && !AppStorage.get<boolean>('rm_recording')) {
          Column({ space: 6 }) {
            Blank()
            Text('还没有轨迹').fontWeight(FontWeight.Bold).fontColor(Theme.INK2)
            Text('点右下角开始记录').fontSize(Theme.F_META).fontColor(Theme.INK3)
            Blank()
          }.width('100%').layoutWeight(1)
        } else {
          List() {
            ForEach(this.tracks, (t: Track) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(t.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.INK)
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.trackSub(t)).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                  }.layoutWeight(1)
                  PillButton({
                    label: '删除',
                    kind: 'danger',
                    onTap: (): void => {
                      Store.deleteTrack(t.id).then(() => {
                        promptAction.showToast({ message: '已删除轨迹' });
                      });
                    }
                  })
                }
                .width('100%')
                .padding({ left: 16, right: 12, top: 12, bottom: 12 })
                .backgroundColor(Theme.CARD)
                .borderRadius(18)
                .border({ width: 2, color: Theme.LINE })
                .margin({ left: 16, right: 16, bottom: 10 })
              }.onClick(() => {
                this.onOpenTrack(t.id);
              })
            }, (t: Track) => t.id + '')
          }
          .width('100%')
          .layoutWeight(1)
        }
      }.width('100%').height('100%')

      // 记录中横幅自带停止按钮，FAB 只在未记录时显示（心跳重建驱动刷新）
      ForEach([this.heartbeat], (h: number) => {
        if (!AppStorage.get<boolean>('rm_recording')) {
          Button('开始记录')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.ON_RED)
            .backgroundColor(Theme.RED)
            .borderRadius(20)
            .height(54)
            .margin(Theme.PAD)
            .onClick(() => {
              this.startDialog.open();
            })
        }
      }, (h: number) => h + '')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
