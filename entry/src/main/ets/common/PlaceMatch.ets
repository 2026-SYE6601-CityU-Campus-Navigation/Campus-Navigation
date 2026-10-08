import { PlaceScan, WifiPoint } from '../data/Entities';
import { ApSample, parseWifiSummary } from './WifiSummary';

/**
 * 「我在哪」——把录过的节点变成指纹地图，再拿当前的扫描去认位置。
 *
 * ⚠️ 这个模块**只做纯计算**（不碰数据库、不碰传感器、不画界面），原因和 `IndoorState` 一样：
 * 判定规则必须能被离线单测与真实数据跑一遍。算法是从 2026-10-08 在 PC 上验证过的那套
 * （`outputs/build_place_map.py` + `outputs/locate.py`）**逐条搬过来**的，参数不变，
 * 因为在真实数据上验过一次的结果不能再靠感觉改。
 *
 * 那套算法在真实数据上的成绩（室外包 track_6：958 点 / 每点 40 个 AP / 17 个节点）：
 *  - 9 个门两两的指纹几乎完全可分（对角线 1.00，72 对里 0 对 >0.5）；
 *  - 只用每个门「门口前 6 秒」当模板，认 4/F 走廊那 772 个点 → 预测序列
 *    LT10→LT8→LT4→LT1→LT3→LT5→LT7→LT9→LT11 与实测顺序完全一致（9/9）；
 *  - 每段是连续约 60 秒的稳定块（不是逐秒乱跳）；
 *  - 负向验证（把 BSSID 换成全局池随机地址）0/958。
 *
 * ⚠️ **一个还没验的前提**：以上全部来自**同一次走动、同一个 App 安装**。
 * 手机 MAC 随机化通常按小时级轮换，**重装 App 或改包名会让旧指纹全废**
 * （本项目改过包名 `hk.edu.cityu.campusnav`，早于那次改动的数据一律不能用作模板）。
 * 所以页面上那个「原地静止扫描」入口不是装饰：它就是为了回答「隔 2 小时 / 隔天还能不能认出来」。
 *
 * ⚠️ **绝不承诺米级坐标**：这套东西给的是「最近的是哪个地点」。室内没有可用定位，
 * 而指纹能回答的本来就是「你在哪个点附近」。连续坐标要靠航位推算，那条已被两次真实数据证伪
 * （终点误差 18~27 m，见 2026-10-08 的样本外检验）。
 */

// ---------------------------------------------------------------- 参数（都有实测依据）

/** 匹配时只用最强的 N 个 AP。离线 N 扫描 8~40 覆盖率 97~100%（**对 N 不敏感**），取中间值 */
export const PLACE_TOP_N: number = 30;
/** 重合系数下限。实测同地点中位 1.00、异地最大 0.29，0.30 是「放宽但仍然分得开」的位置 */
export const PLACE_MIN_SCORE: number = 0.30;
/** 领先第二名的最小差距：防止两个门分数接近时来回跳 */
export const PLACE_MARGIN: number = 0.05;
/** 连续几次都指向同一个地点才确认切换（暂定值；页面上每秒一次 → 约 2 秒） */
export const PLACE_HOLD: number = 2;
/** 地标指纹的时间窗：节点时刻前后各 6 秒内的采样点（与离线建图一致） */
export const PLACE_HALF_WINDOW_S: number = 6;
/** 置信度分档（只用于界面文案；分数本身也一并显示，避免「高/中/低」被当成精确结论） */
export const PLACE_CONF_HIGH: number = 0.70;
export const PLACE_CONF_MID: number = 0.45;

// ---------------------------------------------------------------- 建图

/** 一次观测：某个采样点解析出来的 AP 列表 + 当时的气压 */
export interface PlaceObservation {
  aps: ApSample[];
  pressureHpa?: number;
}

/**
 * 一个地标的原始素材（页面从数据库里取出来喂进来）。
 * `observations` 是它时间窗内的若干采样点，聚合交给 mergeLandmarks。
 */
export interface LandmarkSeed {
  /** 跨会话稳定的身份键，由 landmarkKeyOf 生成 */
  key: string;
  /** 给人看的名字：房间号 · 楼层 · 建筑 */
  label: string;
  floor: string;
  building: string;
  /** 会话 id（本工程 = 轨迹 id：一条轨迹就是一次走动） */
  sessionId: number;
  observations: PlaceObservation[];
}

