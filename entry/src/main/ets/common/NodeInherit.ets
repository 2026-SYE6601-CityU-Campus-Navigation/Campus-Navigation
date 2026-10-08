import { TrackTag } from '../data/Entities';
import { effectiveAreaId } from './RoomPlan';

/**
 * 「上一个节点」的继承信息 —— 记录新节点时「楼层 / 区域」两项默认值的来源。
 *
 * 为什么要有继承（2026-10-08 用户要求：「记录结点的时候我希望楼层，区域的选择能够继承
 * 上一个标点的信息」）：在楼里连着打 5~10 个节点时，楼层和所在建筑基本不变，
 * 每次都从头选一遍既是纯体力活，也是**错数据的来源** —— 漏选一次，这个节点就归错楼了，
 * 而「生成房间」正是按区域分楼建的，一处错会跟着错一串。所以默认值直接沿用上一个节点。
 *
 * 为什么继承的是**上一个节点自己带的**值，而不是「最近一个填过楼层的节点」：
 * 上一个节点如果真的没填楼层，那是它的事实。偷偷从更早的节点抓一个来填，
 * 就凭空造出了一个用户从没确认过的楼层 —— 那正是本项目反复强调要避免的「猜」。
 * 宁可承认「上一个也没填」，把空值如实继承下来。
 *
 * 纯函数，不含数据库与 UI：判定规则抽在这里才能被离线单测覆盖到。
 */
export interface InheritedNode {
  /** 这条轨迹里有没有上一个节点。false 时调用方**不覆盖**任何默认值 */
  exists: boolean;
  /** 上一个节点的楼层；空串 = 它没填，那就继承一个空 */
  floor: string;
  /** 上一个节点的区域 id；<= 0 = 未分区（口径同 effectiveAreaId） */
  areaId: number;
  /** 上一个节点的类型名（界面上告诉用户「继承自哪个节点」，别让它来路不明） */
  tagType: string;
  /** 上一个节点的采集时刻 */
  timeMs: number;
}

/** 「没有上一个节点」时的取值（第一个节点就走这条路）；调用方不必再判 undefined */
export function noInherit(): InheritedNode {
  const out: InheritedNode = {
    exists: false, floor: '', areaId: 0, tagType: '', timeMs: 0
  };
  return out;
}

/**
 * 取时间上**最后一个**节点；时间并列时取 id 大的。
 *
 * 不吃「数组里的顺序」：`listTrackTags` 虽然按 timeMs 升序给出，但用户事后修改过更早的
 * 节点（修改不动 timeMs，只改内容），而且异常退出后重录可能出现时间并列。
 * `timeMs` 才是采集顺序的事实，这里自己挑一遍，不依赖上游排序。
 */
export function previousNode(tags: TrackTag[]): InheritedNode {
  let best: TrackTag | undefined = undefined;
  for (const g of tags) {
    if (best === undefined) {
      best = g;
      continue;
    }
    if (g.timeMs > best.timeMs || (g.timeMs === best.timeMs && g.id > best.id)) {
      best = g;
    }
  }
  if (best === undefined) {
    return noInherit();
  }
  const out: InheritedNode = {
    exists: true,
    floor: best.floor,
    areaId: effectiveAreaId(best),
    tagType: best.tagType,
    timeMs: best.timeMs
  };
  return out;
}
