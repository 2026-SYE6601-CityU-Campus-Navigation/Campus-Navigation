import { TrackPoint, TrackTag } from '../data/Entities';
import { Theme } from './Theme';

/**
 * 轨迹三维可视化：把 经纬度 + 高度 投影成可旋转的立体折线。
 *
 * 为什么自己算而不是用 3D 引擎：仅依赖 Canvas 2D API，无第三方库、不增包体、
 * 全 API 版本可用；本项目的数据量（一条轨迹几百个点）远超所需性能。
 *
 * 数学约定（已用 Node 复现验证）：
 *  - 本地米制坐标：x=东、y=北、z=上，用等距圆柱近似换算经纬度（室内尺度足够）
 *  - 高度来源优先 GPS 海拔；整条轨迹都没有海拔时，用气压按国际气压高度公式
 *    换算出「相对首个有效气压的高度」——室内 GPS 常常没有海拔，这条退路让
 *    垂直校园的高度信息在纯室内采集时也能用
 *  - **竖向压缩**（用户 2026-09-28 要求「固定住 Z 轴在较小范围，x/y 自由」）：
 *    高度显示值不超过平面尺度的 VERTICAL_BUDGET 倍，超出即按比例压；x/y 始终真实比例。
 *    samples 里的 z 一律是**压缩后**的显示值，而 minZ/maxZ 保留**真实**高度，
 *    供「高差」读数与高度层标注使用——图可以压扁，数字不能骗人。
 *  - 正交投影：偏航(yaw)绕竖直轴旋转，俯仰(pitch) 4°≈侧视、90°=正俯视
 *  - depth 为「位置沿视线方向的投影」，越大越远，用于远→近绘制顺序
 */
export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

/** 视图角度与缩放 */
export interface View3D {
  yawDeg: number;
  pitchDeg: number;
  /** 相对自适应缩放的倍率（双指捏合调整） */
  zoom: number;
}

/** 要标注的节点（节点名 + 位置） */
export interface NodePin {
  x: number;
  y: number;
  z: number;
  label: string;
  /** true = 该节点没有定位，位置是按时间就近推算的（室内采集常见），界面要如实说明 */
  estimated?: boolean;
}

/** 转换结果：采样点 + 高度来源，交给页面画标题与读数 */
export interface TrackPlan {
  /** 'gps' 用 GPS 海拔 / 'pressure' 用气压估算 / 'none' 无高度信息 */
  heightSource: string;
  /** 有经纬度的采样点（米制、已去中心；z 为**压缩后**的显示高度） */
  samples: Vec3[];
  /** 与 samples 一一对应的采样时间，用于把节点按时间对齐到轨迹高度上 */
  sampleTimes: number[];
  /**
   * 与 samples 一一对应的定位精度（米）。0 = 该点没记精度（老数据）。
   *
   * 2026-09-30（第二十九轮）新增：用来在图上**分级显示可信度**。
   * 依据是独树阳光里那两条轨迹：室外自报 5~6 m 的两条走同一条路能重合得很紧，
   * 而室内自报 13~16 m 的两条**位置相差 20~30 m** —— 也就是说「±15 m」是低估的，
   * 这些点不该和实测点长得一模一样。
   */
  accuracies: number[];
  /** 没有定位的采样点数（室内正常，提示用） */
  noGeoCount: number;
  /** 真实最低/最高相对高度（米，未压缩），用于高差读数与高度层标注 */
  minZ: number;
  maxZ: number;
  /** 竖向压缩系数（1 = 未压缩）。显示高度 = 真实高度 × zScale */
  zScale: number;
  /** 是否有可用原点（首点定位）；false 表示这条轨迹完全没有定位 */
  hasOrigin: boolean;
  lat0: number;
  lng0: number;
  /** GPS 高度基准（heightSource='gps' 时有效） */
  altBase: number;
  /** 气压基准（heightSource='pressure' 时有效） */
  pBase: number;
}

export interface Fit {
  s: number;
  cx: number;
  cy: number;
}

const M_PER_LAT = 110540;
const M_PER_LNG_PER_DEG = 111320;

/**
 * 竖向预算：显示高度最多占平面尺度的这个比例。
 * 轨迹横跨 50 m 而高差 3 m 时（室内常见）不压缩，保持真实比例；
 * 高差 40 m 而平面只有 20 m 时压到 0.3×，平面形状不会被高度撑成一竖条。
 */
const VERTICAL_BUDGET = 0.3;

/**
 * 定位精度门限（米）：accuracy 比它差的采样点**当作没有定位**，不画进图里。
 *
 * 依据（2026-09-29 实测 AC1 那条 341 点的轨迹）：室内拿不到 GPS 时，系统会给一个
 * **网络定位**的结果（accuracy 200 m 上下），经纬度照样有值 —— 341 点里 209 点属于这种，
 * 相邻点最大跳变 29 m，而且**所有 >15 m 的跳变点 accuracy 都 >50 m**。
 * 同一批数据里真正的 GPS 定位精度是 5~11 m，所以 50 m 这条线分得很干净。
 */
const MAX_ACCURACY_M: number = 50;

/**
 * 「定位可信」的门限（米）。精度差于这个值的点**仍然画**，但画淡一些，并在界面上说明。
 *
 * 依据（2026-09-30 独树阳光里两条同路线、方向相反的轨迹）：室外段自报 5~6 m，
 * 红色与蓝色两条走出来的形状贴得很紧；而室内两段自报 13~16 m，两次走同一条走廊
 * **位置相差 20~30 m** —— 自报精度低估了室内多径误差，这些点不该和实测点长得一样。
 * 8 m 正好把这两档分开（实测里 5~6 与 13~16 之间是空的）。
 */
const WEAK_ACCURACY_M: number = 8;

/**
 * 相邻采样点间隔超过这个时长就不连线段：中间那段没有可用定位，
 * 连起来是「假装知道路怎么走的」。断开更诚实 —— 用户看到的应该是一个缺口，
 * 而不是一条穿过建筑内部的直线。
 */
const GAP_BREAK_MS: number = 30000;

/** 相邻两个采样点之间该不该连线段：间隔太久说明中间没有可用定位，连起来是「假装知道」 */
export function sameSegment(prevTimeMs: number, timeMs: number): boolean {
  return timeMs - prevTimeMs <= GAP_BREAK_MS;
}

/**
 * 一条定位（经纬度 + 精度）能不能当**实测坐标**用。
 * 节点与采样点必须走同一套门限 —— 两边口径不一致的话，图上会出现「采样点被排除了、
 * 旁边的节点却还按那个假坐标摆着」的矛盾。
 */
export function usableFixOf(lat: number | undefined, lng: number | undefined,
  accuracy: number | undefined): boolean {
  if (lat === undefined || lng === undefined) {
    return false;
  }
  return accuracy === undefined || accuracy <= MAX_ACCURACY_M;
}

