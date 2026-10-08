import { promptAction } from '@kit.ArkUI';
import { Track } from '../data/Entities';
import { Store } from '../data/Store';
import { TrackRecorder } from '../sensors/TrackRecorder';
import { RecordingBanner } from './RecordingBanner';
import {
  ROW_DAY, TrackDayGroup, TrackRow, dayKey, defaultTrackName, flattenTracksByDay, groupTracksByDay
} from '../common/Utils';
import { Theme } from '../common/Theme';
import { PillButton, ThickButton } from '../common/Widgets';

/**
 * 「开始记录轨迹」对话框。
 *
 * **2026-10-08 改：不再让用户选「所在区域」。** 原来这里是必选项，因为一条轨迹要归属
 * 一栋楼；但轨迹其实会跨楼（用户的原话：「不要放在区域下面了，因为会跨区域」），
 * 开录时逼着选一栋楼本身就是错的。现在轨迹不归属任何区域：
 *  - 谁属于哪栋楼由**节点**自己带（打节点时选，并默认继承上一个节点）；
 *  - 室内 / 室外在录制中用 RecordingBanner 上那个三态按钮随时切，开录时不问。
 * 所以这个对话框只剩「起个名字」一件事。
 */
@CustomDialog
export struct StartTrackDialog {
  controller?: CustomDialogController;
  onStart?: (name: string) => void;
  @State name: string = '';

  aboutToAppear(): void {
    this.name = defaultTrackName();
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

      Text('开始后每秒采样 定位 + 气压 + 地磁 + 朝向 + WiFi，每 5 秒自动保存；途中可记录节点（标记+照片）、拍风景照、打拐点，并用「室内外」按钮切换当前所在的环境')
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
          ThickButton({
            label: '开始记录',
            kind: 'primary',
            compact: true,
            onTap: (): void => {
              if (this.name.trim().length === 0) {
                promptAction.showToast({ message: '请先给这条轨迹起个名字' });
                return;
              }
              this.controller?.close();
              if (this.onStart) {
                this.onStart(this.name.trim());
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
  /** 按天分组后摊平成的行序列（分组头也是一行）；渲染只认它，见 Utils.flattenTracksByDay */
  @State rows: TrackRow[] = [];
  @State dayCount: number = 0;
  @State heartbeat: number = 0;
  private timer: number = -1;
  /** 上一次算分组时所在的「天」：跨过午夜要重算，否则昨晚的轨迹会一直挂着「今天」 */
  private lastDayKey: string = '';

  private reload = (): void => {
    Store.listTracks().then((t: Track[]) => {
      this.tracks = t;
      this.lastDayKey = dayKey(Date.now());
      const groups: TrackDayGroup[] = groupTracksByDay(t, Date.now());
      this.dayCount = groups.length;
      this.rows = flattenTracksByDay(groups);
    });
  };

  aboutToAppear(): void {
    this.reload();
    Store.subscribe(this.reload);
    this.timer = setInterval(() => {
      this.heartbeat++;
      // 「今天 / 昨天」是按天算出来的标题，不重算的话页面开着过夜就会显示错（比如昨天的轨迹
      // 一直写着「今天」）。这个定时器本来就在跑，顺带比一下日期几乎不花钱。
      if (dayKey(Date.now()) !== this.lastDayKey) {
        this.reload();
      }
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
      onStart: (name: string): void => {
        TrackRecorder.get().start(name).catch(() => {
          promptAction.showToast({ message: '启动记录失败' });
        });
      }
    }),
    customStyle: false
  });

  /**
   * 删除一条轨迹前先确认（用户 2026-09-29 要求）。
   * 原来点了立刻就删、没有任何提示，采样点和照片都是**一起删掉且找不回来**的，
   * 手指一滑就没了，所以这里必须拦一道。
   */
  private confirmDelete(id: number, name: string, sub: string): void {
    promptAction.showDialog({
      title: '删除这条轨迹？',
      message: `「${name}」\n${sub}\n采样点、节点和照片会一起删掉，删了就找不回来了。`,
      buttons: [
        { text: '取消', color: Theme.INK2 },
        { text: '删除', color: Theme.DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index !== 1) {
        return;
      }
      // 正在记录的那条不能删：记录线程还在往里写采样点，删掉会留下一条写不进去的野记录
      if (TrackRecorder.get().getTrackId() === id) {
        promptAction.showToast({ message: '这条轨迹正在记录中，先停止记录再删' });
        return;
      }
      Store.deleteTrack(id).then(() => {
        promptAction.showToast({ message: '已删除轨迹' });
      }).catch((e: Error) => {
        promptAction.showToast({ message: `删除失败：${e.message}` });
      });
    }).catch(() => {
    });
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
            Text(this.dayCount > 0
              ? `共 ${this.tracks.length} 条 · ${this.dayCount} 天`
              : '共 0 条')
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
          // 按天分组：分组头也是一行（去掉了粘性头，理由见 Utils.flattenTracksByDay）
          List() {
            ForEach(this.rows, (r: TrackRow) => {
              ListItem() {
                if (r.kind === ROW_DAY) {
                  Row({ space: 8 }) {
                    Text(r.label)
                      .fontSize(Theme.F_SECTION)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.INK)
                    Text(`${r.count} 条`).fontSize(Theme.F_META).fontColor(Theme.INK2)
                    Blank()
                  }
                  .width('100%')
                  .padding({ left: 20, right: 20, top: 12, bottom: 8 })
                } else {
                  Row({ space: 10 }) {
                    Column({ space: 3 }) {
                      Text(r.name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Theme.INK)
                        .width('100%')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(r.sub).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                    }.layoutWeight(1)
                    PillButton({
                      label: '删除',
                      kind: 'danger',
                      onTap: (): void => {
                        this.confirmDelete(r.id, r.name, r.sub);
                      }
                    })
                  }
                  .width('100%')
                  .padding({ left: 16, right: 12, top: 12, bottom: 12 })
                  .backgroundColor(Theme.CARD)
                  .borderRadius(18)
                  .border({ width: 2, color: Theme.LINE })
                  .margin({ left: 16, right: 16, bottom: 10 })
                  .onClick(() => {
                    this.onOpenTrack(r.id);
                  })
                }
              }
            }, (r: TrackRow) => r.key)
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