/** 一个 AP 的聚合结果。n = 观测次数，sessions = 在几个会话里出现过 */
export interface ApStat {
  bssid: string;
  /** RSSI 均值（与离线建图一致：逐次增量平均，不是取中位数） */
  rssi: number;
  n: number;
  sessions: number[];
}

/** 聚合后的地标 */
export interface Landmark {
  key: string;
  label: string;
  floor: string;
  building: string;
  /** 见过的全部 AP（已按 rssi 降序、bssid 升序排好） */
  aps: ApStat[];
  pressureHpa?: number;
  /** 见过它的会话（升序） */
  sessions: number[];
  /** 每个会话都出现过的 AP —— 地址轮换后只剩这批能对上；会话数 <2 时为空 */
  structural: string[];
}

/**
 * 地标的身份键。**规则的核心是「能不能跨会话认得出这是同一个地方」**：
 *
 *  - 绑过房间 → 房间是唯一的（`room:<建筑>#<房间id>`）→ 可以跨会话合并；
 *  - 没绑房间但有备注 → 用「建筑 + 楼层 + 备注」当键 → 也可以合并；
 *  - 两样都没有（如「门 4/F」，一趟里就有好几个）→ **绝不跨会话合并**，
 *    键里带上轨迹与节点 id。
 *
 * 为什么无名节点不让合并：把三个不同位置的「门」的签名拌在一起，得到的是一个
 * 哪儿都不是的平均值 —— 离线建图（build_place_map.py）当初就是这么定的（`auto_merge=False`）。
 * 代价要认：**不写备注的节点永远长不结实**，跨会话只有写过的那些能认。
 */
export interface LandmarkIdentity {
  roomId: number;
  note: string;
  tagType: string;
  floor: string;
  building: string;
  trackId: number;
  tagId: number;
}

export function landmarkKeyOf(g: LandmarkIdentity): string {
  if (g.roomId > 0) {
    return `room:${g.building}#${g.roomId}`;
  }
  const note: string = g.note.trim();
  if (note.length > 0) {
    return `note:${g.building}@${g.floor}|${note}`;
  }
  return `anon:${g.trackId}#${g.tagId}`;
}

/** 界面上的默认名字：有备注就用备注，否则「类型 楼层」；建筑由页面另行拼接 */
export function landmarkBaseName(g: LandmarkIdentity, roomName: string): string {
  if (roomName.length > 0) {
    return roomName;
  }
  const note: string = g.note.trim();
  if (note.length > 0) {
    return note;
  }
  return g.floor.length > 0 ? `${g.tagType} ${g.floor}` : g.tagType;
}

/** 按 (rssi 降序, bssid 升序) 取前 n 个 —— 与 `wifiSummary` 的排序规则必须一致 */
export function topN(aps: ApSample[], n: number): ApSample[] {
  const sorted: ApSample[] = aps.slice();
  sorted.sort((a: ApSample, b: ApSample): number => {
    if (a.rssi !== b.rssi) {
      return b.rssi - a.rssi;
    }
    if (a.bssid === b.bssid) {
      return 0;
    }
    return a.bssid < b.bssid ? -1 : 1;
  });
  return sorted.length > n ? sorted.slice(0, n) : sorted;
}

function addSession(sessions: number[], sessionId: number): void {
  if (sessions.indexOf(sessionId) < 0) {
    sessions.push(sessionId);
  }
}

/**
 * 把若干地标素材聚合成地标。**同一个 key 的多个 seed 会合并**（这就是跨会话强化），
 * 所以调用方可以一次性把所有轨迹的所有节点都喂进来，不必自己按 key 分组。
 */
