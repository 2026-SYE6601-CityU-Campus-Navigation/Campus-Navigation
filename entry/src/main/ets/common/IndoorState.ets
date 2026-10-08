import { INDOOR_IN, INDOOR_OUT, INDOOR_UNKNOWN, TrackSegment, TrackTag } from '../data/Entities';

/**
 * 室内 / 室外三态 + 轨迹分段（纯函数，便于离线验证）。
 *
 * 这里**不含任何 UI 与数据库**：按钮按一下之后「关哪一段、开哪一段」是纯逻辑，
 * 抽出来才能被离线单测覆盖到（对话框/录制页里的内联逻辑 tsc 编译不到，这是项目里
 * 反复吃过的亏）。
 *
 * 状态循环：未标 → 室内 → 室外 → 未标。
 * 刻意不把「未标」和「室外」合并：录制时可能整趟都没按过按钮，
 * 把「没标」当成「室外」是**错的**，而「未标」是诚实的。
 */
export function nextIndoor(cur: number): number {
  if (cur === INDOOR_UNKNOWN) {
    return INDOOR_IN;
  }
  if (cur === INDOOR_IN) {
    return INDOOR_OUT;
  }
  return INDOOR_UNKNOWN;
}

/** 完整名（列表/导出/统计里用） */
export function indoorLabel(v: number): string {
  if (v === INDOOR_IN) {
    return '室内';
  }
  if (v === INDOOR_OUT) {
    return '室外';
  }
  return '未标';
}

/** 按钮上用的短标签：要能一眼看出「再按一下会变成什么」，所以未标态写的是目标而不是现状 */
export function indoorButtonText(cur: number): string {
  return `切到${indoorLabel(nextIndoor(cur))}`;
}

/**
 * 某个时刻落在哪一段。多段重叠时取**起点最晚**的那一段（后开的覆盖先开的）。
 * 没有任何段覆盖 → INDOOR_UNKNOWN。
 *
 * 拐点的室内/室外就是这么来的：查它落在哪一段，**不需要在 track_corners 上加字段**。
 */
export function indoorOf(segments: TrackSegment[], timeMs: number): number {
  let best: TrackSegment | undefined = undefined;
  for (const s of segments) {
    if (s.startMs > timeMs) {
      continue;
    }
    if (s.endMs !== undefined && timeMs >= s.endMs) {
      continue;
    }
    if (best === undefined || s.startMs > best.startMs) {
      best = s;
    }
  }
  return best === undefined ? INDOOR_UNKNOWN : best.indoor;
}

/**
 * 按一下按钮要做的两件事（纯描述，真正落库由 Store 执行）。
 * `closeId` 为 -1 表示当前没有开着段（例如刚开录、或上一段已被收尾），只需新开一段。
 */
export interface TogglePlan {
  /** 要关掉的段 id；-1 = 没有 */
  closeId: number;
  /** 关掉的时刻（也是新段的起点），毫秒 */
  atMs: number;
  /** 新段的状态 */
  next: number;
}

export function planToggle(openId: number, openIndoor: number, nowMs: number): TogglePlan {
  return { closeId: openId, atMs: nowMs, next: nextIndoor(openIndoor) };
}

/**
 * 一段覆盖的时长（毫秒）。未收尾的段按 nowMs 算，于是「正在录的那一段」也能显示时长。
 */
export function segmentDurationMs(s: TrackSegment, nowMs: number): number {
  const end: number = s.endMs === undefined ? nowMs : s.endMs;
  return end > s.startMs ? end - s.startMs : 0;
}

/**
 * 把一整条轨迹的段压成「室内 / 室外 / 未标」各占多少毫秒。
 * 未收尾的段按 nowMs 截断。界面上那一行统计与导出包的摘要都用它，避免两处各算一次。
 */
export interface IndoorTotals {
  inMs: number;
  outMs: number;
  unknownMs: number;
}

export function indoorTotals(segments: TrackSegment[], nowMs: number): IndoorTotals {
  const t: IndoorTotals = { inMs: 0, outMs: 0, unknownMs: 0 };
  for (const s of segments) {
    const d: number = segmentDurationMs(s, nowMs);
    if (s.indoor === INDOOR_IN) {
      t.inMs += d;
    } else if (s.indoor === INDOOR_OUT) {
      t.outMs += d;
    } else {
      t.unknownMs += d;
    }
  }
  return t;
}