/** 这个点该不该当作「有定位」：有经纬度，且精度（没记精度的老数据不算差）在门限内 */
export function usableFix(p: TrackPoint): boolean {
  return usableFixOf(p.latitude, p.longitude, p.accuracy);
}

/**
 * 这个点的定位**精度是否偏弱**（仍然画，但要画淡 + 界面说明）。
 * 没记精度的老数据返回 false（口径与 usableFix 一致：没记精度不算差）。
 */
export function weakFix(accuracy: number | undefined): boolean {
  return accuracy !== undefined && accuracy > WEAK_ACCURACY_M;
}

/** 给界面用的门限值（图例里要写数字，别在两处各写一遍） */
export function weakAccuracyLimit(): number {
  return WEAK_ACCURACY_M;
}

/** 国际气压高度公式：由气压 p 相对基准 p0 估算高度差（米） */
export function pressureToHeight(p: number, p0: number): number {
  if (p <= 0 || p0 <= 0) {
    return 0;
  }
  return 44330 * (1 - Math.pow(p / p0, 0.1903));
}

/** 高度基准的判定结果：用哪一路、以及各自的基准值（缺席时为 0） */
export interface HeightPick {
  /** 'gps' 用 GPS 海拔 / 'pressure' 用气压估算 / 'none' 两者都没有 */
  source: string;
  altBase: number;
  pBase: number;
}

/** 气象学的近似换算：近地面每 1 hPa ≈ 8.3 m（只用做两个来源之间的量级比较） */
const M_PER_HPA: number = 8.3;

/**
 * 「海拔明显比实际高度夸张」的判据：海拔极差 > 气压极差（折成米）× 这个倍数 + 裕量（米）。
 * 取 1.8 的依据：独树阳光里那条轨迹实测 49.9 m / 17.9 m = **2.8 倍**，
 * 留出余量后取 1.8，既能判出来、又不至于把「海拔比气压稍粗」的正常轨迹也换掉。
 */
const ALT_RANGE_RATIO: number = 1.8;
const ALT_RANGE_MARGIN_M: number = 2;

/**
 * 选高度来源（纯函数，可离线单测）。
 *
 * 规则演进（连着踩了两次，所以整个判定抽出来单测）：
 *  ① 第一版「只要有一个点有海拔就整条用海拔」→ 其余点全落回基准值，高度成了「平线 + 尖刺」。
 *  ② 第二版（第二十二轮）改成看**覆盖率**：海拔覆盖 ≥ 一半才用海拔，否则用气压。
 *  ③ 第三版（2026-09-30，第二十九轮）**再加一道「海拔有没有虚张声势」的判断** ——
 *     起因是独树阳光里那条轨迹：海拔覆盖 68%（过了 50% 的门限）于是选了海拔，
 *     可那条路实际只下了一层楼（约 14 m），**海拔却给出 49.9 m 的极差**，
 *     同一段气压只给出 17.9 m。3D 图是按 minZ~maxZ 来铺高度的，
 *     这 50 m 一进来整张图就被撑成一坨、楼层图层也被拉开，完全不能看。
 *
 * 判据为什么用**极差**而不是「相邻点变化的抖动」：先写的是抖动（相邻差的中位数），
 * 结果在真实数据上**没触发** —— 这条轨迹的海拔是「多数时候安静、时不时来一下 17 m 的大跳」，
 * 中位数只有 0.086 m（17 m 的跳变被淹在中位数里），而极差正是 49.9 m 的元凶，
 * 也正是 3D 图真正会用的那个量。**用错的统计量 = 规则看着合理但实际不生效，只有拿真数据跑过才发现。**
 *
 * 反过来也要防：气压如果是死的（极差 0），不能因为「海拔看起来更大」就改判气压 ——
 * 那样会得到一条完全平的高度线。所以只有**气压确实在动**时才考虑改判。
 */
export function pickHeightSource(pts: TrackPoint[]): HeightPick {
  const pick: HeightPick = { source: 'none', altBase: 0, pBase: 0 };
  let altBase: number | undefined = undefined;
  let altOk = 0;
  let altMin = 0;
  let altMax = 0;
  for (const p of pts) {
    const a: number | undefined = p.altitude;
    // 0 按「缺失」处理：真机把「这次没有海拔」写成了 0，不是真的在海平面
    if (a !== undefined && a > 0) {
      altOk++;
      if (altBase === undefined) {
        altBase = a;
        altMin = a;
        altMax = a;
      }
      if (a < altMin) {
        altMin = a;
      }
      if (a > altMax) {
        altMax = a;
      }
    }
  }
  let p0: number | undefined = undefined;
  let pressOk = 0;
  let pressMin = 0;
  let pressMax = 0;
  for (const p of pts) {
    const v: number | undefined = p.pressureHpa;
    if (v !== undefined && v > 0) {
      pressOk++;
      if (p0 === undefined) {
        p0 = v;
        pressMin = v;
        pressMax = v;
      }
      if (v < pressMin) {
        pressMin = v;
      }
      if (v > pressMax) {
        pressMax = v;
      }
    }
  }
  const hasAlt: boolean = altBase !== undefined && altOk * 2 >= pts.length;
  const hasPress: boolean = p0 !== undefined && pressOk > 0;
  let source = 'none';
  if (hasAlt) {
    source = 'gps';
    if (hasPress) {
      const altRange: number = altMax - altMin;
      const pressRangeM: number = (pressMax - pressMin) * M_PER_HPA;
      if (pressRangeM > 0 && altRange > pressRangeM * ALT_RANGE_RATIO + ALT_RANGE_MARGIN_M) {
        source = 'pressure';
      }
    }
  } else if (hasPress) {
    source = 'pressure';
  } else if (altBase !== undefined) {
    // 海拔覆盖不到一半、又没有气压：聊胜于无，还是用海拔
    source = 'gps';
  }
  pick.source = source;
  pick.altBase = altBase === undefined ? 0 : altBase;
  pick.pBase = p0 === undefined ? 0 : p0;
  return pick;
}