export function mergeLandmarks(seeds: LandmarkSeed[]): Landmark[] {
  const out: Landmark[] = [];
  for (const seed of seeds) {
    let lm: Landmark | undefined = undefined;
    for (const cur of out) {
      if (cur.key === seed.key) {
        lm = cur;
        break;
      }
    }
    if (lm === undefined) {
      const fresh: Landmark = {
        key: seed.key, label: seed.label, floor: seed.floor, building: seed.building,
        aps: [], pressureHpa: undefined, sessions: [], structural: []
      };
      out.push(fresh);
      lm = fresh;
    }
    // 标签取最新一次看到的（备注/楼层可能被事后改过，以当前的为准）
    lm.label = seed.label;
    if (seed.floor.length > 0) {
      lm.floor = seed.floor;
    }
    if (seed.building.length > 0) {
      lm.building = seed.building;
    }
    addSession(lm.sessions, seed.sessionId);

    // 逐个采样点把 AP 并进去：同一 BSSID 的 RSSI 用增量均值（与离线建图一致）
    const psum: number[] = [];
    let pn: number = 0;
    for (const ob of seed.observations) {
      for (const ap of ob.aps) {
        mergeAp(lm.aps, ap.bssid, ap.rssi, seed.sessionId);
      }
      if (ob.pressureHpa !== undefined) {
        psum.push(ob.pressureHpa);
        pn++;
      }
    }
    if (pn > 0) {
      let sum = 0;
      for (const v of psum) {
        sum += v;
      }
      const mean: number = sum / pn;
      lm.pressureHpa = lm.pressureHpa === undefined ? mean : (lm.pressureHpa + mean) / 2;
    }
  }
  for (const lm of out) {
    finalizeLandmark(lm);
  }
  return out;
}

function mergeAp(aps: ApStat[], bssid: string, rssi: number, sessionId: number): void {
  for (const a of aps) {
    if (a.bssid === bssid) {
      a.rssi = (a.rssi * a.n + rssi) / (a.n + 1);
      a.n = a.n + 1;
      addSession(a.sessions, sessionId);
      return;
    }
  }
  const fresh: ApStat = { bssid: bssid, rssi: rssi, n: 1, sessions: [sessionId] };
  aps.push(fresh);
}

/** 收尾：排序、算结构 AP（每个会话都出现的那些） */
function finalizeLandmark(lm: Landmark): void {
  lm.aps.sort((a: ApStat, b: ApStat): number => {
    if (a.rssi !== b.rssi) {
      return b.rssi - a.rssi;
    }
    if (a.bssid === b.bssid) {
      return 0;
    }
    return a.bssid < b.bssid ? -1 : 1;
  });
  lm.sessions.sort((a: number, b: number): number => a - b);
  // ⚠️ 这个局部变量原来叫 `struct` —— 真机编译报 10505001「'struct' is not allowed as a
  // variable declaration name」。**`struct` 是 ArkTS 的保留字**（`@Component struct Foo {}` 就是它），
  // 而 TypeScript 不保留它，所以镜像 tsc 一声不响、离线单测也照跑。改名成 sharedAps。
  const sharedAps: string[] = [];
  if (lm.sessions.length >= 2) {
    for (const a of lm.aps) {
      if (a.sessions.length >= lm.sessions.length) {
        sharedAps.push(a.bssid);
      }
    }
  }
  lm.structural = sharedAps;
}

/** 把 ApStat[] 转回 ApSample[]（打分只需要 bssid/rssi） */
function toSamples(aps: ApStat[]): ApSample[] {
  const out: ApSample[] = [];
  for (const a of aps) {
    out.push({ bssid: a.bssid, rssi: a.rssi });
  }
  return out;
}

// ---------------------------------------------------------------- 匹配

/** 建索引：每个地标截到最强 N 个 */
export interface PlaceIndex {
  key: string;
  label: string;
  floor: string;
  building: string;
  /** 匹配用的指纹（已截到 N 个） */
  sig: ApSample[];
  /** 该地标的气压（楼层反查用） */
  pressureHpa?: number;
  /** 会话数 ≥2 时，只用每个会话都出现过的 AP；否则回落成全部 */
  structuralOnly: boolean;
}

export function makeIndex(landmarks: Landmark[], n: number, structuralOnly: boolean): PlaceIndex[] {
  const out: PlaceIndex[] = [];
  for (const lm of landmarks) {
    let aps: ApStat[] = lm.aps;
    let usedStructural: boolean = false;
    if (structuralOnly && lm.structural.length > 0) {
      const keep: ApStat[] = [];
      for (const a of aps) {
        if (lm.structural.indexOf(a.bssid) >= 0) {
          keep.push(a);
        }
      }
      if (keep.length > 0) {
        aps = keep;
        usedStructural = true;
      }
    }
    if (aps.length === 0) {
      continue;
    }
    const idx: PlaceIndex = {
      key: lm.key, label: lm.label, floor: lm.floor, building: lm.building,
      sig: topN(toSamples(aps), n), pressureHpa: lm.pressureHpa, structuralOnly: usedStructural
    };
    out.push(idx);
  }
  return out;
}

