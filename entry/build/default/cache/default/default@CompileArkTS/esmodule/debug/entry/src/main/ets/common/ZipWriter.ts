import util from "@ohos:util";
/**
 * 手写 ZIP 打包器：STORED（不压缩）+ UTF-8 文件名 + CRC32。
 * HarmonyOS 各 API 版本无官方多文件 zip 库，此实现无第三方依赖、全版本可用。
 * 数据量级（轨迹 JSON + 照片，几十 MB 内）下 STORED 的耗时与体积都可接受。
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
function crc32(bytes: Uint8Array): number {
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
export function buildZip(entries: ZipEntry[]): ArrayBuffer {
    const encoder = new util.TextEncoder();
    ensureCrcTable();
    const t = dosTime(Date.now());
    const d = dosDate(Date.now());
    // 预编码文件名并计算各段偏移
    const nameBufs: Uint8Array[] = [];
    const crcs: number[] = [];
    const localOffsets: number[] = [];
    let offset = 0;
    for (const e of entries) {
        const nb: Uint8Array = encoder.encodeInto(e.name);
        nameBufs.push(nb);
        crcs.push(crc32(e.data));
        localOffsets.push(offset);
        offset += 30 + nb.length + e.data.length;
    }
    const cdOffset = offset;
    let cdSize = 0;
    for (const nb of nameBufs) {
        cdSize += 46 + nb.length;
    }
    const total = cdOffset + cdSize + 22;
    const buf = new Uint8Array(total);
    // 本地文件头 + 数据
    for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        const nb = nameBufs[i];
        const crc = crcs[i];
        let o = localOffsets[i];
        w32(buf, o, 0x04034B50); // 签名
        w16(buf, o + 4, 20); // 版本
        w16(buf, o + 6, 0x0800); // UTF-8 文件名标志
        w16(buf, o + 8, 0); // 压缩方式：STORED
        w16(buf, o + 10, t); // 修改时间
        w16(buf, o + 12, d); // 修改日期
        w32(buf, o + 14, crc); // CRC32
        w32(buf, o + 18, e.data.length); // 压缩后大小
        w32(buf, o + 22, e.data.length); // 原始大小
        w16(buf, o + 26, nb.length); // 文件名长度
        w16(buf, o + 28, 0); // 扩展段长度
        o += 30;
        for (let k = 0; k < nb.length; k++) {
            buf[o + k] = nb[k];
        }
        o += nb.length;
        for (let k = 0; k < e.data.length; k++) {
            buf[o + k] = e.data[k];
        }
    }
    // 中央目录
    let o = cdOffset;
    for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        const nb = nameBufs[i];
        const crc = crcs[i];
        w32(buf, o, 0x02014B50); // 签名
        w16(buf, o + 4, 20); // 制作版本
        w16(buf, o + 6, 20); // 所需版本
        w16(buf, o + 8, 0x0800); // 标志
        w16(buf, o + 10, 0); // 压缩方式
        w16(buf, o + 12, t);
        w16(buf, o + 14, d);
        w32(buf, o + 16, crc);
        w32(buf, o + 20, e.data.length);
        w32(buf, o + 24, e.data.length);
        w16(buf, o + 28, nb.length);
        w16(buf, o + 30, 0); // 扩展段
        w16(buf, o + 32, 0); // 注释
        w16(buf, o + 34, 0); // 磁盘号
        w16(buf, o + 36, 0); // 内部属性
        w32(buf, o + 38, 0); // 外部属性
        w32(buf, o + 42, localOffsets[i]); // 本地头偏移
        o += 46;
        for (let k = 0; k < nb.length; k++) {
            buf[o + k] = nb[k];
        }
        o += nb.length;
    }
    // 中央目录结束记录
    w32(buf, o, 0x06054B50);
    w16(buf, o + 4, 0);
    w16(buf, o + 6, 0);
    w16(buf, o + 8, entries.length);
    w16(buf, o + 10, entries.length);
    w32(buf, o + 12, cdSize);
    w32(buf, o + 16, cdOffset);
    w16(buf, o + 20, 0);
    return buf.buffer;
}