export function buildPlan(pts: TrackPoint[]): TrackPlan {
  // 2026-09-29 用真实数据（AC1 那条 341 点的轨迹）量出来的两条：
  //  ① 室内根本没有 GPS：341 点里 209 点（61%）是**网络定位**，accuracy 中位 210 m，
  //     相邻点最大跳变 29 m —— 全是假坐标。照原样画进 3D 图就是一串飞出去的长线
  //     （用户说的「脱离轨迹的线」很可能就是它）。所以这里按精度筛：**精度太差的当没有定位**，
  //     与「没拿到经纬度」同等对待，页面上会如实告诉用户有多少点被排除。
  //  ② GPS 海拔不可信：那条轨迹里 312/341 点的 altitude 是 0（＝没有海拔），
  //     剩下 29 点却是 45~52 m；而同一段路气压只给出 10 m 高差。两者差一个量级，
  //     说明那个 0 是「没有数据」而不是「海平面」。所以 **altitude <= 0 一律当缺失**，
  //     否则高度会变成「室内 0 m、门口 48 m」的假悬崖，而且会盖掉本来正确的气压高度。
  const geo: TrackPoint[] = [];
  let noGeo = 0;
  for (const p of pts) {
    if (usableFix(p)) {
      geo.push(p);
    } else {
      noGeo++;
    }
  }
  if (geo.length === 0) {
    const empty: Vec3[] = [];
    const times: number[] = [];
    const noAcc: number[] = [];
    const none: TrackPlan = {
      heightSource: 'none', samples: empty, sampleTimes: times, accuracies: noAcc, noGeoCount: noGeo,
      minZ: 0, maxZ: 0, zScale: 1, hasOrigin: false, lat0: 0, lng0: 0, altBase: 0, pBase: 0
    };
    return none;
  }

  const lat0 = geo[0].latitude as number;
  const lng0 = geo[0].longitude as number;
  const mLng = M_PER_LNG_PER_DEG * Math.cos(lat0 * Math.PI / 180);

  // 高度来源判定（海拔 / 气压 / 都没有）**整个交给了 pickHeightSource 纯函数** ——
  // 判定规则踩过两次坑（只看有无海拔 → 平线加尖刺；只看覆盖率 → 被 50 m 的海拔噪声撑爆 3D 图），
  // 抽成纯函数才能在离线测试里把这两种情形都钉住。规则与实测证据写在 pickHeightSource 的注释里。
  const hp: HeightPick = pickHeightSource(geo);
  const source: string = hp.source;
  const altBase: number = hp.altBase;
  const p0: number = hp.pBase;

  const samples: Vec3[] = [];
  const sampleTimes: number[] = [];
  const accuracies: number[] = [];
  let minZ = 0;
  let maxZ = 0;
  let minX = 0;
  let maxX = 0;
  let minY = 0;
  let maxY = 0;
  let first = true;
  for (const p of geo) {
    const lat = p.latitude as number;
    const lng = p.longitude as number;
    let z = 0;
    if (source === 'gps') {
      // 海拔为 0/缺失的点按基准高度算，不要让它变成 -48 m 的假谷底
      const a: number | undefined = p.altitude;
      z = ((a !== undefined && a > 0) ? a : altBase) - altBase;
    } else if (source === 'pressure') {
      if (p.pressureHpa !== undefined) {
        z = pressureToHeight(p.pressureHpa, p0);
      }
    }
    const x = (lng - lng0) * mLng;
    const y = (lat - lat0) * M_PER_LAT;
    const v: Vec3 = { x: x, y: y, z: z };
    samples.push(v);
    sampleTimes.push(p.timeMs);
    // 0 = 没记精度（老数据），与 samples 一一对应
    accuracies.push(p.accuracy === undefined ? 0 : p.accuracy);
    if (first) {
      minZ = z;
      maxZ = z;
      minX = x;
      maxX = x;
      minY = y;
      maxY = y;
      first = false;
    } else {
      if (z < minZ) {
        minZ = z;
      }
      if (z > maxZ) {
        maxZ = z;
      }
      if (x < minX) {
        minX = x;
      }
      if (x > maxX) {
        maxX = x;
      }
      if (y < minY) {
        minY = y;
      }
      if (y > maxY) {
        maxY = y;
      }
    }
  }

  // 竖向压缩：只在高度会「喧宾夺主」时生效（见 VERTICAL_BUDGET 说明）。
  // 平面尺度取 x/y 跨度里较大的那个；平面几乎为零（原地不动）时不压缩，靠自适应缩放收进画布。
  const planar = Math.max(maxX - minX, maxY - minY);
  const zRange = maxZ - minZ;
  let zScale = 1;
  if (planar > 1e-6 && zRange > 1e-6) {
    const allowed = VERTICAL_BUDGET * planar;
    if (zRange > allowed) {
      zScale = allowed / zRange;
    }
  }
  for (const v of samples) {
    v.z = v.z * zScale;
  }

  const plan: TrackPlan = {
    heightSource: source,
    samples: samples,
    sampleTimes: sampleTimes,
    accuracies: accuracies,
    noGeoCount: noGeo,
    minZ: minZ,
    maxZ: maxZ,
    zScale: zScale,
    hasOrigin: true,
    lat0: lat0,
    lng0: lng0,
    altBase: altBase,
    pBase: p0
  };
  return plan;
}

/** 距给定时间最近的采样点下标（按时间就近，用于节点对齐轨迹） */
export function nearestSampleIndex(plan: TrackPlan, timeMs: number): number {
  const n: number = plan.samples.length;
  if (n === 0) {
    return -1;
  }
  let best = 0;
  let bestDiff = Math.abs(plan.sampleTimes[0] - timeMs);
  for (let i = 1; i < n; i++) {
    const d = Math.abs(plan.sampleTimes[i] - timeMs);
    if (d < bestDiff) {
      bestDiff = d;
      best = i;
    }
  }
  return best;
}

/** 节点的 z：按时间就近取采样点的高度，保证节点落在轨迹的高度曲线上 */
export function zForTime(plan: TrackPlan, timeMs: number): number {
  const i: number = nearestSampleIndex(plan, timeMs);
  return i < 0 ? 0 : plan.samples[i].z;
}

/**
 * 节点（标记）→ 三维标注点：与轨迹共用同一个原点与高度基准。
 *
 * 两种定位方式：
 *  - 节点自带**可用**经纬度 → 直接用；高度优先用节点自己的海拔（有的话），否则按时间对齐到轨迹高度。
 *  - 节点没有经纬度、或精度太差（室内那种 200 m 的网络定位）→ **按时间就近取采样点的平面位置**：
 *    节点是在那一刻按下的，手机当时就在轨迹的那个位置上。这样室内节点也能画出来并带名称，
 *    但位置是推算的，NodePin.estimated 标 true，界面要如实说明，不能当成实测坐标。
 *
 * ⚠️ 精度筛这一条是 2026-09-29 补的（第二十五轮）：节点的 accuracy 以前根本没入库，所以
 * 4 个节点里就有 2 个带着 200 m 的网络定位坐标、却和实测坐标长得一模一样地摆在图上。
 * 而这些节点正是**航位推算的锚点**，锚点不干净，后面补出来的室内段就全是错的。
 *
 * 整条轨迹完全没有定位（plan.hasOrigin=false）时返回 undefined，无从摆放。
 */
