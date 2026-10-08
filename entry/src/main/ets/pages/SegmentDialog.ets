import { INDOOR_IN, INDOOR_OUT, INDOOR_UNKNOWN, TrackTag } from '../data/Entities';
import { indoorLabel } from '../common/IndoorState';
import { fmtTime } from '../common/Utils';
import { Theme } from '../common/Theme';
import { ThickButton } from '../common/Widgets';

/**
 * 「在哪个节点切开」对话框（2026-10-08 批次三新增）。
 *
 * 事后修正室内外分段的入口。为什么让用户选**节点**、而不是挑一个时间：
 * 节点的 `timeMs` 是当时**按下那一刻**的精确时间（记录节点虽有填表+拍照的延迟，
 * 但时间戳取自拍照完成的那一刻，是精确的），而「进楼」这个动作用户当时多半正好
 * 打了个「门 / 门禁 / 楼梯」节点 —— 那正是分段边界该落的地方。
 *
 * 为什么不让用户直接输时间：一是手机上输时间很痛苦，二是本工程的口径一贯是
 * 「宁可不说，也不猜」—— 让用户在节点里选，选出来的一定是真实发生过的时刻。
 */
@CustomDialog
export struct SplitSegmentDialog {
  controller?: CustomDialogController;
  onConfirm?: (atMs: number, newIndoor: number) => void;
  /** 这一段内部可以作为切分点的节点（调用方先用 IndoorState.nodesInsideSegment 筛好，升序） */
  candidates: TrackTag[] = [];
  /** 被切开的那一段现在的状态：用来给「后半段」一个合理默认值 */
  segIndoor: number = INDOOR_UNKNOWN;
  @State selId: number = -1;
  @State newIndoor: number = INDOOR_IN;

  aboutToAppear(): void {
    // 默认选中第一个候选（这里不用 ForEach 的 index 参数：本工程没有用过那个重载，
    // 而每次真机编译都要用户在 DevEco 跑一轮，没验证过的 API 不赌 —— 用节点 id 记选中项，
    // 反正节点 id 本来就是这个列表的 key）
    this.selId = this.candidates.length > 0 ? this.candidates[0].id : -1;
    // 默认值取「翻过来」：这个功能最常用来补的是「进楼那一下忘了按」，
    // 也就是前半段（多半是未标/室外）保持不变、后半段应该是「室内」。
    this.newIndoor = this.segIndoor === INDOOR_IN ? INDOOR_OUT : INDOOR_IN;
  }

  private picked(): TrackTag | undefined {
    for (const g of this.candidates) {
      if (g.id === this.selId) {
        return g;
      }
    }
    return undefined;
  }

  private rowSub(g: TrackTag): string {
    let s = `${fmtTime(g.timeMs)} · ${g.tagType}`;
    if (g.floor.length > 0) {
      s += ` · ${g.floor}`;
    }
    if (g.note.trim().length > 0) {
      const n: string = g.note.trim();
      s += ` · ${n.length > 12 ? `${n.substring(0, 12)}…` : n}`;
    }
    return s;
  }

  /** 三态选择按钮：选中的实心深红 */
  @Builder
  stateOption(label: string, value: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 9, bottom: 9 })
      .fontColor(this.newIndoor === value ? Theme.ON_RED : Theme.INK)
      .backgroundColor(this.newIndoor === value ? Theme.RED : Theme.CARD_SOFT)
      .borderRadius(14)
      .border({ width: 2, color: this.newIndoor === value ? Theme.RED_DEEP : Theme.LINE })
      .onClick(() => {
        this.newIndoor = value;
      })
  }

  build() {
    Column({ space: 12 }) {
      Text('在哪个节点切开').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
      Text('选一个当时打下的节点作为分界：它之前的算原来那一半、之后的算新的一半。'
        + '切分点用的是节点的精确时刻，不需要你输时间。')
        .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')

      if (this.candidates.length === 0) {
        // 理论上进不来（调用方筛空了就不打开这个对话框），留着是为了万一
        Text('这一段里没有可以作为分界的节点：先在这段时间里补一个节点，再回来切分。')
          .fontSize(Theme.F_META).fontColor(Theme.DANGER).width('100%')
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.candidates, (g: TrackTag) => {
              Row({ space: 10 }) {
                Column()
                  .width(18)
                  .height(18)
                  .backgroundColor(this.selId === g.id ? Theme.RED : Theme.CARD)
                  .borderRadius(Theme.R_CHIP)
                  .border({ width: 2, color: this.selId === g.id ? Theme.RED_DEEP : Theme.LINE })
                Column({ space: 2 }) {
                  Text(this.rowSub(g))
                    .fontSize(13.5)
                    .fontWeight(this.selId === g.id ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(Theme.INK)
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(10)
              .backgroundColor(this.selId === g.id ? Theme.RED_SOFT : Theme.CARD_SOFT)
              .borderRadius(12)
              .border({ width: 2, color: this.selId === g.id ? Theme.RED : Theme.LINE })
              .onClick(() => {
                this.selId = g.id;
              })
            }, (g: TrackTag) => g.id + '')
          }.width('100%')
        }
        .width('100%')
        .scrollBar(BarState.Auto)
        // 死值上限：CustomDialog 里用百分比做 maxHeight 参考系不明确（可能算成 0 把内容压没）
        .constraintSize({ maxHeight: 260 })

        Text(`切分点：${this.picked() !== undefined ? this.rowSub(this.picked() as TrackTag) : '—'}`)
          .fontSize(Theme.F_META).fontColor(Theme.BLUE_DEEP).width('100%')

        Text('这个节点之后的那一半标成什么？').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
        Row({ space: 8 }) {
          this.stateOption('室内', INDOOR_IN)
          this.stateOption('室外', INDOOR_OUT)
          this.stateOption('未标', INDOOR_UNKNOWN)
        }.width('100%')
        Text(`（前面那一半保持不变：${indoorLabel(this.segIndoor)}）`)
          .fontSize(Theme.F_META).fontColor(Theme.INK3).width('100%')
      }

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

        if (this.candidates.length > 0) {
          Column() {
            ThickButton({
              label: '切开',
              kind: 'accent',
              compact: true,
              onTap: (): void => {
                const g: TrackTag | undefined = this.picked();
                if (g === undefined) {
                  return;
                }
                const atMs: number = g.timeMs;
                const next: number = this.newIndoor;
                this.controller?.close();
                if (this.onConfirm) {
                  this.onConfirm(atMs, next);
                }
              }
            })
          }.layoutWeight(1.4)
        }
      }.width('100%')
    }
    .padding(18)
    .width('100%')
    .backgroundColor(Theme.CARD)
  }
}
