import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { Ctx } from '../common/Utils';

export interface PhotoCapture {
  absPath: string;
  relPath: string;
  timeMs: number;
}

/**
 * 轨迹途中拍照：调起系统相机（cameraPicker，无需相机权限、自动回到应用），
 * 照片直接落进 filesDir/photos/{trackId}/ 沙箱目录。
 *
 * 2026-09-28 第三次修复。真机报错是两条路都 `No such file or directory`：
 *  「复制照片失败（系统复制：No such file or directory；分块读取：No such file or directory）」
 *  —— 说明根本不是 size / 写满 / 目录的问题，而是**那个源 URI 就打不开**。
 *  原因：不配置 `saveUri` 时，相机把照片存进**公共媒体库**，`resultUri` 是
 *  `file://media/Photo/...` 这样的公共媒体路径，应用没有也不该有权限用 fileIo 去读它，
 *  所以「拍完再复制回来」这条路本身就是错的（旧版第一张能成、之后全败，也只是时序上碰巧）。
 *
 *  正确做法（官方文档 PickerProfile.saveUri）：**先在沙箱里建好目标文件**，把它的 uri 放进
 *  `saveUri` —— 这相当于应用把该文件授权给系统相机，相机拍完**直接覆盖写入**这个文件，
 *  应用完全不需要去读媒体库。附带好处：照片不再进系统相册（之前每拍一张都会进相册）。
 *
 *  保底：万一 saveUri 没生效（相机仍存媒体库、文件还是 0 字节），就用**同一次 pick** 的
 *  `resultUri` 走复制（唯一合规矩的兜底，不会再拉一次相机）；仍失败就把 resultCode、两条
 *  路径和原因全写进错误信息，避免再来一轮猜。
 *
 *  返回值：用户取消（resultCode≠0）时返回 `undefined` —— **取消不是失败**，调用方给个普通
 *  提示就行，不要当成错误留在界面上（否则用户会习惯性忽略那条真正的错误信息）。
 */
export async function captureTrackPhoto(trackId: number): Promise<PhotoCapture | undefined> {
  const ctx = Ctx.ui;
  if (!ctx) {
    throw new Error('应用还没准备好，请稍后再试');
  }
  const timeMs = Date.now();
  const relDir = `photos/${trackId}`;
  const absDir = `${ctx.filesDir}/${relDir}`;
  ensureDir(absDir);
  const relPath = `${relDir}/${timeMs}.jpg`;
  const absPath = `${absDir}/${timeMs}.jpg`;

  // saveUri 要求目标文件「已存在且可写」，所以先建一个空文件（名字带时间戳，不会撞车）。
  // 每一步都单独包一层并带上路径/原因：真机出问题时，界面上那行字就能直接指出是哪一步。
  try {
    const created = fs.createRandomAccessFileSync(absPath, fs.OpenMode.CREATE);
    created.close();
  } catch (e) {
    throw new Error(`建立照片文件失败：${absPath}（${(e as Error).message}）`);
  }

  let saveUri = '';
  try {
    saveUri = fileUri.getUriFromPath(absPath);
  } catch (e) {
    throw new Error(`生成沙箱文件 URI 失败：${absPath}（${(e as Error).message}）`);
  }

  // cameraPosition 为必填，枚举来自同 kit 的 camera 命名空间（cameraPicker 自身没有）
  const profile: cameraPicker.PickerProfile = {
    cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
    saveUri: saveUri
  };
  let result: cameraPicker.PickerResult;
  try {
    result = await cameraPicker.pick(ctx, [cameraPicker.PickerMediaType.PHOTO], profile);
  } catch (e) {
    deletePhotoFile(absPath);
    throw new Error(`调起相机失败（${(e as Error).message}）`);
  }

  const srcUri: string = result.resultUri;
  if (result.resultCode !== 0) {
    // 取消（或相机侧失败）：把占位文件删掉，交给调用方按「取消」处理
    deletePhotoFile(absPath);
    return undefined;
  }
  if (sizeOf(absPath) > 0) {
    // 正常路径：相机已经写进沙箱了，不需要任何复制
    const out: PhotoCapture = { absPath: absPath, relPath: relPath, timeMs: timeMs };
    return out;
  }
  // 保底：saveUri 没生效（照片还在媒体库），用同一次 pick 返回的 uri 复制过来
  let copyErr = '没有可用的返回路径';
  if (srcUri !== undefined && srcUri.length > 0) {
    try {
      copyFile(srcUri, absPath);
      copyErr = '';
    } catch (e) {
      copyErr = (e as Error).message;
    }
  }
  if (sizeOf(absPath) > 0) {
    const out: PhotoCapture = { absPath: absPath, relPath: relPath, timeMs: timeMs };
    return out;
  }
  deletePhotoFile(absPath);
  throw new Error(`照片没能存进沙箱：相机往 ${saveUri} 写入 0 字节，从 ${srcUri} 复制也没成功（${copyErr}）`);
}