/** 一次打分的原始结果（给「依据」那行用） */
export interface ScoreResult {
  /** 重合系数 |A∩B| / min(|A|,|B|) */
  overlap: number;
  /** 共同 AP 的 RSSI 平均绝对差；没有共同 AP 时是 undefined */
  mae?: number;
  /** 共同 AP 的个数 */
  common: number;
}

/**
 * 打分：**重合系数**为主判据，共同 AP 的 RSSI 平均差做二次判据（破并）。
 * 用 min(|A|,|B|) 当分母而不是 |A∪B|（Jaccard）：扫描到的 AP 数量天然会波动
 * （当前环境可见多少个 AP 不受我们控制），用 min 才不会被「这次扫到得少」惩罚。
 */
export function scoreOne(sample: ApSample[], cand: PlaceIndex): ScoreResult {
  const empty: ScoreResult = { overlap: 0, mae: undefined, common: 0 };
  if (sample.length === 0 || cand.sig.length === 0) {
    return empty;
  }
  let common: number = 0;
  let diffSum: number = 0;
  for (const a of sample) {
    for (const b of cand.sig) {
      if (a.bssid === b.bssid) {
        common++;
        diffSum += Math.abs(a.rssi - b.rssi);
        break;
      }
    }
  }
  if (common === 0) {
    return empty;
  }
  const denom: number = sample.length < cand.sig.length ? sample.length : cand.sig.length;
  const res: ScoreResult = {
    overlap: common / denom,
    mae: diffSum / common,
    common: common
  };
  return res;
}

// ---------------------------------------------------------------- 逐次定位（带时序平滑）

/**
 * 定位器的状态。页面每秒调一次 `stepLocator` 并把这个对象留着 ——
 * 「连续 hold 次才确认切换」靠它，否则位置会逐秒乱跳（离线实测正确匹配时每段能稳定 60 秒）。
 */
export interface LocatorState {
  /** 正在累积的候选 */
  candidateKey: string;
  /** 已经连续几次指向同一个候选 */
  streak: number;
  /** 当前确认的位置（空串 = 还没认出来） */
  confirmedKey: string;
}

export function newLocatorState(): LocatorState {
  const s: LocatorState = { candidateKey: '', streak: 0, confirmedKey: '' };
  return s;
}

/** 一次定位的结论（页面把它整体渲染出来） */
export interface PlaceEstimate {
  /** 确认的位置（空串 = 认不出） */
  key: string;
  label: string;
  floor: string;
  building: string;
  score: number;
  /** 领先第二名的差距 */
  margin: number;
  runnerLabel: string;
  common: number;
  /** 本次扫描里最强候选的名字（即使没达到确认门槛也给出，用于「最接近的是 X」） */
  bestLabel: string;
  /** 气压反查出来的楼层（与地点无关，独立给出） */
  pressureFloor: string;
  pressureBuilding: string;
  pressureHpa?: number;
  /** 是否确认 */
  matched: boolean;
}

/** 单次匹配（不做时序平滑）的结果，给「静止扫描」入口与「最接近的是谁」用 */
export interface PlaceMatch {
  key: string;
  label: string;
  floor: string;
  building: string;
  score: number;
  margin: number;
  runnerLabel: string;
  common: number;
}

/**
 * 拿一份扫描去比一遍所有地点（不分先后、不做平滑）。
 *
 * 打分是**重合系数**为主判据、共同 AP 的 RSSI 平均差做破并（与离线一致）。
 * 用 min(|A|,|B|) 当分母而不是 Jaccard 的 |A∪B|：扫描到的 AP 数量天然会波动
 * （当前环境可见多少个 AP 不受我们控制），用 min 才不会被「这次扫到的少」惩罚。
 */
export function matchOnce(index: PlaceIndex[], sample: ApSample[], n: number): PlaceMatch | undefined {
  const top: ApSample[] = topN(sample, n);
  if (top.length === 0) {
    return undefined;
  }
  let best: PlaceIndex | undefined = undefined;
  let bestScore: number = 0;
  let bestMae: number = 99;
  let bestCommon: number = 0;
  let secondScore: number = 0;
  let secondLabel: string = '';
  for (const c of index) {
    const r: ScoreResult = scoreOne(top, c);
    if (r.overlap <= 0) {
      continue;
    }
    const mae: number = r.mae === undefined ? 99 : r.mae;
    const better: boolean = best === undefined
      || r.overlap > bestScore
      || (r.overlap === bestScore && mae < bestMae);
    if (better) {
      // 原来的第一名退成第二名
      secondScore = best === undefined ? 0 : bestScore;
      secondLabel = best === undefined ? '' : best.label;
      best = c;
      bestScore = r.overlap;
      bestMae = mae;
      bestCommon = r.common;
    } else if (r.overlap > secondScore) {
      secondScore = r.overlap;
      secondLabel = c.label;
    }
  }
  if (best === undefined) {
    return undefined;
  }
  const out: PlaceMatch = {
    key: best.key, label: best.label, floor: best.floor, building: best.building,
    score: bestScore, margin: bestScore - secondScore, runnerLabel: secondLabel, common: bestCommon
  };
  return out;
}

