import { util } from '@kit.ArkTS';

/**
 * 手写 ZIP 打包器：STORED（不压缩）+ UTF-8 文件名 + CRC32。
 * HarmonyOS 各 API 版本无官方多文件 zip 库，此实现无第三方依赖、全版本可用。
 *
 * ⚠️ 2026-09-29（第二十六轮）：从「一次算出一整包字节」改成**流式**。
 * 起因是真机上传时打包中途闪退。量了一下导出包：一个只有 **5 张照片**的轨迹包就有 **17.5 MB**
 * （照片原图每张 2.7~4.1 MB，见那个真实导出包），而老实现要同时握住
 * 「全部照片」和「整包字节」两份 —— 勾 5 条轨迹就是 2×87 MB，必崩。
 * 现在改成边读边写：调用方内存里**只留一个文件**，峰值与包的总大小无关。
 *
 * 分工：本文件只负责**生成字节**（本地头 / 中央目录项 / 结束记录），**不碰文件系统**；
 * 真正的读写由调用方（Exporter）驱动 —— 好处是打包格式可以在离线沙箱里
 * 用 Python 的 zipfile / unzip 逐项校验（已做过）。
 */

export interface ZipEntry {
  /** 包内相对路径，如 track_1.json 或 photos/1/1726450000000.jpg */
  name: string;
  data: Uint8Array;
}

const CRC_TABLE: number[] = [];

function ensureCrcTable(): void {
  if (CRC_TABLE.length > 0) {
    return;
  }
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    CRC_TABLE.push(c >>> 0);
  }
}

export function crc32(bytes: Uint8Array): number {
  ensureCrcTable();
  let c = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) {
    c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) >>> 0;
}

