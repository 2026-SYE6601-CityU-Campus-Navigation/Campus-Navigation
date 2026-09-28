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
  DOOR = '门',
  GATE = '门禁',
  ELEVATOR = '电梯',
  CLASSROOM = '教室'
}

export function trackTagOptions(): Array<SelectOption> {
  return [
    { value: TrackTagType.TOILET },
    { value: TrackTagType.STAIRS },
    { value: TrackTagType.DOOR },
    { value: TrackTagType.GATE },
    { value: TrackTagType.ELEVATOR },
    { value: TrackTagType.CLASSROOM }
  ];
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

/** 轨迹途中打的标签点（厕所/楼梯/门/门禁/电梯/教室 + 备注） */
export interface TrackTag {
  id: number;
  trackId: number;
  timeMs: number;
  tagType: string;
  note: string;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  headingDeg?: number;
  createdAt: number;
}

/** 轨迹途中拍的照片（filePath 为相对 filesDir 的沙箱路径，如 photos/12/1726450000000.jpg） */
export interface TrackPhoto {
  id: number;
  trackId: number;
  timeMs: number;
  filePath: string;
  note: string;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  headingDeg?: number;
  createdAt: number;
}