export function pinFrom(lat: number | undefined, lng: number | undefined,
  altitude: number | undefined, accuracy: number | undefined,
  timeMs: number, label: string, plan: TrackPlan): NodePin | undefined {
  if (!plan.hasOrigin || plan.samples.length === 0) {
    return undefined;
  }
  if (!usableFixOf(lat, lng, accuracy)) {
    const i: number = nearestSampleIndex(plan, timeMs);
    if (i < 0) {
      return undefined;
    }
    const s: Vec3 = plan.samples[i];
    const est: NodePin = { x: s.x, y: s.y, z: s.z, label: label, estimated: true };
    return est;
  }
  const lat0: number = lat as number;
  const lng0: number = lng as number;
  const mLng = M_PER_LNG_PER_DEG * Math.cos(plan.lat0 * Math.PI / 180);
  let z: number;
  if (plan.heightSource === 'gps' && altitude !== undefined) {
    z = (altitude - plan.altBase) * plan.zScale;
  } else {
    z = zForTime(plan, timeMs);
  }
  const pin: NodePin = {
    x: (lng0 - plan.lng0) * mLng,
    y: (lat0 - plan.lat0) * M_PER_LAT,
    z: z,
    label: label,
    estimated: false
  };
  return pin;
}

/** 正交投影：返回屏幕相对坐标（未加中心偏移与缩放） */
export function projectPoint(p: Vec3, yaw: number, pitch: number): Vec3 {
  const x1 = p.x * Math.cos(yaw) - p.y * Math.sin(yaw);
  const y1 = p.x * Math.sin(yaw) + p.y * Math.cos(yaw);
  const sy = -(y1 * Math.sin(pitch) + p.z * Math.cos(pitch));
  const depth = -(y1 * Math.cos(pitch) - p.z * Math.sin(pitch));
  return { x: x1, y: sy, z: depth };
}

/** 自适应缩放：先以 s=1 投影求包围盒，再缩放到留白内并居中（任意视角都不出画布） */
export function fitTransform(samples: Vec3[], pins: NodePin[], yaw: number, pitch: number,
  w: number, h: number, pad: number, zoom: number): Fit {
  let x0 = 0;
  let x1 = 0;
  let y0 = 0;
  let y1 = 0;
  let first = true;
  const all: Vec3[] = [];
  for (const p of samples) {
    all.push(p);
  }
  for (const p of pins) {
    all.push({ x: p.x, y: p.y, z: p.z });
  }
  for (const p of all) {
    const q = projectPoint(p, yaw, pitch);
    if (first) {
      x0 = q.x; x1 = q.x; y0 = q.y; y1 = q.y;
      first = false;
    } else {
      if (q.x < x0) {
        x0 = q.x;
      }
      if (q.x > x1) {
        x1 = q.x;
      }
      if (q.y < y0) {
        y0 = q.y;
      }
      if (q.y > y1) {
        y1 = q.y;
      }
    }
  }
  if (first) {
    const zero: Fit = { s: 1, cx: w / 2, cy: h / 2 };
    return zero;
  }
  // 下限避免除零（单点/全重合时）
  const bw = Math.max(x1 - x0, 0.001);
  const bh = Math.max(y1 - y0, 0.001);
  const fit = Math.min((w - pad * 2) / bw, (h - pad * 2) / bh);
  const s = fit * (zoom > 0 ? zoom : 1);
  const out: Fit = {
    s: s,
    cx: w / 2 - ((x0 + x1) / 2) * s,
    cy: h / 2 - ((y0 + y1) / 2) * s
  };
  return out;
}

/** 楼层次（高度层）等距切分：层数控制在 3–8 之间，避免上百层糊成一片 */
export function levelStep(minZ: number, maxZ: number): number {
  const range = Math.abs(maxZ - minZ);
  if (range < 0.5) {
    return 0;
  }
  let step = 2;
  while (range / step > 7) {
    step += 2;
  }
  return step;
}

export function heightSourceLabel(source: string): string {
  if (source === 'gps') {
    return '高度来源：GPS 海拔';
  }
  if (source === 'pressure') {
    return '高度来源：气压估算（高空差更准）';
  }
  return '无高度数据：这段轨迹没有海拔也没有气压';
}

/**
 * 一个楼层图层（用户 2026-09-29 要求：层数跟着**实际记录到的楼层**走，不再按米数切）。
 * z 是**显示高度**（与 samples[].z、NodePin.z 同一口径，已含竖向压缩），画时不要再乘 zScale。
 */
export interface FloorLevel {
  /** 图层标签：手填的楼层名（3/F、LG…），或退路里的「+12m」 */
  name: string;
  z: number;
  /** 这一层有几个节点（退路按米数分层时为 0） */
  count: number;
}