/** 文件大小（读不到当 0 处理，用于判断相机到底有没有写进来） */
function sizeOf(absPath: string): number {
  try {
    return fs.statSync(absPath).size;
  } catch (e) {
    return 0;
  }
}

/**
 * 确保目录存在。
 *
 * ⚠️ **这里踩过一个代价很大的坑，写下来别再犯**：
 * `fs.accessSync` 返回**布尔值**，文件/目录不存在时返回 `false` 而**不抛异常**
 * （文档：「以同步方法检查文件或目录是否存在…返回 true 表示文件存在；返回 false 表示文件不存在」，
 * 只有权限不足才会抛 13900012）。所以「调一下 accessSync、没抛异常就认为目录已存在」是错的：
 * 目录**从来没被创建过**，之后每一步写文件都 ENOENT —— 拍照一张都存不下来的真正原因就是这个
 * （第一张能成功是因为更早的版本无条件调 mkdirSync，后来我换成探测式就把它改坏了）。
 *
 * 现在：直接建，再用 `statSync` 校验（stat 对不存在的路径会抛，这个信号是可靠的）。
 */
function ensureDir(absDir: string): void {
  try {
    fs.mkdirSync(absDir, true);
  } catch (e) {
    // 目录已存在时会抛，忽略；其它原因（权限等）交给下面的 stat 校验去发现
  }
  try {
    fs.statSync(absDir);
  } catch (e) {
    throw new Error(`创建照片目录失败：${absDir}（${(e as Error).message}）`);
  }
}

const CHUNK = 64 * 1024;

/**
 * 把相机返回的 URI 复制进沙箱（防临时授权过期）：系统复制优先，失败再手动分块复制。
 * 下面三个复制相关的函数都 `export` 出来，是为了能在离线环境用假的 fileIo 直接把这段
 * 复制逻辑跑一遍（真机上的媒体 URI 行为没法在本地复现，只能靠假实现覆盖各种边界）。
 */
export function copyFile(srcUri: string, absPath: string): void {
  let firstErr = '';
  try {
    fs.copyFileSync(srcUri, absPath);
    if (fs.statSync(absPath).size > 0) {
      return;
    }
    firstErr = '系统复制得到的文件是 0 字节';
  } catch (e) {
    firstErr = (e as Error).message;
  }
  try {
    copyByChunks(srcUri, absPath);
  } catch (e) {
    throw new Error(`复制照片失败（系统复制：${firstErr}；分块读取：${(e as Error).message}）`);
  }
}

/** 手写复制：固定块顺序读满（不依赖文件大小），写完校验落盘字节数 */
export function copyByChunks(srcUri: string, absPath: string): void {
  const src = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
  let data: Uint8Array;
  try {
    data = readAll(src.fd);
  } finally {
    fs.closeSync(src);
  }
  if (data.length === 0) {
    throw new Error('读出来是 0 字节');
  }
  const dst = fs.openSync(absPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    // 每次只把「还没写的那一段」交给 writeSync，且不传 offset：
    // WriteOptions.offset 到底是文件位置还是缓冲区位置，语义上两说（单次全量写时两种解释结果相同，
    // 一旦发生部分写就会写错位置）。显式切片 + 不传 offset，在任何一种解释下都正确。
    let written = 0;
    while (written < data.length) {
      // 第一轮是常见情况（一次写完），直接用原缓冲区、不再复制一份几 MB 的照片
      const remain: ArrayBuffer = written === 0
        ? (data.buffer as ArrayBuffer)
        : (data.buffer.slice(written, data.length) as ArrayBuffer);
      const n = fs.writeSync(dst.fd, remain);
      if (n <= 0) {
        break;
      }
      written += n;
    }
    if (written < data.length) {
      throw new Error(`只写入 ${written}/${data.length} 字节`);
    }
  } finally {
    fs.closeSync(dst);
  }
  const size: number = fs.statSync(absPath).size;
  if (size !== data.length) {
    throw new Error(`落盘大小不对：${size}/${data.length}`);
  }
}