/**
 * 事后修正一段室内外：把某一段在某个时刻**切成两半**（2026-10-08 批次三新增）。
 *
 * 为什么必须有这个功能：录制时那个三态按钮是人在走、在分神的时候按的。
 * 「进楼那一下忘了按」是这个功能最常见、也最要命的错 —— 不切成两半就没法补，
 * 因为整条轨迹只有一段，无论怎么切状态都只能让**整条**变室内或室外。
 *
 * 切分点从哪里来：**用节点**（门 / 门禁 / 楼梯 这些用户当时精确按下过的点），
 * 而不是让用户去挑时间。节点的时间是按下那一刻的精确时间，这正是段边界要的精度
 * （也是当初为什么它不走「填表+拍照」那条会晚 15~25 米的流程）。所以这里只接受
 * 落在候选节点上的时刻，界面上也是让用户「选一个节点」。
 *
 * 返回 undefined = 这个时刻不能切（不在这一段内部）。**宁可拒绝，也不切出一个零长度的段**：
 * 零长度段在列表里是噪音，还会让「并入上一段」之类的操作出现无意义的边界。
 */
export interface SegmentSplit {
  /** 被切开的那一段（它的 endMs 会收到 atMs） */
  segId: number;
  trackId: number;
  /** 切分时刻 = 新段的起点 */
  atMs: number;
  /** 新开的**后半段**的状态 */
  newIndoor: number;
  /** 后半段要继承的结束时刻；undefined = 原来就是开着的（正在录），继续开着 */
  endMs?: number;
}

export function planSplit(seg: TrackSegment, atMs: number, newIndoor: number): SegmentSplit | undefined {
  if (atMs <= seg.startMs) {
    return undefined;
  }
  if (seg.endMs !== undefined && atMs >= (seg.endMs as number)) {
    return undefined;
  }
  const out: SegmentSplit = {
    segId: seg.id,
    trackId: seg.trackId,
    atMs: atMs,
    newIndoor: newIndoor,
    endMs: seg.endMs
  };
  return out;
}

/**
 * 落在这一段内部、可以作为切分点的节点（按时间升序）。
 *
 * 判据与 planSplit 保持一致（严格在内部），所以「列出来的都能切」——
 * 界面上不会出现点了却报「这个时刻不能切」的情况。
 */
export function nodesInsideSegment(tags: TrackTag[], seg: TrackSegment): TrackTag[] {
  const out: TrackTag[] = [];
  for (const g of tags) {
    if (g.timeMs <= seg.startMs) {
      continue;
    }
    if (seg.endMs !== undefined && g.timeMs >= (seg.endMs as number)) {
      continue;
    }
    out.push(g);
  }
  return out;
}

/**
 * 「并入上一段」要用的那一段：按起点排在 seg 前面的**最后一段**。
 * 返回 undefined = seg 就是第一段（那就没有上一段可并，界面上不显示这个按钮）。
 */
export function previousSegment(segments: TrackSegment[], seg: TrackSegment): TrackSegment | undefined {
  let best: TrackSegment | undefined = undefined;
  for (const s of segments) {
    if (s.id === seg.id || s.startMs >= seg.startMs) {
      continue;
    }
    if (best === undefined || s.startMs > best.startMs) {
      best = s;
    }
  }
  return best;
}

/**
 * 把 seg 并入前一段的计划（2026-10-08 批次三）。
 *
 * 合并后那一段取**前一段的状态**（用户的意思正是「这一段不该存在、应该接着前一段」），
 * 时间范围取两段的并集。实现取向是「保留后一段、把它的起点与状态改成前一段的、删掉前一段」，
 * 而不是「把前一段的 endMs 延长过去」：后者在后面那段**还开着**（正在录）时得把前一段
 * 重新置成 NULL，而往 ValuesBucket 里写 null 需要额外确认；这一版只用「改两列数字 + 删一行」，
 * 全走已经验证过的写法，也不必碰 endMs 的可空语义。
 *
 * 决策留在纯函数里（而不是写在 Store 里），这样「并入之后是什么状态」可以被离线单测钉住。
 */
export interface SegmentMerge {
  /** 保留的那一段（起点与状态会被改成前一段的） */
  keepId: number;
  /** 要删掉的那一段（前一段） */
  delId: number;
  /** 合并后这一段的起点 = 前一段的起点 */
  startMs: number;
  /** 合并后这一段的状态 = 前一段的状态 */
  indoor: number;
}

export function planMerge(seg: TrackSegment, prev: TrackSegment | undefined): SegmentMerge | undefined {
  if (prev === undefined) {
    return undefined;
  }
  const out: SegmentMerge = {
    keepId: seg.id,
    delId: prev.id,
    startMs: prev.startMs,
    indoor: prev.indoor
  };
  return out;
}
