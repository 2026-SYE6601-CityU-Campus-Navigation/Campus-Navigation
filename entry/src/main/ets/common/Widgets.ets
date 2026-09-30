import { Theme } from './Theme';

/**
 * 节点类型 / 功能图标 → 资源映射。图标是细描边 SVG、写死城大深红，
 * 因此只适合放在浅色底上（深色底上会看不见，那边就只用文字）。
 */
export function tagIconRes(iconKey: string): Resource | undefined {
  if (iconKey === '大门') {
    return $r('app.media.ic_maingate');
  }
  if (iconKey === '楼梯') {
    return $r('app.media.ic_stairs');
  }
  if (iconKey === '扶梯') {
    return $r('app.media.ic_escalator');
  }
  if (iconKey === '门') {
    return $r('app.media.ic_door');
  }
  if (iconKey === '电梯') {
    return $r('app.media.ic_lift');
  }
  if (iconKey === '厕所') {
    return $r('app.media.ic_wc');
  }
  if (iconKey === '门禁') {
    return $r('app.media.ic_gate');
  }
  if (iconKey === '教室') {
    return $r('app.media.ic_class');
  }
  if (iconKey === '食堂') {
    return $r('app.media.ic_canteen');
  }
  if (iconKey === '商店') {
    return $r('app.media.ic_shop');
  }
  if (iconKey === '其他室内') {
    return $r('app.media.ic_indoor');
  }
  if (iconKey === 'floor') {
    return $r('app.media.ic_layers');
  }
  if (iconKey === 'scene') {
    return $r('app.media.ic_scene');
  }
  return undefined;
}

/**
 * 通用外观组件。放在这里而不是各页各写一遍，方便统一改版式。
 *
 * 关于「厚底边按钮」：不用 shadow / 单边 border 去模拟底边，而是外层容器承载深色底边、
 * 内层是按钮面 —— 避免 ArkUI 边缘属性与圆角叠加时的渲染差异。
 * 按钮宽度总是撑满父容器；要半宽或并排，请在调用处用 Column/Row + layoutWeight 包一层。
 *
 * 动态参数一律用 @Prop（label/kind/compact/disabled）：这些值随父页面状态变化
 * （最典型的是「导出所选（N）」的计数和它变灰与否），@Prop 保证父组件重渲染时同步过来；
 * 普通成员变量不具备这个同步能力，会出现「状态早变了、按钮还是老样子」。
 * onTap 保持普通成员（@Prop 不支持函数类型）。
 */
@Component
export struct ThickButton {
  @Prop label: string = '';
  /** primary(深红) | accent(黄) | ghost(白底描边) | danger(红) | onred(深红底上的按钮) */
  @Prop kind: string = 'primary';
  @Prop compact: boolean = false;
  @Prop disabled: boolean = false;
  onTap: () => void = () => {
  };

  private face(): string {
    if (this.kind === 'accent') {
      return Theme.YELLOW;
    }
    if (this.kind === 'ghost') {
      return Theme.CARD;
    }
    if (this.kind === 'danger') {
      return Theme.DANGER;
    }
    if (this.kind === 'onred') {
      return Theme.RED_HI;
    }
    return Theme.RED;
  }

  private lip(): string {
    if (this.kind === 'accent') {
      return Theme.YELLOW_DEEP;
    }
    if (this.kind === 'ghost') {
      return Theme.LINE;
    }
    if (this.kind === 'danger') {
      return Theme.DANGER_DEEP;
    }
    return Theme.RED_DEEP;
  }

  private ink(): string {
    if (this.kind === 'accent') {
      return Theme.YELLOW_ON;
    }
    if (this.kind === 'ghost') {
      return Theme.RED;
    }
    return Theme.ON_RED;
  }

  build() {
    Row() {
      Column() {
        Text(this.label)
          .fontSize(this.compact ? 13 : 15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.ink())
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({
            left: this.compact ? 12 : 16,
            right: this.compact ? 12 : 16,
            top: this.compact ? 8 : 12,
            bottom: this.compact ? 8 : 12
          })
          .backgroundColor(this.face())
          .borderRadius(this.compact ? 12 : Theme.R_BTN - 2)
          .border({ width: this.kind === 'ghost' ? 2 : 0, color: Theme.LINE })
          .onClick(() => {
            if (!this.disabled) {
              this.onTap();
            }
          })
      }
      .backgroundColor(this.lip())
      .borderRadius(this.compact ? 13 : Theme.R_BTN)
      .padding({ bottom: this.compact ? 3 : 4 })
      .layoutWeight(1)
    }
    .width('100%')
    .opacity(this.disabled ? 0.45 : 1)
  }
}

/** 小圆角胶囊按钮：用在顶栏 / 工具条这类不需要厚底边的地方 */
@Component
export struct PillButton {
  @Prop label: string = '';
  /** plain(白底描边) | solid(深红底) | accent(黄底) | danger(红底) */
  @Prop kind: string = 'plain';
  onTap: () => void = () => {
  };

  private fg(): string {
    if (this.kind === 'plain') {
      return Theme.RED;
    }
    if (this.kind === 'accent') {
      return Theme.YELLOW_ON;
    }
    return Theme.ON_RED;
  }

  private bg(): string {
    if (this.kind === 'solid') {
      return Theme.RED;
    }
    if (this.kind === 'accent') {
      return Theme.YELLOW;
    }
    if (this.kind === 'danger') {
      return Theme.DANGER;
    }
    return Theme.CARD;
  }

  build() {
    Text(this.label)
      .fontSize(12.5)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.fg())
      .backgroundColor(this.bg())
      .borderRadius(13)
      .border({ width: this.kind === 'plain' ? 2 : 0, color: Theme.LINE })
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .onClick(() => {
        this.onTap();
      })
  }
}

/** 信息胶囊：节点类型 / 楼层 / 风景照 / 已保存等 */
@Component
export struct Chip {
  @Prop text: string = '';
  /** tag(深红) | floor(蓝) | scene(黄) | ok(绿) | plain(灰) */
  @Prop kind: string = 'tag';
  /** 图标键：节点类型（楼梯/门/电梯/厕所/门禁/教室）或 floor / scene；空字符串则只显示文字 */
  @Prop iconKey: string = '';

  private bg(): string {
    if (this.kind === 'floor') {
      return Theme.BLUE_SOFT;
    }
    if (this.kind === 'scene') {
      return Theme.YELLOW_SOFT;
    }
    if (this.kind === 'ok') {
      return Theme.GREEN_SOFT;
    }
    if (this.kind === 'plain') {
      return Theme.PLACEHOLDER;
    }
    return Theme.RED_SOFT;
  }

  private fg(): string {
    if (this.kind === 'floor') {
      return Theme.BLUE_DEEP;
    }
    if (this.kind === 'scene') {
      return Theme.YELLOW_INK;
    }
    if (this.kind === 'ok') {
      return Theme.GREEN_DEEP;
    }
    if (this.kind === 'plain') {
      return Theme.INK2;
    }
    return Theme.RED;
  }

  private iconRes(): Resource | undefined {
    return tagIconRes(this.iconKey);
  }

  build() {
    Row({ space: 4 }) {
      if (this.iconRes() !== undefined) {
        Image(this.iconRes() as Resource)
          .width(13)
          .height(13)
          .objectFit(ImageFit.Contain)
      }
      Text(this.text)
        .fontSize(Theme.F_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.fg())
    }
    .backgroundColor(this.bg())
    .borderRadius(Theme.R_CHIP)
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
  }
}
