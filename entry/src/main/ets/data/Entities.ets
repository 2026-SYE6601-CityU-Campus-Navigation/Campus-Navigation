/**
 * 数据实体：与 Android 版 Room 表结构一一对应。
 * 可空字段（undefined）对应数据库 NULL。
 */

export interface Room {
  id: number;
  name: string;
  /**
   * 教室代码（如 LT-1 / P4702 / 6-213）。
   * 2026-09-29 新增：教室名单里「代码」和「名称」是两样东西，分开存；
   * 普通房间（手建/按轨迹生成）没有代码，存空字符串。
   */
  code: string;
  note: string;
  areaId?: number;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  pressureHpa?: number;
  createdAt: number;
}

/** 标记类型（存储中文标签，与 Android 版 MarkerType.label 对应） */
export enum MarkerType {
  FRONT_DOOR = '前门',
  BACK_DOOR = '后门',
  WINDOW = '窗户',
  CORNER = '墙角',
  SOCKET = '插座',
  CUSTOM = '自定义'
}

export function markerTypeOptions(): Array<SelectOption> {
  return [
    { value: MarkerType.FRONT_DOOR },
    { value: MarkerType.BACK_DOOR },
    { value: MarkerType.WINDOW },
    { value: MarkerType.CORNER },
    { value: MarkerType.SOCKET },
    { value: MarkerType.CUSTOM }
  ];
}

export interface Marker {
  id: number;
  roomId: number;
  name: string;
  markerType: string;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  accuracy?: number;
  pressureHpa?: number;
  magneticX?: number;
  magneticY?: number;
  magneticZ?: number;
  createdAt: number;
}

/**
 * 区域分类（用户 2026-09-29 要求：区域固定分两大类）。
 *  - 城市大学：正式的校园建筑区域（一键导入的 11 栋楼、导入教室时按楼建出来的区域都归这里）
 *  - 测试集：自己试采集用的区域（录实验轨迹、试标签、试拍照）
 * 只做「固定两类」，所以这里用常量而不是可扩展的分类表；将来真要加第三类，改成一张表即可。
 */
export const AREA_CATEGORY_CITYU: string = '城市大学';
export const AREA_CATEGORY_TEST: string = '测试集';

/** 首页分区显示与新建区域时的可选项（城市大学在前：它是主内容） */
export function areaCategoryOptions(): Array<string> {
  return [AREA_CATEGORY_CITYU, AREA_CATEGORY_TEST];
}

/** 区域（文件夹）：顶层组织单位，房间与轨迹都归属某个区域。id=0 约定为「未分区」（areaId 为 NULL） */
export interface Area {
  id: number;
  name: string;
  note: string;
  /** 所属分类：AREA_CATEGORY_CITYU / AREA_CATEGORY_TEST；空串表示还没分类 */
  category: string;
  roomCount: number;
  trackCount: number;
  createdAt: number;
}

/** 轨迹途中标签类型（与房间标记 MarkerType 是两套体系） */
export enum TrackTagType {
  /** 大门：建筑主入口（用户 2026-09-29 要求新增）。它是建筑级的东西，**不绑房间** */
  MAIN_GATE = '大门',
  DOOR = '门',
  GATE = '门禁',
  STAIRS = '楼梯',
  /** 扶梯（自动扶梯）—— 城大垂直交通的主要方式之一，和楼梯分开记 */
  ESCALATOR = '扶梯',
  ELEVATOR = '电梯',
  TOILET = '厕所',
  CLASSROOM = '教室',
  /** 食堂 / 餐厅（2026-09-29 新增，新生常找） */
  CANTEEN = '食堂',
  /** 商店 / 便利店 / 银行（2026-09-29 新增） */
  SHOP = '商店',
  /** 其他室内：咖啡店、自习区、中庭这类不好穷举的，具体是什么写在备注里（2026-09-29 新增） */
  OTHER_INDOOR = '其他室内'
}

/**
 * 可以（但不再必须）绑定到某个房间的节点类型。
 *
 * 2026-09-28 的旧口径是「门 / 门禁**必须**选一个房间」，2026-09-29 实测后放宽：
 * 建筑大门 / 出入口本来就不属于任何房间，强制绑房间会逼用户建一个假的「大门房间」，
 * 与「区域＝一栋楼」的模型打架。现在这两类**可选**绑房间：绑了就照旧往该房间写前门/后门标记，
 * 不绑就只作为一个归属该区域的节点。
 *
 * 注意「大门(MainGate)」**刻意不在这个表里** —— 大门是建筑级的出入口，永远不绑房间，
 * 所以标「大门」时对话框中根本不会出现「所属房间」那一栏（用户 2026-09-29 确认）。
 */
