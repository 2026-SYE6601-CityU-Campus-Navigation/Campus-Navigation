import { TrackPoint } from '../data/Entities';
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

/** 国际气压高度公式：由气压 p 相对基准 p0 估算高度差（米） */
export function pressureToHeight(p: number, p0: number): number {
  if (p <= 0 || p0 <= 0) {
    return 0;
  }
  return 44330 * (1 - Math.pow(p / p0, 0.1903));
}

/** 经纬度 + 高度 → 本地米制坐标（以首个有效定位点为原点） */
export function buildPlan(pts: TrackPoint[]): TrackPlan {
  const geo: TrackPoint[] = [];
  let noGeo = 0;
  for (const p of pts) {
    if (p.latitude !== undefined && p.longitude !== undefined) {
      geo.push(p);
    } else {
      noGeo++;
    }
  }
  if (geo.length === 0) {
    const empty: Vec3[] = [];
    const times: number[] = [];
    const none: TrackPlan = {
      heightSource: 'none', samples: empty, sampleTimes: times, noGeoCount: noGeo,
      minZ: 0, maxZ: 0, zScale: 1, hasOrigin: false, lat0: 0, lng0: 0, altBase: 0, pBase: 0
    };
    return none;
  }

  const lat0 = geo[0].latitude as number;
  const lng0 = geo[0].longitude as number;
  const mLng = M_PER_LNG_PER_DEG * Math.cos(lat0 * Math.PI / 180);

  // 高度来源判定：海拔优先，其次气压（以首个有效气压为基准）
  let altBase: number | undefined = undefined;
  for (const p of geo) {
    if (p.altitude !== undefined) {
      altBase = p.altitude;
      break;
    }
  }
  let p0: number | undefined = undefined;
  for (const p of geo) {
    if (p.pressureHpa !== undefined && p.pressureHpa > 0) {
      p0 = p.pressureHpa;
      break;
    }
  }
  let source = 'none';
  if (altBase !== undefined) {
    source = 'gps';
  } else if (p0 !== undefined) {
    source = 'pressure';
  }

  const samples: Vec3[] = [];
  const sampleTimes: number[] = [];
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
      z = (p.altitude !== undefined ? p.altitude : (altBase as number)) - (altBase as number);
    } else if (source === 'pressure') {
      if (p.pressureHpa !== undefined) {
        z = pressureToHeight(p.pressureHpa, p0 as number);
      }
    }
    const x = (lng - lng0) * mLng;
    const y = (lat - lat0) * M_PER_LAT;
    const v: Vec3 = { x: x, y: y, z: z };
    samples.push(v);
    sampleTimes.push(p.timeMs);
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
    noGeoCount: noGeo,
    minZ: minZ,
    maxZ: maxZ,
    zScale: zScale,
    hasOrigin: true,
    lat0: lat0,
    lng0: lng0,
    altBase: altBase === undefined ? 0 : altBase,
    pBase: p0 === undefined ? 0 : p0
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
 *  - 节点自带经纬度 → 直接用；高度优先用节点自己的海拔（有的话），否则按时间对齐到轨迹高度。
 *  - 节点没有经纬度（室内采集最常见）→ **按时间就近取采样点的平面位置**：节点是在那一刻
 *    按下的，手机当时就在轨迹的那个位置上。这样室内节点也能画出来并带名称，
 *    但位置是推算的，NodePin.estimated 标 true，界面要如实说明，不能当成实测坐标。
 *
 * 整条轨迹完全没有定位（plan.hasOrigin=false）时返回 undefined，无从摆放。
 */
