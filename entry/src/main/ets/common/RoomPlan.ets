import { TrackTag, TrackTagType } from '../data/Entities';
import { fmtTime } from './Utils';

/**
 * 房间规划（纯函数，便于离线验证）：把一条轨迹里的节点转成「要新建的房间」清单。
 *
 * 口径（用户 2026-09-28 确认）：**只有「教室」节点对应一个房间**。
 * 厕所 / 楼梯 / 门 / 门禁 / 电梯都是设施，仍只作节点，不建房间。
 * 房间名优先取节点备注（采集时填的「301 会议室」这类真实房号）；备注为空时退化为
 * 「教室 <楼层>」，仍为空就只叫「教室」。同区域内已有同名房间（忽略大小写与空格）
 * 直接跳过，同一批内也去重——所以重复点「生成房间」不会产生重复房间。
 */
export interface RoomDraft {
  name: string;
  note: string;
  /** 来源节点 id（供界面核对/以后回溯用） */
  tagId: number;
  latitude?: number;
  longitude?: number;
  altitude?: number;
}

/** 教室类型名。取自 TrackTagType，避免字面量散落各处 */
const CLASSROOM_TAG: string = TrackTagType.CLASSROOM;

function normKey(s: string): string {
  return s.replace(/\s+/g, '').toLowerCase();
}

/** 是不是「教室」节点（房间的唯一来源） */
export function isClassroomTag(tag: TrackTag): boolean {
  return tag.tagType === CLASSROOM_TAG;
}

/** 教室节点数量：界面用它决定要不要显示「生成房间」 */
export function countClassroomTags(tags: TrackTag[]): number {
  let c = 0;
  for (const t of tags) {
    if (isClassroomTag(t)) {
      c++;
    }
  }
  return c;
}

/** 节点 → 房间名 */
export function roomNameOf(tag: TrackTag): string {
  const note: string = tag.note.trim();
  if (note.length > 0) {
    return note;
  }
  const floor: string = tag.floor.trim();
  return floor.length > 0 ? `${tag.tagType} ${floor}` : tag.tagType;
}

/** 一条轨迹里的教室节点 → 要新建的房间清单（existingNames 为该区域已有房间名） */
export function planRooms(tags: TrackTag[], existingNames: string[], trackName: string): RoomDraft[] {
  const taken: string[] = [];
  for (const n of existingNames) {
    taken.push(normKey(n));
  }
  const out: RoomDraft[] = [];
  for (const tag of tags) {
    if (tag.tagType !== CLASSROOM_TAG) {
      continue;
    }
    const name: string = roomNameOf(tag);
    const key: string = normKey(name);
    if (key.length === 0 || taken.indexOf(key) >= 0) {
      continue;
    }
    taken.push(key);
    const bits: string[] = [`来自轨迹「${trackName}」`];
    const floor: string = tag.floor.trim();
    if (floor.length > 0) {
      bits.push(`楼层 ${floor}`);
    }
    bits.push(fmtTime(tag.timeMs));
    const draft: RoomDraft = {
      name: name,
      note: bits.join(' · '),
      tagId: tag.id,
      latitude: tag.latitude,
      longitude: tag.longitude,
      altitude: tag.altitude
    };
    out.push(draft);
  }
  return out;
}
