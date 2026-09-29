import { floorKey } from './Track3D';

/**
 * 楼层高度索引（纯函数，便于离线验证）。
 *
 * 用户 2026-09-29 提出的需求原文：「如果检测到在某一在案的楼层高度，默认那个楼层，
 * 当然也支持手动修改」—— 即：过去在**同一栋楼**里记过「某层 ≈ 某个高度」，
 * 下次采集时按当前高度自动带出楼层名，减轻逐个节点手填的负担。
 *
 * 所以这不是「按气压算楼层」的高度估算（那件事 2026-09-28 已明确不做），
 * 而是「**查已经记过的楼层**」：只认你自己采过的楼层，采不到就一个字都不猜。
 *
 * 两条高度依据，优先级与适用条件不同：
 *  1. **海拔（altitude）** —— GPS 给的大地高，跨天可比（不受天气影响）。但室内没有 GPS，
 *     所以只有露天/近门口的点才有。有就用它，容差 2.5 m。
 *  2. **气压（pressureHpa）** —— 室内也有。但绝对气压随天气漂移（几天可差十几 hPa ≈ 上百米），
 *     所以只在**观测足够新**（默认 12 小时内）时参与比对，容差 0.35 hPa ≈ 3 m。
 *
 * 楼层名归一化复用 Track3D 的 floorKey()（忽略空格/大小写、去掉 /F 与结尾 F），
 * 保证「3」「3/F」「3F」在学习与匹配两侧算同一层，也与立体图的图层分组口径一致。
 */

/** 一条「楼层 ≈ 高度」的观测记录（一条楼层一行，学到的会覆盖同层旧值） */
export interface FloorObservation {
  /** 归一化楼层键（floorKey），判同一层用 */
  key: string;
  /** 实际写下的楼层名（显示用，如「3/F」） */
  floor: string;
  pressureHpa?: number;
  altitude?: number;
  /** 学到这条记录的时间（毫秒），气压新鲜度判定要用 */
  updatedAt: number;
}

/** 待判定的当前高度（来自采集时/编辑时的实测快照） */
export interface FloorProbe {
  pressureHpa?: number;
  altitude?: number;
}

/** 推测结果：floor 为空串表示没推测出来（调用方就不该改用户填的值） */
export interface FloorGuess {
  floor: string;
  /** 依据：FLOOR_BY_ALTITUDE / FLOOR_BY_PRESSURE / 空串（没推测出来） */
  by: string;
}

export const FLOOR_BY_ALTITUDE: string = 'altitude';
export const FLOOR_BY_PRESSURE: string = 'pressure';

/** 海拔容差（米）。同层在不同点按下会差一点，2.5 m 够用又不会串到隔壁层（层高约 3–4 m） */
const ALT_TOL_M: number = 2.5;
/** 气压容差（hPa）。1 hPa ≈ 8.4 m，0.35 hPa ≈ 3 m */
const PRESS_TOL_HPA: number = 0.35;
/** 气压观测的保鲜期（毫秒）。超过它就不参与比对 —— 天气已经把绝对气压改变了 */
const PRESS_FRESH_MS: number = 12 * 60 * 60 * 1000;

/** 由「楼层 + 当前实测高度」造一条观测记录（Store 落库前用它，测试也用它） */
export function observationFrom(floor: string, probe: FloorProbe, nowMs: number): FloorObservation {
  return {
    key: floorKey(floor),
    floor: floor,
    pressureHpa: probe.pressureHpa,
    altitude: probe.altitude,
    updatedAt: nowMs
  };
}

/** 按海拔找最近的一层（容差内）；找不到返回 undefined */
function nearestByAltitude(obs: FloorObservation[], alt: number): FloorObservation | undefined {
  let best: FloorObservation | undefined = undefined;
  let bestD: number = ALT_TOL_M;
  for (const o of obs) {
    if (o.altitude === undefined) {
      continue;
    }
    const d: number = Math.abs(o.altitude - alt);
    if (d <= bestD) {
      bestD = d;
      best = o;
    }
  }
  return best;
}

/** 按气压找最近的一层（容差内、且观测没过期）；找不到返回 undefined */
function nearestByPressure(obs: FloorObservation[], p: number, nowMs: number): FloorObservation | undefined {
  let best: FloorObservation | undefined = undefined;
  let bestD: number = PRESS_TOL_HPA;
  for (const o of obs) {
    if (o.pressureHpa === undefined) {
      continue;
    }
    if (nowMs - o.updatedAt > PRESS_FRESH_MS) {
      continue;
    }
    const d: number = Math.abs(o.pressureHpa - p);
    if (d <= bestD) {
      bestD = d;
      best = o;
    }
  }
  return best;
}

/**
 * 推测楼层：先按海拔（跨天可靠），没命中再按气压（限新鲜观测）。
 * 两者都没有或都在容差外 → 返回空串，**不猜**（调用方保留用户已填的值）。
 */
export function matchFloor(obs: FloorObservation[], probe: FloorProbe, nowMs: number): FloorGuess {
  if (obs.length === 0) {
    return { floor: '', by: '' };
  }
  if (probe.altitude !== undefined) {
    const hit: FloorObservation | undefined = nearestByAltitude(obs, probe.altitude);
    if (hit !== undefined) {
      return { floor: hit.floor, by: FLOOR_BY_ALTITUDE };
    }
  }
  if (probe.pressureHpa !== undefined) {
    const hit: FloorObservation | undefined = nearestByPressure(obs, probe.pressureHpa, nowMs);
    if (hit !== undefined) {
      return { floor: hit.floor, by: FLOOR_BY_PRESSURE };
    }
  }
  return { floor: '', by: '' };
}

/** 推测依据的中文说法（界面提示用）；没推测出来时返回空串 */
export function guessByLabel(by: string): string {
  if (by === FLOOR_BY_ALTITUDE) {
    return '海拔';
  }
  if (by === FLOOR_BY_PRESSURE) {
    return '气压';
  }
  return '';
}

/**
 * 一行提示文案，如「按海拔推测：4/F（可改）」。
 * 没推测出来返回空串，界面据此决定这一行显不显示。
 */
export function guessLabel(g: FloorGuess): string {
  if (g.floor.length === 0) {
    return '';
  }
  return `按${guessByLabel(g.by)}推测：${g.floor}（可改）`;
}
