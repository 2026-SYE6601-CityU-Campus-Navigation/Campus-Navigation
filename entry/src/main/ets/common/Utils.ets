import { common } from '@kit.AbilityKit';

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