export function roomBoundTagTypes(): Array<string> {
  return [TrackTagType.DOOR, TrackTagType.GATE];
}

export function trackTagOptions(): Array<SelectOption> {
  return [
    { value: TrackTagType.MAIN_GATE },
    { value: TrackTagType.DOOR },
    { value: TrackTagType.GATE },
    { value: TrackTagType.STAIRS },
    { value: TrackTagType.ESCALATOR },
    { value: TrackTagType.ELEVATOR },
    { value: TrackTagType.TOILET },
    { value: TrackTagType.CLASSROOM },
    { value: TrackTagType.CANTEEN },
    { value: TrackTagType.SHOP },
    { value: TrackTagType.OTHER_INDOOR }
  ];
}

/**
 * 节点类型名（纯 string 数组），供界面自己遍历渲染。
 * 刻意不复用 trackTagOptions()：它的 SelectOption.value 是 ResourceStr（可能为 Resource），
 * 拿来当 string 用会被 ArkTS 编译器拒绝（Select 组件自己用没问题）。
 * 取值与 TrackTagType 保持一致；顺序按「出入口 → 垂直交通 → 设施 → 场所」排，采集时好找。
 */
export function trackTagNames(): Array<string> {
  return ['大门', '门', '门禁', '楼梯', '扶梯', '电梯', '厕所', '教室', '食堂', '商店', '其他室内'];
}

export interface Track {
  id: number;
  name: string;
  areaId?: number;
  areaName?: string;
  startedAt: number;
  endedAt?: number;
  pointCount: number;
}

export interface TrackPoint {
  id: number;
  trackId: number;
  timeMs: number;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  accuracy?: number;
  pressureHpa?: number;
  magneticX?: number;
  magneticY?: number;
  magneticZ?: number;
  /** 手机朝向（0-360°，加速度+地磁融合方位角，GPS direction 兜底） */
  headingDeg?: number;
  wifiCount: number;
  /**
   * 附近 AP 的摘要，格式 `bssid:rssi;bssid:rssi;…`。
   *
   * 2026-09-30 起保留**前 40 个**（按 rssi 降序、bssid 升序**确定**取，见 TrackRecorder.refreshWifi）；
   * 之前只留最强 5 个，实测在同一地点相隔 30 秒的两次扫描之间重合 0 个 —— 等于噪声。
   * 老数据仍然是 5 个（字段名与格式都没变，所以解析方式不用改）。
   */
  wifiTop: string;
}

/** 插入采样点时 id 尚未生成，使用无 id 版本 */
export interface TrackPointDraft {
  trackId: number;
  timeMs: number;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  accuracy?: number;
  pressureHpa?: number;
  magneticX?: number;
  magneticY?: number;
  magneticZ?: number;
  headingDeg?: number;
  wifiCount: number;
  /** 见 TrackPoint.wifiTop：从 2026-09-30 起是前 40 个（老数据 5 个） */
  wifiTop: string;
}

/** 轨迹途中打的「节点」标记（厕所/楼梯/门/门禁/电梯/教室 + 备注）。
 *  2026-09-28 起：节点是「标记 + 照片」的整体，照片是节点信息的必填部分
 *  （拍照失败或取消时节点不落库），照片存在 track_photos 且 kind='node'、tagId 指回本行。
 *  表名仍沿用 track_tags，避免改表名带来的迁移风险。 */