function emptyEstimate(): PlaceEstimate {
  const e: PlaceEstimate = {
    key: '', label: '', floor: '', building: '', score: 0, margin: 0, runnerLabel: '',
    common: 0, bestLabel: '', pressureFloor: '', pressureBuilding: '',
    pressureHpa: undefined, matched: false
  };
  return e;
}

/**
 * 楼层用「**最近气压的那个地标**」给出，**不用「每层一个气压值」的线性模型**：
 * 城大入口在坡地上，实测「电子隧道」的气压比 3/F 还高约 2.7 米（夹在 3/F 与 4/F 之间），
 * 线性模型在这个楼里会错。返回的是「最接近的那个地标所在的楼层」。
 */
export interface PressureFloor {
  floor: string;
  building: string;
  label: string;
  key: string;
  deltaHpa: number;
}

export function floorFromPressure(index: PlaceIndex[], hpa: number | undefined): PressureFloor | undefined {
  if (hpa === undefined) {
    return undefined;
  }
  let best: PlaceIndex | undefined = undefined;
  let bestDelta: number = 0;
  for (const c of index) {
    if (c.pressureHpa === undefined || c.floor.length === 0) {
      continue;
    }
    const d: number = Math.abs(c.pressureHpa - hpa);
    if (best === undefined || d < bestDelta) {
      best = c;
      bestDelta = d;
    }
  }
  if (best === undefined) {
    return undefined;
  }
  const out: PressureFloor = {
    floor: best.floor, building: best.building, label: best.label,
    key: best.key, deltaHpa: bestDelta
  };
  return out;
}

/** 置信度文案（分数本身也要显示，别让「高/中/低」被当成精确结论） */
export function confidenceLabel(score: number): string {
  if (score >= PLACE_CONF_HIGH) {
    return '高';
  }
  if (score >= PLACE_CONF_MID) {
    return '中';
  }
  return '低';
}

/**
 * 走一步定位。`state` 就地更新（页面持有同一个对象）。
 *
 * 确认规则（与离线一致）：重合系数 ≥ minScore **且** 领先第二名 ≥ margin，
 * 连续 hold 次都指向同一个地点，才把「当前位置」切过去；否则只是累积候选，
 * 已有的确认位置保持不变（不会因为一次抖动就变成「认不出」）。
 *
 * 打分本身复用 `matchOnce`（静止扫描入口用的是同一个函数），这里只多了时序平滑。
 */
export function stepLocator(state: LocatorState, index: PlaceIndex[], sample: ApSample[],
  pressureHpa: number | undefined, n: number): PlaceEstimate {
  const est: PlaceEstimate = emptyEstimate();
  const m: PlaceMatch | undefined = matchOnce(index, sample, n);
  if (m !== undefined) {
    est.score = m.score;
    est.margin = m.margin;
    est.runnerLabel = m.runnerLabel;
    est.common = m.common;
    est.bestLabel = m.label;
  }

  const pf: PressureFloor | undefined = floorFromPressure(index, pressureHpa);
  if (pf !== undefined) {
    est.pressureFloor = pf.floor;
    est.pressureBuilding = pf.building;
    est.pressureHpa = pressureHpa;
  }

  const ok: boolean = m !== undefined && m.score >= PLACE_MIN_SCORE && m.margin >= PLACE_MARGIN;
  if (ok && m !== undefined) {
    if (state.candidateKey === m.key) {
      state.streak = state.streak + 1;
    } else {
      state.candidateKey = m.key;
      state.streak = 1;
    }
    if (state.streak >= PLACE_HOLD) {
      state.confirmedKey = m.key;
    }
  } else {
    state.candidateKey = '';
    state.streak = 0;
  }

  for (const c of index) {
    if (c.key === state.confirmedKey) {
      est.key = c.key;
      est.label = c.label;
      est.floor = c.floor;
      est.building = c.building;
      est.matched = true;
      break;
    }
  }
  return est;
}