export function pinFrom(lat: number | undefined, lng: number | undefined,
  altitude: number | undefined, timeMs: number, label: string, plan: TrackPlan): NodePin | undefined {
  if (!plan.hasOrigin || plan.samples.length === 0) {
    return undefined;
  }
  if (lat === undefined || lng === undefined) {
    const i: number = nearestSampleIndex(plan, timeMs);
    if (i < 0) {
      return undefined;
    }
    const s: Vec3 = plan.samples[i];
    const est: NodePin = { x: s.x, y: s.y, z: s.z, label: label, estimated: true };
    return est;
  }
  const mLng = M_PER_LNG_PER_DEG * Math.cos(plan.lat0 * Math.PI / 180);
  let z: number;
  if (plan.heightSource === 'gps' && altitude !== undefined) {
    z = (altitude - plan.altBase) * plan.zScale;
  } else {
    z = zForTime(plan, timeMs);
  }
  const pin: NodePin = {
    x: (lng - plan.lng0) * mLng,
    y: (lat - plan.lat0) * M_PER_LAT,
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

/** 绘制整张三维图 */
export function drawTrack3D(ctx: CanvasRenderingContext2D, plan: TrackPlan, pins: NodePin[],
  view: View3D, w: number, h: number, style: DrawStyle): void {
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

  // ---- 高度层平面：远 → 近绘制，形成「一叠楼层」的空间感 ----
  // 层位按**真实高度**切分，绘制时乘 zScale 压到显示高度，
  // 这样层标注的数字始终是真实相对高度（+12m 就写 +12m），压缩只改观感不改读数。
  const zs = plan.zScale > 0 ? plan.zScale : 1;
  const step = levelStep(plan.minZ, plan.maxZ);
  if (step > 0) {
    const z0 = Math.floor(plan.minZ / step) * step;
    const z1 = Math.ceil(plan.maxZ / step) * step;
    const planes: number[] = [];
    for (let z = z0; z <= z1 + 0.001; z += step) {
      planes.push(z);
    }
    // 每层四个角，先算深度再排序
    const order: number[] = [];
    for (let i = 0; i < planes.length; i++) {
      order.push(i);
    }
    const depthOf: number[] = [];
    for (const z of planes) {
      const c = toScreen({ x: (minX + maxX) / 2, y: (minY + maxY) / 2, z: z * zs });
      depthOf.push(c.z);
    }
    order.sort((a: number, b: number) => depthOf[b] - depthOf[a]);
    for (const i of order) {
      const z = planes[i];
      const dz = z * zs;
      const c1 = toScreen({ x: minX, y: minY, z: dz });
      const c2 = toScreen({ x: maxX, y: minY, z: dz });
      const c3 = toScreen({ x: maxX, y: maxY, z: dz });
      const c4 = toScreen({ x: minX, y: maxY, z: dz });
      ctx.beginPath();
      ctx.moveTo(c1.x, c1.y);
      ctx.lineTo(c2.x, c2.y);
      ctx.lineTo(c3.x, c3.y);
      ctx.lineTo(c4.x, c4.y);
      ctx.closePath();
      ctx.fillStyle = style.floor;
      ctx.fill();
      ctx.strokeStyle = style.floorStroke;
      ctx.lineWidth = 1;
      ctx.stroke();
      // 高度标签贴在左前角，标真实相对高度（不编造楼层号）；
      // 锚点被旋转推到画布外时直接不画，避免标签跑到画布外或挤在边缘误导
      const lx = c1.x - 2;
      const ly = c1.y - 4;
      if (lx >= 4 && lx <= w - 30 && ly >= 12 && ly <= h - 4) {
        ctx.fillStyle = style.floorText;
        ctx.font = '700 10px sans-serif';
        ctx.fillText(`${z >= 0 ? '+' : ''}${z.toFixed(0)}m`, lx, ly);
      }
    }
  }

  // ---- 轨迹折线：颜色随进度由绿到红，先描一层淡色加粗线做「阴影」 ----
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const fromRgb: number[] = hexRgb(style.start);
  const toRgb: number[] = hexRgb(style.end);
  const n = samples.length;
  for (let i = 1; i < n; i++) {
    const a = toScreen(samples[i - 1]);
    const b = toScreen(samples[i]);
    const t = i / (n - 1);
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.strokeStyle = style.lineFade;
    ctx.lineWidth = 9;
    ctx.stroke();
    const r = Math.round(fromRgb[0] + t * (toRgb[0] - fromRgb[0]));
    const g = Math.round(fromRgb[1] + t * (toRgb[1] - fromRgb[1]));
    const bl = Math.round(fromRgb[2] + t * (toRgb[2] - fromRgb[2]));
    ctx.strokeStyle = `rgb(${r},${g},${bl})`;
    ctx.lineWidth = 4.5;
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
    ctx.font = '700 9px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(text, q.x, q.y + 3.2);
    ctx.textAlign = 'left';
  };
  markPoint(samples[0], style.start, '起');
  markPoint(samples[n - 1], style.end, '终');

  // ---- 节点：按深度排序，近的后画；标签用白底药丸，左右自动避让边界 ----
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

    ctx.font = '700 11px sans-serif';
    // 标签过长时截断加省略号：药丸不能宽过画布，否则会被裁掉尾巴
    let text: string = pin.label;
    while (text.length > 3 && ctx.measureText(text).width + 16 > w - 12) {
      text = `${text.substring(0, text.length - 2)}…`;
    }
    const tw = ctx.measureText(text).width + 16;
    const th = 20;
    let lx = q.x + 13;
    let ly = q.y - 27;
    if (lx + tw > w - 4) {
      lx = q.x - 13 - tw;
    }
    if (lx < 2) {
      lx = 2;
    }
    if (ly < 2) {
      ly = q.y + 8;
    }
    if (ly + th > h - 2) {
      ly = h - 2 - th;
    }
    const r = 9;
    ctx.beginPath();
    ctx.moveTo(lx + r, ly);
    ctx.arcTo(lx + tw, ly, lx + tw, ly + th, r);
    ctx.arcTo(lx + tw, ly + th, lx, ly + th, r);
    ctx.arcTo(lx, ly + th, lx, ly, r);
    ctx.arcTo(lx, ly, lx + tw, ly, r);
    ctx.closePath();
    ctx.fillStyle = style.labelBg;
    ctx.fill();
    ctx.strokeStyle = style.pin;
    ctx.lineWidth = est ? 1 : 1.5;
    ctx.stroke();
    ctx.fillStyle = style.pinText;
    ctx.fillText(text, lx + 8, ly + 14);
  }
}