export interface TrackTag {
  id: number;
  trackId: number;
  timeMs: number;
  tagType: string;
  note: string;
  /** 手填楼层（用户 2026-09-28 确认：不做高度估算，由采集者填写）。空字符串 = 未填 */
  floor: string;
  /**
   * 这个节点属于哪个区域（一栋楼）—— 2026-09-29 新增，用户实测后提出：
   * 一条轨迹可以从校外一路穿过好几栋楼，轨迹本身只挂一个区域不够用，
   * 打标签时应当能选/切区域，节点各归各楼（「生成房间」也按它分楼建）。
   * undefined = 沿用轨迹的区域（旧数据）。
   */
  areaId?: number;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  /**
   * 打这个节点那一刻的定位精度（米，来自系统）—— 2026-09-29 新增（第二十五轮）。
   *
   * 采样点一直有 accuracy、节点却没有，后果很实在：室内拿到的那个「定位」常常是误差一两百米的
   * **网络定位**，节点照样带着它入库，于是在图上和实测坐标长得一模一样地摆着 ——
   * 而节点正是航位推算要当**锚点**用的东西，锚点不干净，后面补出来的室内段就全是错的。
   *
   * undefined = 老数据（2026-09-29 之前采的节点）。口径与采样点一致：**没记精度不算差**。
   */
  accuracy?: number;
  /**
   * 打这个节点时的气压（hPa）—— 2026-09-29 新增。
   * 采样点本来就有气压，节点却没有；补上之后「楼层高度索引」才能拿室内节点当依据
   * （室内没有 GPS 海拔，只剩气压可用），导出的节点数据也更完整。
   */
  pressureHpa?: number;
  /**
   * 这个节点绑定时写进房间的那条标记（markers.id）—— 2026-09-29 新增，可空。
   * 门 / 门禁绑了房间会往该房间插一条「前门 / 后门」标记；用户要求能**事后修正**绑错的房间，
   * 而「改绑到别的房间」必须先把旧房间里那条标记删掉 —— 记下它的 id 才能精确删，
   * 不去猜（猜错会删掉别人辛苦采的标记）。
   * undefined = 老数据（2026-09-29 之前采的），当时的绑定没留来历，
   * 改动房间时无法自动清理旧标记，界面会如实说明。
   */
  markerId?: number;
  headingDeg?: number;
  createdAt: number;
}

/**
 * 门 / 门禁节点绑定房间时，写进该房间的标记类型：
 * 备注里带「后」算后门，否则算前门（用户 2026-09-28 定的口径）。
 * 抽成函数是因为「记录时」和「事后编辑时」两处都要用同一个口径，写在两处迟早会分叉。
 */
export function markerTypeForNote(note: string): string {
  return note.indexOf('后') >= 0 ? MarkerType.BACK_DOOR : MarkerType.FRONT_DOOR;
}

/** 标记名：优先用节点备注（采集时填的「西侧铁门」这类实况描述），没备注就用节点类型名 */
export function markerNameForNote(note: string, tagType: string): string {
  return note.length > 0 ? note : tagType;
}

/** 照片分类：节点照（属于某个节点）/ 风景照（宣传美化用，不参与节点体系） */
export enum PhotoKind {
  NODE = 'node',
  SCENERY = 'scenery'
}

/** 轨迹途中拍的照片（filePath 为相对 filesDir 的沙箱路径，如 photos/12/1726450000000.jpg） */
export interface TrackPhoto {
  id: number;
  trackId: number;
  /** PhotoKind：'node' 节点照 / 'scenery' 风景照 */
  kind: string;
  /** 节点照所属节点的 id（track_tags.id）；风景照为 undefined */
  tagId?: number;
  timeMs: number;
  filePath: string;
  note: string;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  headingDeg?: number;
  createdAt: number;
}

/** 插入照片时 id 尚未生成，使用无 id 版本 */
export interface TrackPhotoDraft {
  trackId: number;
  kind: string;
  tagId?: number;
  timeMs: number;
  filePath: string;
  note: string;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  headingDeg?: number;
}

/**
 * 「记录节点」对话框的产出：类型 / 备注 / 楼层 / 归属的房间。
 * 放在数据层（而不是对话框文件里）有两个好处：它本来就是对 track_tags 的写入意图描述，
 * 而且非 UI 模块能被离线类型检查覆盖到（对话框里的内联字面量 tsc 编译不到）。
 */
export interface NodeDraft {
  tagType: string;
  note: string;
  floor: string;
  /** 这个节点归属的区域（建筑）id；-1 = 不分区域（旧数据/还没建区域） */
  areaId: number;
  /** 区域名（按钮/提示文案要用，避免再查一次库） */
  areaName: string;
  /** 门 / 门禁可选绑定（绑了就往这个房间写前门/后门标记）；不绑或其它类型为 -1 */
  roomId: number;
  roomName: string;
}
