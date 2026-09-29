/**
 * 视觉令牌（设计系统单一来源）。
 *
 * 风格约定：保留 Duolingo 那种「可按下去的厚按钮」、大圆角、饱和色块、粗描边图标；
 * 不做 XP／连胜／吉祥物等游戏化元素（这是采集工具）。差异化支点是「垂直高度」——
 * 高度层、高差读数、节点楼层徽章贯穿界面。
 *
 * ⚠️ 换配色只需要改本文件：主色 RED / RED_DEEP 目前是**近似**的城大深红，
 * 拿到准确 HEX（或从校徽取色）后改这两行即可全局生效。
 * 例外：resources/base/media/ic_*.svg 里的描边色是写死的同一个深红，
 * 换主色时需要一并替换（SVG 无法继承文字颜色）。
 */
export class Theme {
  // ---------- 主色：城大深红 ----------
  static readonly RED: string = '#8C1D40';
  static readonly RED_DEEP: string = '#5E1230';
  static readonly RED_HI: string = '#A82950';
  static readonly RED_SOFT: string = '#F7E4EB';

  // ---------- 辅助色 ----------
  static readonly YELLOW: string = '#F5B301';
  static readonly YELLOW_DEEP: string = '#B88700';
  static readonly YELLOW_SOFT: string = '#FDF0CE';
  static readonly YELLOW_INK: string = '#8A6600';

  static readonly BLUE: string = '#1E7FC2';
  static readonly BLUE_DEEP: string = '#14588A';
  static readonly BLUE_SOFT: string = '#E3F0FA';

  static readonly GREEN: string = '#2FA36B';
  static readonly GREEN_DEEP: string = '#1F7A4E';
  static readonly GREEN_SOFT: string = '#E2F4EA';

  static readonly DANGER: string = '#E23B3B';
  static readonly DANGER_DEEP: string = '#A82A2A';

  // ---------- 底与文字 ----------
  static readonly BG: string = '#FFF6F1';
  static readonly CARD: string = '#FFFFFF';
  static readonly CARD_SOFT: string = '#FFF9F6';
  static readonly PLACEHOLDER: string = '#F4EAE6';
  static readonly INK: string = '#2A1A20';
  static readonly INK2: string = '#7A6A70';
  static readonly INK3: string = '#A89098';
  static readonly LINE: string = '#F0DCD4';

  /** 深红底上放白色文字；浅底上用 INK */
  static readonly ON_RED: string = '#FFFFFF';
  /** 深红底上的次要文字（浅粉） */
  static readonly ON_RED_SOFT: string = '#EBCFDA';
  /** 黄底上的文字（深棕，保证对比度） */
  static readonly YELLOW_ON: string = '#3A2A00';
  /** 录制中的红点 */
  static readonly REC: string = '#FF5F6D';

  // ---------- 画布（三维轨迹图）用色 ----------
  // 半透明色只能用 rgba 字面量（Canvas 的 fillStyle 收字符串），集中放这里，
  // 避免颜色散落在页面里。实色部分一律引用上面的令牌。
  static readonly CANVAS_LINE_FADE: string = 'rgba(140,29,64,.14)';
  static readonly CANVAS_FLOOR: string = 'rgba(30,127,194,.07)';
  static readonly CANVAS_FLOOR_STROKE: string = 'rgba(30,127,194,.28)';
  static readonly CANVAS_FLOOR_TEXT: string = 'rgba(20,88,138,.75)';
  static readonly CANVAS_LABEL_BG: string = 'rgba(255,255,255,.96)';

  // ---------- 圆角 ----------
  static readonly R_CARD: number = 22;
  static readonly R_HERO: number = 24;
  static readonly R_BTN: number = 16;
  static readonly R_CHIP: number = 99;
  static readonly R_THUMB: number = 14;
  static readonly R_ICONBTN: number = 14;

  // ---------- 间距与字号 ----------
  static readonly PAD: number = 18;
  static readonly GAP: number = 14;
  static readonly F_TITLE: number = 20;
  static readonly F_SECTION: number = 15;
  static readonly F_BODY: number = 13.5;
  static readonly F_META: number = 11.5;
  static readonly F_BIG: number = 30;
}