/** 楼层名归一化键：忽略空格/大小写，并去掉「/F」或结尾的「F」，好让「3」「3/F」「3F」算作同一层 */
export function floorKey(name: string): string {
  let s: string = name.replace(/\s+/g, '').toLowerCase();
  if (s.endsWith('/f')) {
    s = s.substring(0, s.length - 2);
  }
  // 「3F」这种不写斜杠的写法也归到一起；只在剩不止一个字符时才砍，
  // 免得把单字符楼名（如「F」）砍成空串
  if (s.length > 1 && s.endsWith('f')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/**
 * 按实际记录到的楼层汇总图层。纯函数，便于离线验证。
 *  - 只统计手填了「楼层」的节点；归一化后同名的合并，高度取这些节点显示高度的**平均值**
 *    （同一个楼层名在几个点上按下的高度略有出入，取平均比取第一个稳）
 *  - 按高度升序排（低楼层在前）
 *  - 一个可用楼层都没有、或这条轨迹根本没有可用采样点时，返回空数组 → 调用方退回按米数分层
 *  - 上限 12 层：正常校园最多 LG+G+1..8，真有更杂的手填值也不至于把图糊满
 */
export function buildFloors(tags: TrackTag[], plan: TrackPlan): FloorLevel[] {
  if (plan.samples.length === 0 || plan.heightSource === 'none') {
    return [];
  }
  const keys: string[] = [];
  const names: string[] = [];
  const sums: number[] = [];
  const counts: number[] = [];
  for (const t of tags) {
    const raw: string = t.floor.trim();
    if (raw.length === 0) {
      continue;
    }
    const k: string = floorKey(raw);
    if (k.length === 0) {
      continue;
    }
    let idx: number = keys.indexOf(k);
    if (idx < 0) {
      keys.push(k);
      names.push(raw);
      sums.push(0);
      counts.push(0);
      idx = keys.length - 1;
    }
    sums[idx] += zForTime(plan, t.timeMs);
    counts[idx] += 1;
  }
  const out: FloorLevel[] = [];
  for (let i = 0; i < names.length; i++) {
    out.push({ name: names[i], z: sums[i] / counts[i], count: counts[i] });
  }
  out.sort((a: FloorLevel, b: FloorLevel) => a.z - b.z);
  return out.length > 12 ? out.slice(0, 12) : out;
}

/**
 * 一个楼层都没填时的退路：按真实高度每 levelStep 切一层，标签写「+12m」。
 * 这是改版前的行为 —— 保留它，是为了「没填楼层也还有参照」，
 * 而且标签也走 FloorLevel，绘制路径只有一条。
 */
export function fallbackLevels(plan: TrackPlan): FloorLevel[] {
  const out: FloorLevel[] = [];
  const step: number = levelStep(plan.minZ, plan.maxZ);
  if (step <= 0) {
    return out;
  }
  const zs: number = plan.zScale > 0 ? plan.zScale : 1;
  const z0: number = Math.floor(plan.minZ / step) * step;
  const z1: number = Math.ceil(plan.maxZ / step) * step;
  for (let z = z0; z <= z1 + 0.001; z += step) {
    out.push({ name: `${z >= 0 ? '+' : ''}${z.toFixed(0)}m`, z: z * zs, count: 0 });
  }
  return out;
}

/**
 * 把 'rgba(r,g,b,a)' 的透明度乘一个系数，用来做「越远越淡」。
 *
 * 刻意**不用 Canvas 的 globalAlpha**：本工程从没用过那个属性，没验证过的 API 不去赌
 * （每次真机编译都要用户在 DevEco 里跑一轮，代价太高）。这样色值来源仍然只有 Theme 一处，
 * 淡出纯粹是算术。非 rgba 形式（如 '#RRGGBB'）或解析不出透明度时原样返回。
 */
export function fadeRgba(rgba: string, k: number): string {
  const i: number = rgba.lastIndexOf(',');
  if (i < 0) {
    return rgba;
  }
  const head: string = rgba.substring(0, i + 1);
  const tail: string = rgba.substring(i + 1).replace(')', '').trim();
  const a: number = parseFloat(tail);
  if (isNaN(a)) {
    return rgba;
  }
  let scaled: number = a * k;
  if (scaled < 0) {
    scaled = 0;
  }
  if (scaled > 1) {
    scaled = 1;
  }
  return `${head}${scaled.toFixed(3)})`;
}

/**
 * 文本宽度估算（vp）。**刻意不用 ctx.measureText()**。
 *
 * 2026-09-29 踩到的真 bug：ArkUI 画布的坐标与线宽**默认单位是 vp**，但
 *  ① `ctx.font` 里的 `px` 是**设备物理像素**（官方文档：font-size「单位支持 px、vp」，
 *     并举例对比 `30px` 与 `30vp`；px/vp 的差别就是屏幕密度）；
 *  ② `measureText()` 返回的宽度「不同设备上获取的宽度值可能不同」，同样是**物理像素**。
 * 原来字号写的 `'700 11px'`、药丸宽度用 `measureText().width + 16` 当 vp 用 ——
 * 于是 3 倍密度的机器上：文字只有约 3.7vp（几乎看不见），药丸又被算窄，就成了
 * 「一个空白的小红条」（用户 2026-09-29 说的「脱离轨迹的红色短条」和「文字标签没正常显示」）。
 *
 * 所以宽度改成按字宽估算：**中日韩/全角字符算 1 个字宽，其余算 0.55**，再乘字号（vp）。
 * 纯函数、与设备无关，也就不会有「量出来的单位跟画的单位不是一个」这种问题。
 * 字宽取得略宽松一点没关系（药丸宽一点不难看），取窄了文字就会溢出边框。
 */
export function textWidthVp(text: string, fontVp: number): number {
  let em = 0;
  for (let i = 0; i < text.length; i++) {
    // 0x1100 起是谚文/中日韩/全角标点的范围，这些字符基本是正方形的
    em += text.charCodeAt(i) >= 0x1100 ? 1 : 0.55;
  }
  return em * fontVp;
}

/** 画布边缘上的一个点（罗盘用） */
export interface EdgePoint {
  x: number;
  y: number;
}

/**
 * 把一个屏幕方向 (dx, dy)（不必归一化）投到画布矩形的边缘上，四边各内缩 inset。
 * 罗盘「东南西北」就是靠它贴到四边的：取方向与矩形边界的交点即可，
 * 所以任意偏航角下四个字都贴在边上、不会跑出画布或挤成一堆。
 * 方向退化成 (0,0) 或画布过小导致无交点时返回 undefined。
 */
export function edgePointOnRect(dx: number, dy: number, w: number, h: number,
  inset: number): EdgePoint | undefined {
  if (dx === 0 && dy === 0) {
    return undefined;
  }
  const cx = w / 2;
  const cy = h / 2;
  let t = Number.MAX_VALUE;
  if (dx > 0) {
    t = Math.min(t, (cx - inset) / dx);
  } else if (dx < 0) {
    t = Math.min(t, (inset - cx) / dx);
  }
  if (dy > 0) {
    t = Math.min(t, (cy - inset) / dy);
  } else if (dy < 0) {
    t = Math.min(t, (inset - cy) / dy);
  }
  if (t === Number.MAX_VALUE || t <= 0) {
    return undefined;
  }
  return { x: cx + dx * t, y: cy + dy * t };
}

/**
 * 取标签开头的序号（「3 教室 2/F · LT-8」→「3」）。
 * 图太挤、完整标签摆不下时退一步只摆这个序号：序号与节点列表里的红色序号徽章一一对应，
 * 图上看不出细节时照着序号去下面的列表里找即可。开头没有数字就退回第一个字符。
 */
export function shortLabelOf(label: string): string {
  let s = '';
  for (let i = 0; i < label.length; i++) {
    const c: number = label.charCodeAt(i);
    if (c >= 48 && c <= 57) {
      s += label.charAt(i);
    } else {
      break;
    }
  }
  return s.length > 0 ? s : label.substring(0, 1);
}

/** 屏幕上的一个矩形（标签摆放 / 占位用） */
export interface LabelBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

/**
 * 标签候选位置（相对圆点的偏移，按优先级排）。
 * 先右上、再左上、右下、左下、右侧、左侧 —— 越靠前的越「像标签该在的地方」。
 */
function labelOffsets(tw: number, th: number): number[][] {
  return [
    [13, -th - 7],
    [-13 - tw, -th - 7],
    [13, 7],
    [-13 - tw, 7],
    [13, -th / 2],
    [-13 - tw, -th / 2]
  ];
}

/**
 * 给一个节点标签挑位置：依次试候选位，返回第一个「在画布内、且不与已占位置重叠」的矩形。
 * 全都占满就返回 undefined —— 调用方就只画圆点、不画标签（节点列表里仍然有它）。
 *
 * 为什么要做这个（2026-09-29）：离线把图渲染出来才看见，节点一多，标签会互相盖住、
 * 糊成一堆看不出哪个是哪个，用户的感受就是「标签没正常显示」。楼层标签一直有这个「打架就不画」
 * 的处理，节点标签当时漏了。纯函数，便于离线验证。
 */
export function placeLabel(qx: number, qy: number, tw: number, th: number, w: number, h: number,
  taken: LabelBox[]): LabelBox | undefined {
  const offs: number[][] = labelOffsets(tw, th);
  for (const off of offs) {
    const x: number = qx + off[0];
    const y: number = qy + off[1];
    if (x < 2 || y < 2 || x + tw > w - 2 || y + th > h - 2) {
      continue;
    }
    let hit = false;
    for (const t of taken) {
      if (x < t.x + t.w && x + tw > t.x && y < t.y + t.h && y + th > t.y) {
        hit = true;
        break;
      }
    }
    if (!hit) {
      return { x: x, y: y, w: tw, h: th };
    }
  }
  return undefined;
}

/**
 * 画布字号：**用 vp2px() 换成 px 再写进 font 串**。
 *
 * 为什么不用 `'700 11vp sans-serif'`（2026-09-29 真机实测）：官方文档说 font-size
 * 「单位支持 px、vp」，但**在用户的机器上 vp 这一路没生效** —— 代码里写得好好的，
 * 编译产物里也确实是 `'700 11vp sans-serif'`，真机上节点名字还是显示不出来。
 * 与其继续猜 vp 为什么不被采纳，不如退回到文档里最基础、默认值就在用的 **px**
 * （默认字体就是 `'normal normal 14px sans-serif'`），用 `vp2px()` 把设计尺寸（vp）
 * 换算成物理像素写进去 —— 这样不管 vp 支不支持，字号都是按屏幕密度算准的。
 *
 * ⚠️ 以后在画布上写字一律走这个函数，别在别处手写 font 串：检查器第 8 项会拦住
 * 「字号里直接写数字 + px」的写法（那种写法在高密度屏上会小到看不见）。
 */
export function canvasFont(sizeVp: number, bold: boolean): string {
  const px: number = Math.round(vp2px(sizeVp));
  return `${bold ? '700' : '400'} ${px}px sans-serif`;
}

export interface DrawStyle {
  lineFade: string;
  start: string;
  end: string;
  pin: string;
  /** 位置是推算出来的节点用空心圆（填这个色 + style.pin 描边），一眼区分实测与推算 */
  pinEstimatedFill: string;
  pinText: string;
  floor: string;
  floorStroke: string;
  floorText: string;
  labelBg: string;
}

/** '#RRGGBB' → [r,g,b]，用于按进度插值轨迹线颜色（颜色来源仍是 Theme，不写死） */
function hexRgb(hex: string): number[] {
  return [
    parseInt(hex.substring(1, 3), 16),
    parseInt(hex.substring(3, 5), 16),
    parseInt(hex.substring(5, 7), 16)
  ];
}

/** 绘制整张三维图。floors 为楼层图层（来自 buildFloors，空数组则退回按米数分层） */
export function drawTrack3D(ctx: CanvasRenderingContext2D, plan: TrackPlan, pins: NodePin[],
  floors: FloorLevel[], view: View3D, w: number, h: number, style: DrawStyle): void {
  ctx.clearRect(0, 0, w, h);
  const samples = plan.samples;
  const pinVecs: Vec3[] = [];
  for (const p of pins) {
    pinVecs.push({ x: p.x, y: p.y, z: p.z });
  }
  if (samples.length === 0) {
    return;
  }
  const zoom = view.zoom > 0 ? view.zoom : 1;
  const fit = fitTransform(samples, pins, view.yawDeg * Math.PI / 180,
    view.pitchDeg * Math.PI / 180, w, h, 38, zoom);
  const yaw = view.yawDeg * Math.PI / 180;
  const pitch = view.pitchDeg * Math.PI / 180;
  const toScreen = (p: Vec3): Vec3 => {
    const q = projectPoint(p, yaw, pitch);
    return { x: fit.cx + q.x * fit.s, y: fit.cy + q.y * fit.s, z: q.z };
  };

  // 数据平面范围（画高度层用）
  let minX = samples[0].x;
  let maxX = samples[0].x;
  let minY = samples[0].y;
  let maxY = samples[0].y;
  for (const p of samples) {
    if (p.x < minX) {
      minX = p.x;
    }
    if (p.x > maxX) {
      maxX = p.x;
    }
    if (p.y < minY) {
      minY = p.y;
    }
    if (p.y > maxY) {
      maxY = p.y;
    }
  }
  for (const p of pins) {
    if (p.x < minX) {
      minX = p.x;
    }
    if (p.x > maxX) {
      maxX = p.x;
    }
    if (p.y < minY) {
      minY = p.y;
    }
    if (p.y > maxY) {
      maxY = p.y;
    }
  }
  // 层平面比采样点范围只稍微外扩一点：外扩越多，旋转后平面角越容易跑到画布外，
  // 贴在角上的高度标签就会画到看不见的地方（页面另有「高差」文字读数兜底）
  const padXY = Math.max(Math.max(maxX - minX, maxY - minY) * 0.03, 0.4);
  minX -= padXY; maxX += padXY; minY -= padXY; maxY += padXY;

  // ---- 楼层图层：远 → 近绘制，形成「一叠楼层」的空间感 ----
  // 2026-09-29 改版（用户要求）：层数跟着**实际记录到的楼层**走，不再每 2m 切一层 ——
  // 那样层数又多又没意义，一堆边框叠在一起就是用户说的「太密集」。节点一个楼层都没填时
  // 才退回按米数分层（标签写 +12m），两条路都产出 FloorLevel，所以下面只有一条绘制路径。
  //
  // 三个改动都是为了「不密集」：
  //  ① 每层只描**离观察者最近的那个角**（两条边拼成一个 V），像楼板前沿，不再四边全描；
  //  ② 越远的层越淡（fadeRgba 调 Theme 里那两个画布令牌的透明度，不用没验证过的 globalAlpha）；
  //  ③ 标签等所有图层画完后**由近到远**依次摆，位置打架的干脆不画 —— 近的先占位，
  //     留下的永远是看得最清的那几个。
  const levels: FloorLevel[] = floors.length > 0 ? floors : fallbackLevels(plan);
  if (levels.length > 0) {
    const depthOf: number[] = [];
    for (const lv of levels) {
      const c = toScreen({ x: (minX + maxX) / 2, y: (minY + maxY) / 2, z: lv.z });
      depthOf.push(c.z);
    }
    let dMin = depthOf[0];
    let dMax = depthOf[0];
    for (const d of depthOf) {
      if (d < dMin) {
        dMin = d;
      }
      if (d > dMax) {
        dMax = d;
      }
    }
    const dSpan = Math.max(dMax - dMin, 0.0001);

    const order: number[] = [];
    for (let i = 0; i < levels.length; i++) {
      order.push(i);
    }
    order.sort((a: number, b: number) => depthOf[b] - depthOf[a]);

    // 每个图层的「近角」屏幕坐标，留给第二轮摆标签用
    const nearPts: Vec3[] = [];
    for (const i of order) {
      const lv: FloorLevel = levels[i];
      const c1 = toScreen({ x: minX, y: minY, z: lv.z });
      const c2 = toScreen({ x: maxX, y: minY, z: lv.z });
      const c3 = toScreen({ x: maxX, y: maxY, z: lv.z });
      const c4 = toScreen({ x: minX, y: maxY, z: lv.z });
      const pts: Vec3[] = [c1, c2, c3, c4];
      // 屏幕 y 最大的那个角离观察者最近
      let near = 0;
      for (let k = 1; k < 4; k++) {
        if (pts[k].y > pts[near].y) {
          near = k;
        }
      }
      const fade = 1 - 0.6 * ((depthOf[i] - dMin) / dSpan);
      ctx.beginPath();
      ctx.moveTo(c1.x, c1.y);
      ctx.lineTo(c2.x, c2.y);
      ctx.lineTo(c3.x, c3.y);
      ctx.lineTo(c4.x, c4.y);
      ctx.closePath();
      ctx.fillStyle = fadeRgba(style.floor, fade);
      ctx.fill();
      // 只描近角的两条边
      const prev = pts[(near + 3) % 4];
      const next = pts[(near + 1) % 4];
      ctx.beginPath();
      ctx.moveTo(prev.x, prev.y);
      ctx.lineTo(pts[near].x, pts[near].y);
      ctx.lineTo(next.x, next.y);
      ctx.strokeStyle = fadeRgba(style.floorStroke, fade);
      ctx.lineWidth = 1.5;
      ctx.stroke();
      nearPts.push(pts[near]);
    }

    // 楼层标签：由近到远摆放。每个标签先试「近角上方」，被打架挡掉就依次往下、再往更上/更下挪一行。
    // 为什么要挪：俯视时各层的近角几乎落在一条线上，只试一个位置的话三层里只有一层能显示出来
    // （离线渲染出来才看见：3 层只标出了 1 个「3/F」）。实在挪不动才不画。
    const placedX: number[] = [];
    const placedY: number[] = [];
    // 字号一律用 vp：画布坐标是 vp，写 px 会变成物理像素（同一句在 3 倍密度屏上小到看不见）
    ctx.font = canvasFont(9.5, true);
    for (let i = 0; i < order.length; i++) {
      const lv: FloorLevel = levels[order[i]];
      const label: string = lv.name;
      const tw: number = textWidthVp(label, 9.5) + 12;
      const th = 15;
      let lx: number = nearPts[i].x + 6;
      if (lx + tw > w - 4) {
        lx = nearPts[i].x - 6 - tw;
      }
      if (lx < 4) {
        lx = 4;
      }
      const yTries: number[] = [nearPts[i].y - th - 2, nearPts[i].y + 6,
        nearPts[i].y - 2 * th - 6, nearPts[i].y + th + 10, nearPts[i].y + 2 * th + 14];
      let ly = -1;
      for (const ty of yTries) {
        if (ty < 4 || ty + th > h - 4) {
          continue;
        }
        let clash = false;
        for (let j = 0; j < placedX.length; j++) {
          if (Math.abs(placedX[j] - lx) < tw && Math.abs(placedY[j] - ty) < th + 2) {
            clash = true;
            break;
          }
        }
        if (!clash) {
          ly = ty;
          break;
        }
      }
      if (ly < 0) {
        continue;
      }
      placedX.push(lx);
      placedY.push(ly);
      const r = 6;
      ctx.beginPath();
      ctx.moveTo(lx + r, ly);
      ctx.arcTo(lx + tw, ly, lx + tw, ly + th, r);
      ctx.arcTo(lx + tw, ly + th, lx, ly + th, r);
      ctx.arcTo(lx, ly + th, lx, ly, r);
      ctx.arcTo(lx, ly, lx + tw, ly, r);
      ctx.closePath();
      ctx.fillStyle = style.labelBg;
      ctx.fill();
      ctx.strokeStyle = style.floorStroke;
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.fillStyle = style.floorText;
      ctx.fillText(label, lx + 6, ly + 10.8);
    }
  }

  // ---- 轨迹折线：颜色随进度由绿到红，先描一层淡色加粗线做「阴影」 ----
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const fromRgb: number[] = hexRgb(style.start);
  const toRgb: number[] = hexRgb(style.end);
  const n = samples.length;
  for (let i = 1; i < n; i++) {
    // 中间缺了一段（室内没有可用定位）就不连线，别假装知道那段路怎么走
    if (plan.sampleTimes.length > i && !sameSegment(plan.sampleTimes[i - 1], plan.sampleTimes[i])) {
      continue;
    }
    const a = toScreen(samples[i - 1]);
    const b = toScreen(samples[i]);
    const t = i / (n - 1);
    // 分级显示可信度（用户 2026-09-30 要求）：这一段两端只要有一端精度偏弱，
    // 就**不画阴影、线也更淡更细**。依据见 WEAK_ACCURACY_M 的注释。
    const accA: number | undefined = plan.accuracies.length > i - 1 ? plan.accuracies[i - 1] : undefined;
    const accB: number | undefined = plan.accuracies.length > i ? plan.accuracies[i] : undefined;
    const weak: boolean = weakFix(accA) || weakFix(accB);
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    if (!weak) {
      ctx.strokeStyle = style.lineFade;
      ctx.lineWidth = 9;
      ctx.stroke();
    }
    const r = Math.round(fromRgb[0] + t * (toRgb[0] - fromRgb[0]));
    const g = Math.round(fromRgb[1] + t * (toRgb[1] - fromRgb[1]));
    const bl = Math.round(fromRgb[2] + t * (toRgb[2] - fromRgb[2]));
    ctx.strokeStyle = weak ? `rgba(${r},${g},${bl},${Theme.CANVAS_WEAK_ALPHA})` : `rgb(${r},${g},${bl})`;
    ctx.lineWidth = weak ? 3 : 4.5;
    ctx.stroke();
  }

  // ---- 起点 / 终点 ----
  const markPoint = (p: Vec3, color: string, text: string): void => {
    const q = toScreen(p);
    ctx.beginPath();
    ctx.arc(q.x, q.y, 8, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.lineWidth = 3;
    ctx.strokeStyle = Theme.CARD;
    ctx.stroke();
    ctx.fillStyle = Theme.ON_RED;
    ctx.font = canvasFont(9, true);
    ctx.textAlign = 'center';
    ctx.fillText(text, q.x, q.y + 3.2);
    ctx.textAlign = 'left';
  };
  markPoint(samples[0], style.start, '起');
  markPoint(samples[n - 1], style.end, '终');

  // ---- 罗盘：东南西北（用户 2026-09-29 要求）----
  // 世界坐标里 +y 是北、+x 是东（buildPlan 里 y 取自纬度、x 取自经度），所以四个方向就是
  // (0,1) / (1,0) / (0,-1) / (-1,0)。罗盘是平面概念，**只按偏航旋转、不参与俯仰** ——
  // 若再乘 sin(pitch)，视角越平四个方向越会往左右挤成一堆，反而看不懂；地图类应用也都是这么做的。
  // 旋转后投到画布边缘（edgePointOnRect），所以拖到任何角度它都跟着转、且始终贴着四边。
  // 罗盘先画：它的位置要作为「已占位」交给下面的节点标签避让。
  const taken: LabelBox[] = [];
  const cardNames: string[] = ['北', '东', '南', '西'];
  const cardDirs: number[][] = [[0, 1], [1, 0], [0, -1], [-1, 0]];
  for (let ci = 0; ci < cardNames.length; ci++) {
    const wx: number = cardDirs[ci][0];
    const wy: number = cardDirs[ci][1];
    // 与 projectPoint 同一套水平旋转，只是去掉俯仰那一步
    const sdx: number = wx * Math.cos(yaw) - wy * Math.sin(yaw);
    const sdy: number = -(wx * Math.sin(yaw) + wy * Math.cos(yaw));
    const at: EdgePoint | undefined = edgePointOnRect(sdx, sdy, w, h, 15);
    if (at === undefined) {
      continue;
    }
    const cw: number = textWidthVp(cardNames[ci], 12) + 10;
    const ch = 18;
    const clx = at.x - cw / 2;
    const cly = at.y - ch / 2;
    const cr = 6;
    ctx.beginPath();
    ctx.moveTo(clx + cr, cly);
    ctx.arcTo(clx + cw, cly, clx + cw, cly + ch, cr);
    ctx.arcTo(clx + cw, cly + ch, clx, cly + ch, cr);
    ctx.arcTo(clx, cly + ch, clx, cly, cr);
    ctx.arcTo(clx, cly, clx + cw, cly, cr);
    ctx.closePath();
    ctx.fillStyle = style.labelBg;
    ctx.fill();
    ctx.strokeStyle = style.pin;
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.fillStyle = style.pinText;
    ctx.font = canvasFont(12, true);
    ctx.fillText(cardNames[ci], clx + 5, cly + 13.5);
    taken.push({ x: clx, y: cly, w: cw, h: ch });
  }

  // ---- 节点：按深度排序，近的后画（近的压在上面）----
  // 注意：ArkTS 是名义类型（不支持结构化类型），NodePin 不能直接当 Vec3 用，
  // 所以投影一律走这个显式转换出来的坐标数组，标签文字另从 pins 取。
  const drawOrder: number[] = [];
  for (let i = 0; i < pinVecs.length; i++) {
    drawOrder.push(i);
  }
  const pinDepth: number[] = [];
  for (const v of pinVecs) {
    pinDepth.push(toScreen(v).z);
  }
  drawOrder.sort((a: number, b: number) => pinDepth[b] - pinDepth[a]);

  // 标签文字与尺寸先算好（截断到画布宽度以内），再统一摆放位置
  const labelText: string[] = [];
  const labelTw: number[] = [];
  const labelTh = 20;
  for (let k = 0; k < pins.length; k++) {
    let text: string = pins[k].label;
    while (text.length > 3 && textWidthVp(text, 11) + 16 > w - 12) {
      text = `${text.substring(0, text.length - 2)}…`;
    }
    labelText.push(text);
    labelTw.push(textWidthVp(text, 11) + 16);
  }
  // 摆放顺序**由近到远**：近的先挑，占到的就是最顺手的位置；挑不到位置就只画圆点不画标签
  // （节点下面的列表里仍然有它）。drawOrder 是远→近，所以倒着走。
  const labelBox: Array<LabelBox | undefined> = [];
  for (let k = 0; k < pins.length; k++) {
    labelBox.push(undefined);
  }
  for (let k = drawOrder.length - 1; k >= 0; k--) {
    const i: number = drawOrder[k];
    const q = toScreen(pinVecs[i]);
    let box: LabelBox | undefined = placeLabel(q.x, q.y, labelTw[i], labelTh, w, h, taken);
    if (box === undefined) {
      // 完整标签摆不下 → 退一步只摆序号（与节点列表里的红色序号徽章一一对应）
      const num: string = shortLabelOf(pins[i].label);
      const nw: number = textWidthVp(num, 11) + 14;
      box = placeLabel(q.x, q.y, nw, 18, w, h, taken);
      if (box !== undefined) {
        labelText[i] = num;
      }
    }
    if (box !== undefined) {
      taken.push(box);
    }
    labelBox[i] = box;
  }

  // 圆点全部画完（远→近，近的压在上面），再统一画标签。
  // 分两轮是离线渲染出来才发现的：原来「画完圆点紧接着画自己的标签」，
  // 后面那个更近的节点的圆点会盖在远处节点的标签上（白圈糊住半个标签）。
  for (const i of drawOrder) {
    const pin: NodePin = pins[i];
    const q = toScreen(pinVecs[i]);
    const est: boolean = pin.estimated === true;
    ctx.beginPath();
    ctx.arc(q.x, q.y, 9, 0, Math.PI * 2);
    // 推算出来的位置画成空心圆：一眼能看出「这是按时间推的，不是实测坐标」
    ctx.fillStyle = est ? style.pinEstimatedFill : style.pin;
    ctx.fill();
    ctx.lineWidth = 3;
    ctx.strokeStyle = Theme.CARD;
    ctx.stroke();
  }

  for (const i of drawOrder) {
    // 位置已经在上面统一摆好了；没摆到的（太挤）只留圆点，节点列表里仍然有它
    const box: LabelBox | undefined = labelBox[i];
    if (box === undefined) {
      continue;
    }
    // 2026-09-29 用户要求：**标签框做成透明的**。不再画白底药丸，只把文字压在图上。
    // 位置仍然由 placeLabel 算（避让其他标签与罗盘，所以标签之间不会叠），
    // 但**不画框**——图面干净，也不挡住楼层板和轨迹。可读性靠「加粗 + 深红」：
    // 底色是浅灰画布，深红加粗的字直接看是清楚的。
    //
    // ⚠️ 不要在估算位被占满时把标签甩到离圆点很远的地方（那正是用户说过的「脱离轨迹的东西」）：
    // 摆不下就退成只摆序号，再摆不下就只留圆点 —— 这个取舍在 placeLabel 那边。
    ctx.fillStyle = style.pinText;
    ctx.font = canvasFont(11, true);
    ctx.fillText(labelText[i], box.x + 8, box.y + 14);
  }
}