/** 从当前文件位置顺序读满，读到 0 字节为止 */
export function readAll(fd: number): Uint8Array {
  let cap = CHUNK * 8;
  let out = new Uint8Array(cap);
  let total = 0;
  while (true) {
    if (total + CHUNK > cap) {
      cap = cap * 2;
      const bigger = new Uint8Array(cap);
      for (let i = 0; i < total; i++) {
        bigger[i] = out[i];
      }
      out = bigger;
    }
    const buf = new ArrayBuffer(CHUNK);
    const n = fs.readSync(fd, buf);
    if (n <= 0) {
      break;
    }
    const view = new Uint8Array(buf, 0, n);
    for (let i = 0; i < n; i++) {
      out[total + i] = view[i];
    }
    total += n;
  }
  const exact = new Uint8Array(total);
  for (let i = 0; i < total; i++) {
    exact[i] = out[i];
  }
  return exact;
}

/**
 * 读一个**自己的沙箱文件**（大小可信）—— 一次分配、一次读取，不做倍增拷贝。
 *
 * ⚠️ 2026-09-30 新增。起因是一次真机 appfreeze 堆栈：
 *   `BCStub_... → readAll(TrackMedia.ets:213) → readFileBytes → writeZip → stageForUpload`，
 * 主线程 5.3 s 全烧在 readAll 上。readAll 为了「不赌文件大小」做了三层拷贝
 * （倍增搬运 + 每块搬运 + 收尾再搬一次），一张 4 MB 照片就要搬 1500 万个元素，
 * 而它在字节码解释器里跑（堆栈里的 BCStub/RTStub）—— 每张照片接近 1 秒。
 *
 * 本函数的前提是**大小来自 statSync 且文件是我们自己写的**：一次 `readSync` 读满即可。
 * 万一大小报 0 或一次没读满（罕见），退回通用读法 readAll，**不赌**。
 */
export function readFileExact(absPath: string): Uint8Array {
  let size = 0;
  try {
    size = fs.statSync(absPath).size;
  } catch (e) {
    size = 0;
  }
  const f = fs.openSync(absPath, fs.OpenMode.READ_ONLY);
  try {
    // 大小不可信（报 0）→ 退回通用读法
    if (size <= 0) {
      return readAll(f.fd);
    }
    // 先赌一次「一次读满」（常规文件在正常实现下就是这样）—— 命中则**零拷贝**
    const first = new ArrayBuffer(size);
    const n0 = fs.readSync(f.fd, first);
    if (n0 <= 0) {
      return new Uint8Array(0);
    }
    if (n0 === size) {
      return new Uint8Array(first);
    }
    // 有的实现一次只肯读一部分：把已读到的搬进目标缓冲，再分块补齐。
    // 文件位置已经往后走了，**不用重开**，直接从当前位置继续。
    const out = new Uint8Array(size);
    const v0 = new Uint8Array(first, 0, n0);
    for (let i = 0; i < n0; i++) {
      out[i] = v0[i];
    }
    let total = n0;
    while (total < size) {
      const buf = new ArrayBuffer(CHUNK);
      const n = fs.readSync(f.fd, buf);
      if (n <= 0) {
        break;
      }
      const view = new Uint8Array(buf, 0, n);
      const room = size - total;
      const take = view.length < room ? view.length : room;
      for (let i = 0; i < take; i++) {
        out[total + i] = view[i];
      }
      total += take;
    }
    if (total === size) {
      return out;
    }
    // 文件比 stat 报的短（极罕见）：按实际读到的长度裁一下，包里的长度与 CRC 都用这个值，
    // 所以包本身仍然自洽
    const exact = new Uint8Array(total);
    for (let i = 0; i < total; i++) {
      exact[i] = out[i];
    }
    return exact;
  } finally {
    fs.closeSync(f);
  }
}

/** 删除已复制的照片文件（用户放弃保存时清理） */
export function deletePhotoFile(absPath: string): void {
  try {    fs.unlinkSync(absPath);
  } catch (e) {
  }
}

/** 照片文件是否还存在（显示前兜底） */
export function photoExists(absPath: string): boolean {
  try {
    // 注意：accessSync 是**返回布尔值**的，不是靠抛异常表达「不存在」
    return fs.accessSync(absPath);
  } catch (e) {
    return false;
  }
}

/** 沙箱相对路径 → 可直接交给 Image() 的 file:// URL */
export function photoUrl(relPath: string): string {
  const dir = Ctx.ui ? Ctx.ui.filesDir : '';
  return `file://${dir}/${relPath}`;
}
