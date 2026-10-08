import { Theme } from '../common/Theme';
import { ThickButton } from '../common/Widgets';

/**
 * 「这次扫描是在哪个地点」选择框（2026-10-08）。
 *
 * 为什么需要一个选择框而不是「绑定到刚才匹配到的那个」：**恰恰是匹配失败的时候最需要绑定。**
 * 跨会话第一次扫描如果认不出来（地址轮换、天气、AP 变动……），用户仍然知道自己在哪 ——
 * 把这次扫描绑到那个地点，它就会作为**一个新的会话**参与建图（见 Entities.PlaceScan），
 * 指纹因此被压实一次。这就是「不断标记强化这些地点」那条产品思路的落地点。
 */
export interface PlaceOption {
  key: string;
  label: string;
  /** 补充说明：几个 AP、几个会话 */
  sub: string;
}

@CustomDialog
export struct BindPlaceDialog {
  controller?: CustomDialogController;
  onPick?: (key: string, label: string) => void;
  /** 可选地点（调用方按「本次匹配到的排最前」排好） */
  options: PlaceOption[] = [];
  /** 这次扫描当场匹配到的地点（用于标出「本次匹配」） */
  matchedKey: string = '';
  @State selKey: string = '';
  /** 空串 = 不绑定（点确认时） */
  @State noBind: boolean = false;

  aboutToAppear(): void {
    // 默认选中「本次匹配到的」；认不出来时默认「不绑定」，避免手一滑绑错地方
    this.selKey = this.matchedKey;
    this.noBind = this.matchedKey.length === 0;
  }

  private confirm(): void {
    const key: string = this.noBind ? '' : this.selKey;
    let label: string = '';
    for (const o of this.options) {
      if (o.key === key) {
        label = o.label;
        break;
      }
    }
    this.controller?.close();
    if (this.onPick) {
      this.onPick(key, label);
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('这次扫描是在哪个地点？').fontSize(19).fontWeight(FontWeight.Bold)
        .width('100%').fontColor(Theme.INK)
      Text('绑了之后，这次扫描会作为一次新的「到访」参与建图，那个地点的指纹会更结实（也会长出跨会话的稳定 AP）。'
        + '认不出来时也能绑 —— 你知道自己在哪，App 不知道。')
        .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')

      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.options, (o: PlaceOption) => {
            Row({ space: 10 }) {
              Column()
                .width(18)
                .height(18)
                .backgroundColor(!this.noBind && this.selKey === o.key ? Theme.RED : Theme.CARD)
                .borderRadius(Theme.R_CHIP)
                .border({
                  width: 2,
                  color: !this.noBind && this.selKey === o.key ? Theme.RED_DEEP : Theme.LINE
                })
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(o.label)
                    .fontSize(13.5)
                    .fontWeight(!this.noBind && this.selKey === o.key ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(Theme.INK)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (o.key === this.matchedKey) {
                    Text('本次匹配')
                      .fontSize(10)
                      .fontColor(Theme.GREEN_DEEP)
                      .backgroundColor(Theme.GREEN_SOFT)
                      .borderRadius(Theme.R_CHIP)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  }
                }
                Text(o.sub).fontSize(Theme.F_META).fontColor(Theme.INK2)
                  .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(10)
            .backgroundColor(!this.noBind && this.selKey === o.key ? Theme.RED_SOFT : Theme.CARD_SOFT)
            .borderRadius(12)
            .border({
              width: 2,
              color: !this.noBind && this.selKey === o.key ? Theme.RED : Theme.LINE
            })
            .onClick(() => {
              this.noBind = false;
              this.selKey = o.key;
            })
          }, (o: PlaceOption) => o.key)
        }.width('100%')
      }
      .width('100%')
      .scrollBar(BarState.Auto)
      .constraintSize({ maxHeight: 300 })

      // 「不绑定」单独一项：与地点列表放在一起容易被误当成一个地点
      Row({ space: 10 }) {
        Column()
          .width(18)
          .height(18)
          .backgroundColor(this.noBind ? Theme.RED : Theme.CARD)
          .borderRadius(Theme.R_CHIP)
          .border({ width: 2, color: this.noBind ? Theme.RED_DEEP : Theme.LINE })
        Text('不绑定（只作为一条验证记录留着）').fontSize(13).fontColor(Theme.INK2)
          .layoutWeight(1)
      }
      .width('100%')
      .padding(10)
      .backgroundColor(this.noBind ? Theme.RED_SOFT : Theme.CARD_SOFT)
      .borderRadius(12)
      .border({ width: 2, color: this.noBind ? Theme.RED : Theme.LINE })
      .onClick(() => {
        this.noBind = true;
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
            label: '保存绑定',
            kind: 'accent',
            compact: true,
            onTap: (): void => {
              this.confirm();
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
