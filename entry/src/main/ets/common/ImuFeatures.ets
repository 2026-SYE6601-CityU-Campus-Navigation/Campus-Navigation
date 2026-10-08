/**
 * 每秒窗口内的原始 IMU 采样序列的编解码（纯函数，可离线单测）。
 *
 * ⚠️ 2026-10-04（阶段 0）新增。为什么单独抽成模块：与 `WifiSummary` 同理 ——
 * 「每秒窗口怎么攒、怎么编码、超限怎么抽稀」这三件事**只有真机 + 传感器才跑得起来**，
 * 嵌在 `TrackRecorder` 里就离线测不了。
 *
 * **为什么存原始序列而不是只存特征**（与原《室内定位改进方案》里「存每秒特征」的写法不同）：
 * 特征算错了就没法从聚合值里反推（步态检测要的是波形，不是均值/方差），那样整批数据只能报废重采；
 * 而 `wifiTop` 已经证明「每个采样点挂一条几百字符的紧凑字符串」在这个工程里是可接受的代价。
 * 所以这里选**信息量最大的存法**：把这一秒的原始三轴序列压成一条字符串存下来，
 * 步态检测、步长、朝向积分全都可以事后在 PC 端反复重算。
 *
 * 存储格式（每条采样点一行、两个字段各一条字符串）：
 *   `"t:x:y:z;t:x:y:z;…"`   t = 相对本秒窗口起点的毫秒（整数），x/y/z = 三轴分量（定点小数）
 * 加速度单位 m/s²、陀螺仪单位 rad/s（原样存，不改单位，避免二次猜测）。
 */

/** 一帧三轴采样。`t` 是相对本秒窗口起点的毫秒偏移。 */
export interface Vec3Sample {
  t: number;
  x: number;
  y: number;
  z: number;
}

/**
 * 每秒最多保留多少个样本，超了等距抽稀。
 *
 * 60 Hz 对步态（约 2 Hz）和朝向积分都绰绰有余，而它能挡住「传感器回调频率远超预期
 * 把每行撑爆」的风险 —— 回调频率由平台决定、本工程无法预先核实，
 * 所以这里按上限截断，实际频率靠 `accelSeries` 的样本数反推（见开发日志的采集要求）。
 */
export const IMU_MAX_PER_WINDOW = 60;

/** 向量模长（加速度的幅值、陀螺仪的角速度幅值都用它）。 */
export function magnitude(v: Vec3Sample): number {
  return Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
}

/**
 * 等距抽稀到 `limit` 个以内。返回**原数组本身**（未超限时），调用方不要就地修改。
 * 抽稀而不是截断：截断只会留下这一秒的开头一段，波形会被破坏。
 */
export function decimate(samples: Vec3Sample[], limit: number): Vec3Sample[] {
  const n: number = samples.length;
  if (limit <= 0 || n <= limit) {
    return samples;
  }
  const stride: number = Math.ceil(n / limit);
  const out: Vec3Sample[] = [];
  for (let i = 0; i < n; i += stride) {
    out.push(samples[i]);
  }
  return out;
}

/** 把一秒的采样序列编码成存储串；超限自动等距抽稀。空数组返回空串。 */
export function encodeSeries(samples: Vec3Sample[], decimals: number): string {
  const arr: Vec3Sample[] = decimate(samples, IMU_MAX_PER_WINDOW);
  const parts: string[] = [];
  for (let i = 0; i < arr.length; i++) {
    const v: Vec3Sample = arr[i];
    parts.push(`${Math.round(v.t)}:${v.x.toFixed(decimals)}:${v.y.toFixed(decimals)}:${v.z.toFixed(decimals)}`);
  }
  return parts.join(';');
}

/** 解析存储串。空串、坏段一律跳过（老数据字段为空串是正常情形）。 */
export function parseSeries(s: string): Vec3Sample[] {
  const out: Vec3Sample[] = [];
  if (s.length === 0) {
    return out;
  }
  for (const seg of s.split(';')) {
    if (seg.length === 0) {
      continue;
    }
    const f: string[] = seg.split(':');
    if (f.length < 4) {
      continue;
    }
    const t: number = Number.parseFloat(f[0]);
    const x: number = Number.parseFloat(f[1]);
    const y: number = Number.parseFloat(f[2]);
    const z: number = Number.parseFloat(f[3]);
    if (Number.isNaN(t) || Number.isNaN(x) || Number.isNaN(y) || Number.isNaN(z)) {
      continue;
    }
    out.push({ t: t, x: x, y: y, z: z });
  }
  return out;
}
