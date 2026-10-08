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
 *
 * 2026-09-29 改动（用户实测后提出「一条轨迹要从校外一路穿过好几栋楼」）：
 * 房间不再统一建到轨迹的区域，而是**建到节点自己的区域**——每个节点在打标签时可以选/切区域，
 * 一条跨楼轨迹里的教室节点各回各楼。因此这里先按区域把教室节点分组，
 * 每个区域各自去重（同名只在这栋楼里算重复）。
 */
export interface RoomDraft {
  /** 这个房间建到哪个区域（= 该组节点的区域） */
  areaId: number;
  name: string;
  note: string;
  /** 来源节点 id（供界面核对/以后回溯用） */
  tagId: number;
  latitude?: number;
  longitude?: number;
  altitude?: number;
}

/** 按区域分好组的教室节点 */
export interface AreaTagGroup {
  areaId: number;
  tags: TrackTag[];
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

/**
 * 节点实际归属的区域：**只认节点自己写的那个**（2026-10-08 改）。
 *
 * 旧口径是「节点没写就沿用轨迹的区域」，但轨迹已经不归属区域了（一条轨迹会跨好几栋楼，
 * 用它的区域去兜底本身就是错的），所以回退值取消 —— 节点没写就是「不属于任何楼」。
 * 老数据不会有问题：升级时已经把「NULL 的节点 areaId」按当时的轨迹区域回填过了
 * （见 Store 里那段一次性 UPDATE）。
 *
 * 返回 <= 0 表示这个节点不属于任何真实区域（未分区/还没建区域），不能建房。
 */
export function effectiveAreaId(tag: TrackTag): number {
  return (tag.areaId !== undefined && tag.areaId > 0) ? tag.areaId : 0;
}

/**
 * 把轨迹里的教室节点按「各自归属的区域」分组，只保留能建房的组（区域 > 0）。
 * 组内保持原时间顺序（tags 已是按 timeMs 升序查出来的）。
 */
export function groupClassroomTagsByArea(tags: TrackTag[]): AreaTagGroup[] {
  const out: AreaTagGroup[] = [];
  for (const tag of tags) {
    if (!isClassroomTag(tag)) {
      continue;
    }
    const aId: number = effectiveAreaId(tag);
    if (aId <= 0) {
      continue;
    }
    let group: AreaTagGroup | undefined = undefined;
    for (const g of out) {
      if (g.areaId === aId) {
        group = g;
        break;
      }
    }
    if (group === undefined) {
      group = { areaId: aId, tags: [] };
      out.push(group);
    }
    group.tags.push(tag);
  }
  return out;
}

/** 能不能生成房间：至少有一个教室节点属于真实区域 */
export function canPlanRooms(tags: TrackTag[]): boolean {
  return groupClassroomTagsByArea(tags).length > 0;
}

/**
 * 一条轨迹里节点出现最多的那个区域 id（0 = 没有）。
 *
 * 用途：轨迹详情页给节点标区域简称时，用它当「基线」——落在基线区域里的节点不显示简称，
 * 只有「离题」的那些才显示。旧口径拿「轨迹自身的区域」当基线，但轨迹已经不归属区域了，
 * 于是改成「这条轨迹主要在哪个楼」，语义比原来更贴切（跨楼轨迹里也不会满屏重复）。
 * 并列时取 id 小的，保证结果稳定（同一批数据每次跑出来一样）。
 */
export function dominantAreaId(tags: TrackTag[]): number {
  const ids: number[] = [];
  const counts: number[] = [];
  for (const tag of tags) {
    const aId: number = effectiveAreaId(tag);
    if (aId <= 0) {
      continue;
    }
    let at = -1;
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] === aId) {
        at = i;
        break;
      }
    }
    if (at < 0) {
      ids.push(aId);
      counts.push(1);
    } else {
      counts[at] = counts[at] + 1;
    }
  }
  let bestId = 0;
  let bestN = 0;
  for (let i = 0; i < ids.length; i++) {
    if (counts[i] > bestN || (counts[i] === bestN && ids[i] < bestId)) {
      bestId = ids[i];
      bestN = counts[i];
    }
  }
  return bestId;
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

/**
 * 一组（同一区域内的）教室节点 → 要新建的房间清单。
 * existingNames 是**该区域**已有的房间名；同名（忽略大小写与空格）跳过，批内也去重。
 */
export function planRooms(tags: TrackTag[], existingNames: string[], trackName: string,
  areaId: number): RoomDraft[] {
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
      areaId: areaId,
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
