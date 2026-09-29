/**
 * 数据实体：与 Android 版 Room 表结构一一对应。
 * 可空字段（undefined）对应数据库 NULL。
 */

export interface Room {
  id: number;
  name: string;
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

/** 区域（文件夹）：顶层组织单位，房间与轨迹都归属某个区域。id=0 约定为「未分区」（areaId 为 NULL） */
export interface Area {
  id: number;
  name: string;
  note: string;
  roomCount: number;
  trackCount: number;
  createdAt: number;
}

/** 轨迹途中标签类型（与房间标记 MarkerType 是两套体系） */
export enum TrackTagType {
  TOILET = '厕所',
  STAIRS = '楼梯',
  /** 扶梯（自动扶梯）—— 城大垂直交通的主要方式之一，和楼梯分开记 */
  ESCALATOR = '扶梯',
  DOOR = '门',
  GATE = '门禁',
  ELEVATOR = '电梯',
  CLASSROOM = '教室'
}

/** 需要归属到某个房间的节点类型（用户 2026-09-28 要求：标记「门」时和房间绑到一起） */
export function roomBoundTagTypes(): Array<string> {
  return [TrackTagType.DOOR, TrackTagType.GATE];
}

export function trackTagOptions(): Array<SelectOption> {
  return [
    { value: TrackTagType.TOILET },
    { value: TrackTagType.STAIRS },
    { value: TrackTagType.ESCALATOR },
    { value: TrackTagType.DOOR },
    { value: TrackTagType.GATE },
    { value: TrackTagType.ELEVATOR },
    { value: TrackTagType.CLASSROOM }
  ];
}

/**
 * 节点类型名（纯 string 数组），供界面自己遍历渲染。
 * 刻意不复用 trackTagOptions()：它的 SelectOption.value 是 ResourceStr（可能为 Resource），
 * 拿来当 string 用会被 ArkTS 编译器拒绝（Select 组件自己用没问题）。
 * 取值与 TrackTagType 保持一致。
 */
export function trackTagNames(): Array<string> {
  return ['厕所', '楼梯', '扶梯', '门', '门禁', '电梯', '教室'];
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
  latitude?: number;
  longitude?: number;
  altitude?: number;
  headingDeg?: number;
  createdAt: number;
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
  /** 门 / 门禁必选（要往这个房间写前门/后门标记）；其它类型为 -1 */
  roomId: number;
  roomName: string;
}
