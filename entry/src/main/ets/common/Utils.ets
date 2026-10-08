import { common } from '@kit.AbilityKit';
import { Track } from '../data/Entities';

/** 全局持有的 UIAbilityContext（传感器/后台任务/通知等需要） */
export class Ctx {
  static ui: common.UIAbilityContext | null = null;
}

export function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/** HH:mm:ss */
export function fmtTime(ms: number): string {
  const d: Date = new Date(ms);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

/** MM-dd HH:mm */
export function fmtDateTime(ms: number): string {
  const d: Date = new Date(ms);
  return `${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

/** YYYY-MM-DD HH:mm:ss（照片参数/导出索引用完整时间戳） */
export function fmtFullTime(ms: number): string {
  const d: Date = new Date(ms);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} `
    + `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

/** mm:ss 或 h:mm:ss */
export function fmtDuration(sec: number): string {
  const h: number = Math.floor(sec / 3600);
  const m: number = Math.floor((sec % 3600) / 60);
  const s: number = Math.floor(sec % 60);
  return h > 0 ? `${h}:${pad2(m)}:${pad2(s)}` : `${pad2(m)}:${pad2(s)}`;
}

export function coordText(lat?: number, lng?: number): string {
  if (lat !== undefined && lng !== undefined) {
    return `${lat.toFixed(6)}, ${lng.toFixed(6)}`;
  }
  return '无 GPS（室内正常）';
}

/** 默认轨迹名：轨迹 MM-dd HH:mm */
export function defaultTrackName(): string {
  return `轨迹 ${fmtDateTime(Date.now())}`;
}

/**
 * 加速度+地磁融合方位角（Android SensorManager.getRotationMatrix 移植）：
 * 返回手机屏幕朝向（0-360°，北=0），输入不足或磁场异常时返回 undefined。
 */
export function fusedAzimuth(accel: number[], mag: number[]): number | undefined {
  const ax = accel[0], ay = accel[1], az = accel[2];
  const ex = mag[0], ey = mag[1], ez = mag[2];
  let hx = ey * az - ez * ay;
  let hy = ez * ax - ex * az;
  let hz = ex * ay - ey * ax;
  const normH = Math.sqrt(hx * hx + hy * hy + hz * hz);
  if (normH < 0.1) {
    return undefined;
  }
  const invH = 1.0 / normH;
  hx *= invH; hy *= invH; hz *= invH;
  const normA = Math.sqrt(ax * ax + ay * ay + az * az);
  if (normA < 0.1) {
    return undefined;
  }
  const invA = 1.0 / normA;
  const axn = ax * invA, ayn = ay * invA, azn = az * invA;
  const mx = ayn * hz - azn * hy;
  const my = azn * hx - axn * hz;
  return (Math.atan2(my, mx) * 180 / Math.PI + 360) % 360;
}

/** 朝向角 → 中文方位（北/东北/…） */
export function compassDir(deg: number): string {
  const dirs: string[] = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
  const idx: number = Math.round(deg / 45) % 8;
  return dirs[idx];
}

/** 文件名安全化：替换路径分隔与非法字符 */
export function safeFileName(s: string): string {
  return s.replace(/[\s/\\:*?"<>|]+/g, '_');
}

// ---------- 轨迹列表：副标题 + 按天分组（用户 2026-09-29 要求「按天分类」） ----------

/**
 * 列表里一条轨迹的副标题：16:27:25 · 时长 05:41 · 341 点
 *
 * **2026-10-08 改：去掉了原来的 `[区域]` 前缀。** 轨迹不再归属区域（会跨区域），
 * 挂一个区域名在副标题上是错的。真要显示「采到哪栋楼」，应当由节点区域汇总而来，
 * 而 `Track` 里没有那个信息 —— 宁可先不显示，也不显示一个不存在的归属。
 */
export function trackSubtitle(t: Track): string {
  const end: number = t.endedAt !== undefined ? (t.endedAt as number) : t.startedAt;
  let s = `${fmtTime(t.startedAt)} · 时长 `
    + `${fmtDuration(Math.floor((end - t.startedAt) / 1000))} · ${t.pointCount} 点`;
  if (t.endedAt === undefined) {
    s += ' · 进行中';
  }
  return s;
}

const WEEKDAYS: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

/** 本地时区的当天零点。分组要按用户眼里的「天」切，不能用 UTC（东八区会把 08:00 前的算成前一天） */
export function startOfDay(ms: number): number {
  const d: Date = new Date(ms);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

/** 分组用的天键：YYYY-MM-DD（本地时区）。跨午夜就换一组，正是「按天分类」要的 */
export function dayKey(ms: number): string {
  const d: Date = new Date(ms);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/**
 * 分组标题：今天 / 昨天 / 09-27 周日。
 *
 * 用「两个零点之差」而不是直接减时间戳再取整：同一天的 00:05 和 23:55 只差 23.8 小时，
 * 直接除 86400000 取整会算成 0 天（对），但当天 00:05 与昨天 23:55 相差 24.2 小时会算成 1 天（也对）——
 * 真正出错的是「昨天 00:30」与「今天 23:30」相差 47 小时→2 天。零点相减没有这个问题。
 */
export function dayLabel(ms: number, nowMs: number): string {
  const diff: number = Math.round((startOfDay(nowMs) - startOfDay(ms)) / 86400000);
  // diff < 0 只可能是系统时钟被改过，也归到「今天」，免得出现「未来」这种奇怪标题
  if (diff <= 0) {
    return '今天';
  }
  if (diff === 1) {
    return '昨天';
  }
  const d: Date = new Date(ms);
  return `${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${WEEKDAYS[d.getDay()]}`;
}

export interface TrackDayGroup {
  key: string;
  label: string;
  tracks: Track[];
}

/** 列表行的种类 */
export const ROW_DAY: string = 'day';
export const ROW_TRACK: string = 'track';

/**
 * 摊平后的一行。做成一整行自带全部字段（而不是按 kind 去取 track 的字段），
 * 是因为 ArkUI 的声明式块里**不能写语句**（没法 `const t = r.track as Track`），
 * 用 `r.track!.name` 这种写法又容易在缺字段时空指针。
 */
export interface TrackRow {
  kind: string;
  key: string;
  /** 分组头：标题；轨迹行留空 */
  label: string;
  /** 分组头：该天的条数；轨迹行是 0 */
  count: number;
  /** 轨迹行：轨迹 id；分组头是 -1 */
  id: number;
  name: string;
  sub: string;
}

/**
 * 按天分组。输入必须是**按 startedAt 倒序**的（Store.listTracks 就是这么给的），
 * 本函数只做相邻合并、不排序 —— 万一排序和查询顺序不一致，列表看起来就是乱的。
 */
export function groupTracksByDay(tracks: Track[], nowMs: number): TrackDayGroup[] {
  const out: TrackDayGroup[] = [];
  for (const t of tracks) {
    const k: string = dayKey(t.startedAt);
    if (out.length === 0 || out[out.length - 1].key !== k) {
      const g: TrackDayGroup = { key: k, label: dayLabel(t.startedAt, nowMs), tracks: [] };
      out.push(g);
    }
    out[out.length - 1].tracks.push(t);
  }
  return out;
}

/**
 * 分组 → 一行一条的渲染序列（分组头也是一行）。
 *
 * 为什么不用 ListItemGroup + 粘性分组头：那要求分组标题走 @Builder，而本项目吃过
 * 「@Builder 按值传参不刷新」的亏（见 TrackDetail 统计卡片那段注释）——分组标题正是
 * 「算好了按值传进去」的，跨过午夜那一刻就会一直停在「今天」。摊平之后每一行都是普通 ListItem，
 * 全走 @State 的刷新路径，没有这个隐患；列表本来就短，也不值得为粘性头去冒险。
 */
export function flattenTracksByDay(groups: TrackDayGroup[]): TrackRow[] {
  const rows: TrackRow[] = [];
  for (const g of groups) {
    rows.push({ kind: ROW_DAY, key: `d-${g.key}`, label: g.label, count: g.tracks.length, id: -1, name: '', sub: '' });
    for (const t of g.tracks) {
      rows.push({
        kind: ROW_TRACK, key: `t-${t.id}`, label: '', count: 0,
        id: t.id, name: t.name, sub: trackSubtitle(t)
      });
    }
  }
  return rows;
}