/** DOS 格式时间（2 字节）与日期（2 字节） */
function dosTime(ms: number): number {
  const d = new Date(ms);
  return (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
}

function dosDate(ms: number): number {
  const d = new Date(ms);
  return (((d.getFullYear() - 1980) & 0x7F) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
}

function w16(buf: Uint8Array, off: number, v: number): void {
  buf[off] = v & 0xFF;
  buf[off + 1] = (v >>> 8) & 0xFF;
}

function w32(buf: Uint8Array, off: number, v: number): void {
  buf[off] = v & 0xFF;
  buf[off + 1] = (v >>> 8) & 0xFF;
  buf[off + 2] = (v >>> 16) & 0xFF;
  buf[off + 3] = (v >>> 24) & 0xFF;
}

/** 本地文件头（30 字节 + 文件名）。size/crc 是**数据**的大小与校验值（STORED 下压缩前后同值） */
export function localHeader(nb: Uint8Array, size: number, crc: number, nowMs: number): Uint8Array {
  const h = new Uint8Array(30 + nb.length);
  w32(h, 0, 0x04034B50);          // 签名
  w16(h, 4, 20);                  // 版本
  w16(h, 6, 0x0800);              // UTF-8 文件名标志
  w16(h, 8, 0);                   // 压缩方式：STORED
  w16(h, 10, dosTime(nowMs));     // 修改时间
  w16(h, 12, dosDate(nowMs));     // 修改日期
  w32(h, 14, crc);                // CRC32
  w32(h, 18, size);               // 压缩后大小
  w32(h, 22, size);               // 原始大小
  w16(h, 26, nb.length);          // 文件名长度
  w16(h, 28, 0);                  // 扩展段长度
  for (let k = 0; k < nb.length; k++) {
    h[30 + k] = nb[k];
  }
  return h;
}

/** 中央目录项（46 字节 + 文件名）。localOffset = 该条目本地头的起始偏移 */
export function centralHeader(nb: Uint8Array, size: number, crc: number,
  localOffset: number, nowMs: number): Uint8Array {
  const h = new Uint8Array(46 + nb.length);
  w32(h, 0, 0x02014B50);          // 签名
  w16(h, 4, 20);                  // 制作版本
  w16(h, 6, 20);                  // 所需版本
  w16(h, 8, 0x0800);              // 标志
  w16(h, 10, 0);                  // 压缩方式
  w16(h, 12, dosTime(nowMs));
  w16(h, 14, dosDate(nowMs));
  w32(h, 16, crc);
  w32(h, 20, size);
  w32(h, 24, size);
  w16(h, 28, nb.length);
  w16(h, 30, 0);                  // 扩展段
  w16(h, 32, 0);                  // 注释
  w16(h, 34, 0);                  // 磁盘号
  w16(h, 36, 0);                  // 内部属性
  w32(h, 38, 0);                  // 外部属性
  w32(h, 42, localOffset);        // 本地头偏移
  for (let k = 0; k < nb.length; k++) {
    h[46 + k] = nb[k];
  }
  return h;
}

/** 中央目录结束记录（22 字节） */
export function endRecord(count: number, cdSize: number, cdOffset: number): Uint8Array {
  const h = new Uint8Array(22);
  w32(h, 0, 0x06054B50);
  w16(h, 4, 0);                   // 本磁盘号
  w16(h, 6, 0);                   // 中央目录起始磁盘号
  w16(h, 8, count);               // 本磁盘条目数
  w16(h, 10, count);              // 总条目数
  w32(h, 12, cdSize);
  w32(h, 16, cdOffset);
  w16(h, 20, 0);                  // 注释长度
  return h;
}

/**
 * 把一段字节**写满**。
 *
 * 单次 writeSync 可能只完成一部分（本项目在照片复制那里已经吃过这个亏），
 * 而 zip 的中央目录偏移是照着「每个条目都写满」算出来的 —— 少写一个字节，
 * 包会变成「能打开但内容错位」的坏包，比直接报错危险得多，所以写不满就抛。
 *
 * 写成「把写函数传进来」而不是直接调 fs：这样这段逻辑能在离线沙箱里
 * 用一个**只肯写几个字节的假 sink** 真跑一遍（见 test_zip.ts）。
 */
export function writeAllTo(sink: (bytes: ArrayBuffer) => number, data: Uint8Array): void {
  // 本项目里传进来的都是「整块」视图（new Uint8Array(n) / encodeInto 的返回值 / slice 的结果），
  // 第一次尝试可以直接把底层 buffer 交给 sink，不必为几 MB 的照片再复制一份
  const whole: boolean = data.byteOffset === 0 && data.byteLength === data.buffer.byteLength;
  let written = 0;
  while (written < data.length) {
    const buf: ArrayBuffer = (written === 0 && whole)
      ? (data.buffer as ArrayBuffer)
      : (data.buffer.slice(data.byteOffset + written, data.byteOffset + data.length) as ArrayBuffer);
    const n: number = sink(buf);
    if (n <= 0) {
      break;
    }
    written += n;
  }
  if (written < data.length) {
    throw new Error(`只写入 ${written}/${data.length} 字节`);
  }
}

/**
 * 流式打包状态机。
 *
 * 调用方按顺序处理每个条目：
 * ```
 * const head = z.entryHeader(nameBytes, size, crc, now);   // 1. 拿本地头
 * writeAll(fd, head);                                       // 2. 写头
 * writeAll(fd, data);                                       // 3. 写数据
 * ```
 * 全部条目写完后 `writeAll(fd, z.finish())` 写出中央目录与结束记录。
 *
 * ⚠️ 偏移是照着「头长度 + size」**累加**出来的，所以调用方必须保证每一次写都写满
 * （Exporter.writeAll 会写满、写不满就抛错）。少写一个字节，后面所有条目的偏移就全错，
 * 包会变成「能打开但内容错位」的坏包 —— 比直接报错危险得多。
 */
export class ZipStream {
  private offset: number = 0;
  private cdChunks: Uint8Array[] = [];
  private cdSize: number = 0;
  private count: number = 0;

  /** 已写出的字节数（＝下一个条目本地头的偏移；也用来对账落盘大小） */
  writtenBytes(): number {
    return this.offset;
  }

  entryCount(): number {
    return this.count;
  }

  /** 声明一个条目并返回它的本地文件头 */
  entryHeader(nb: Uint8Array, size: number, crc: number, nowMs: number): Uint8Array {
    const head: Uint8Array = localHeader(nb, size, crc, nowMs);
    const cd: Uint8Array = centralHeader(nb, size, crc, this.offset, nowMs);
    this.cdChunks.push(cd);
    this.cdSize += cd.length;
    this.offset += head.length + size;
    this.count++;
    return head;
  }

  /** 收尾：中央目录 + 结束记录（每个条目几十字节，整体很小，一次写出即可） */
  finish(): Uint8Array {
    const end: Uint8Array = endRecord(this.count, this.cdSize, this.offset);
    const out: Uint8Array = new Uint8Array(this.cdSize + end.length);
    let o: number = 0;
    for (const c of this.cdChunks) {
      for (let k = 0; k < c.length; k++) {
        out[o + k] = c[k];
      }
      o += c.length;
    }
    for (let k = 0; k < end.length; k++) {
      out[o + k] = end[k];
    }
    return out;
  }

  /** 整包最终的字节数（写完之后拿它和落盘大小对账） */
  totalBytes(): number {
    return this.offset + this.cdSize + 22;
  }
}

/**
 * 内容全在内存里的小包直接出字节。Exporter 现在走流式不用它，
 * 但**打包格式的离线校验**（在沙箱里生成一个 zip 再用 Python zipfile / unzip 逐项核对）
 * 正是靠它 —— 没有它就没法在本地验证这套头字节写对没有。
 */
export function buildZip(entries: ZipEntry[]): ArrayBuffer {
  const encoder = new util.TextEncoder();
  const now: number = Date.now();
  const z: ZipStream = new ZipStream();
  const parts: Uint8Array[] = [];
  for (const e of entries) {
    const nb: Uint8Array = encoder.encodeInto(e.name);
    parts.push(z.entryHeader(nb, e.data.length, crc32(e.data), now));
    parts.push(e.data);
  }
  parts.push(z.finish());
  const out: Uint8Array = new Uint8Array(z.totalBytes());
  let o: number = 0;
  for (const p of parts) {
    for (let k = 0; k < p.length; k++) {
      out[o + k] = p[k];
    }
    o += p.length;
  }
  return out.buffer;
}