/**
 * 把若干次连续扫描按 BSSID 合并成一条更强的指纹（均值 RSSI，再按同样规则取前 keep 个）。
 *
 * 为什么要合并：一次扫描是「一瞬间」的样本，同一个 AP 的 RSSI 会抖几个 dB，
 * 而且偶尔会漏掉几个 AP。站定不动连扫几次再平均，就是建模板时用的同一套做法
 * （`mergeLandmarks` 也是逐点求均值），比拿单次扫描当证据稳得多。
 */
export function mergeScans(summaries: string[], keep: number): string {
  const stat: ApStat[] = [];
  for (const s of summaries) {
    for (const ap of parseWifiSummary(s)) {
      mergeAp(stat, ap.bssid, ap.rssi, 1);
    }
  }
  const sorted: ApStat[] = stat;
  sorted.sort((a: ApStat, b: ApStat): number => {
    if (a.rssi !== b.rssi) {
      return b.rssi - a.rssi;
    }
    if (a.bssid === b.bssid) {
      return 0;
    }
    return a.bssid < b.bssid ? -1 : 1;
  });
  const parts: string[] = [];
  const take: number = sorted.length > keep ? keep : sorted.length;
  for (let i = 0; i < take; i++) {
    parts.push(`${sorted[i].bssid}:${sorted[i].rssi}`);
  }
  return parts.join(';');
}

// ---------------------------------------------------------------- 从采样点造地标素材

/**
 * 取地标时间窗内的观测（节点时刻前后各 halfWindowS 秒）。
 * 与离线建图（build_place_map.py 的 `--half-window 6`）**同一口径**，
 * 参数改名但语义没动 —— 换窗口大小就等于换了一套指纹，必须重跑真实数据验证。
 *
 * 输入用 `WifiPoint`（只有三列）而不是 `TrackPoint`：建图要过全部轨迹的全部点，
 * 而 `TrackPoint` 每行还带着约 2 KB 的 IMU 序列（见 Entities.WifiPoint 的说明）。
 */
export function windowObservations(points: WifiPoint[], atMs: number, halfWindowS: number): PlaceObservation[] {
  const out: PlaceObservation[] = [];
  const lo: number = atMs - Math.round(halfWindowS * 1000);
  const hi: number = atMs + Math.round(halfWindowS * 1000);
  for (const p of points) {
    if (p.timeMs < lo || p.timeMs > hi) {
      continue;
    }
    const aps: ApSample[] = parseWifiSummary(p.wifiTop);
    if (aps.length === 0) {
      continue;
    }
    const ob: PlaceObservation = { aps: aps, pressureHpa: p.pressureHpa };
    out.push(ob);
  }
  return out;
}

// ---------------------------------------------------------------- 跨会话成绩（就是那个生死问题的答案）

/**
 * 某个绑定地点的跨会话成绩。
 *
 * **这是整个功能最该看的一个数**：绑定同一地点（`boundKey`）的多次静止扫描里，
 * 有几次真的认回了它。全部来自同一次走动的结果不说明问题 ——
 * 「隔 2 小时 / 隔天还能认出来吗」才是决定这套指纹方案能不能用的前提，
 * 而回答它只能靠这个统计（`hit < total` 的那些，点开列表能看到当时匹配成了哪里）。
 */
export interface SessionScore {
  key: string;
  label: string;
  /** 绑定到该地点的扫描次数 */
  total: number;
  /** 其中真的认出它的次数 */
  hit: number;
  /** 最近一次扫描的时刻 */
  lastMs: number;
}

export function crossSessionScores(scans: PlaceScan[]): SessionScore[] {
  const out: SessionScore[] = [];
  for (const s of scans) {
    if (s.boundKey.length === 0) {
      continue;
    }
    let row: SessionScore | undefined = undefined;
    for (const r of out) {
      if (r.key === s.boundKey) {
        row = r;
        break;
      }
    }
    if (row === undefined) {
      const fresh: SessionScore = {
        key: s.boundKey, label: s.boundLabel, total: 0, hit: 0, lastMs: 0
      };
      out.push(fresh);
      row = fresh;
    }
    row.total = row.total + 1;
    if (s.matchedKey === s.boundKey) {
      row.hit = row.hit + 1;
    }
    if (s.atMs > row.lastMs) {
      row.lastMs = s.atMs;
    }
  }
  return out;
}
