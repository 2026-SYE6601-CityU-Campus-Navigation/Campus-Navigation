import { util } from '@kit.ArkTS';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { Area, PhotoKind, Track, TrackPhoto, TrackPoint, TrackTag } from '../data/Entities';
import { effectiveAreaId } from './RoomPlan';
import { ZipStream, crc32, writeAllTo } from './ZipWriter';
import { readFileExact } from '../sensors/TrackMedia';
import { Ctx, compassDir, coordText, fmtFullTime, pad2, safeFileName } from './Utils';

/** 导出 JSON 的采样点结构（可选字段为 undefined 时 JSON.stringify 自动省略） */
interface ExportPoint {
  timeMs: number;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  accuracy?: number;
  pressureHpa?: number;
  magneticX?: number;
  magneticY?: number;
  magneticZ?: number;
  headingDeg?: number;
  wifiCount: number;
  wifiTop: string;
}

interface ExportTag {
  timeMs: number;
  tagType: string;
  note: string;
  /** 手填楼层（空字符串 = 未填） */
  floor: string;
  /** 节点所属建筑区域名（2026-09-29 新增，跨楼轨迹才非空区别）；
   *  空字符串 = 节点没写区域且轨迹自身也没区域。属增量字段，version 不变，旧的消费脚本不受影响 */
  area: string;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  /**
   * 打这个节点时的定位精度（米）—— 2026-09-29 新增（第二十五轮）。
   * 与采样点的 accuracy 同名字段对齐；**旧包没有这个字段**，所以消费脚本要按「缺省 = 没记精度、
   * 不算差」处理。做航位推算时，只有精度在门限内的节点才能当锚点。
   */
  accuracy?: number;
  /** 打这个节点时的气压（2026-09-29 新增，与采样点同名字段对齐；旧包没有这个字段） */
  pressureHpa?: number;
  headingDeg?: number;
}

interface ExportPhoto {
  timeMs: number;
  file: string;
  note: string;
  /** 'node' 节点照（属于某个节点）/ 'scenery' 风景照 */
  kind: string;
  /** 节点照所属节点在 tags[] 里的下标；风景照为 undefined */
  tagIndex?: number;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  headingDeg?: number;
  fileMissing?: boolean;
}

interface ManifestTrack {
  file: string;
  name: string;
  startedAt: number;
  pointCount: number;
  /** 节点数（原「标签」，2026-09-28 起节点 = 标记 + 照片） */
  nodeCount: number;
  photoCount: number;
  sceneryPhotoCount: number;
}

interface ExportAreaInfo {
  id: number | null;
  name: string;
}

interface ExportTrackJson {
  /** 2：tags 语义变为「节点」，photos 增加 kind/tagIndex */
  version: number;
  name: string;
  area: string;
  startedAt: number;
  endedAt?: number;
  pointCount: number;
  points: ExportPoint[];
  /** 节点列表（标记 + 定位 + 朝向），节点照在 photos[] 里以 tagIndex 指向本数组 */
  tags: ExportTag[];
  photos: ExportPhoto[];
}

interface ExportManifest {
  app: string;
  exportedAt: number;
  area: ExportAreaInfo;
  trackCount: number;
  /** 包内照片索引页（解压后用浏览器打开） */
  gallery: string;
  tracks: ManifestTrack[];
}

/** 生成 gallery.html 时用的每轨汇总 */
interface GalleryTrack {
  name: string;
  jsonFile: string;
  startedAt: number;
  pointCount: number;
  tags: TrackTag[];
  photos: TrackPhoto[];
  photoMissing: boolean[];
  /** 区域清单与轨迹自身区域：用来算每个节点的「所在建筑」 */
  areas: Area[];
  trackAreaId: number;
}

/**
 * 轨迹数据导出：
 * 打包为 zip（每条轨迹一个 JSON + photos/ 下照片原图 + manifest.json + gallery.html 照片索引），
 * 通过系统文件保存对话框让用户选择保存位置（默认 Downloads）。
 * AI 可直接读 JSON（含标签/照片元数据与相对路径）并对照照片原图；
 * 人工则可以解压后双击 gallery.html 逐张核对照片、位置、朝向与备注。
 */
/**
 * 打包进度：既是给用户看的反馈，也是**打包中途出问题时的唯一线索**
 * （闪退时 toast 带不走信息，但界面上的最后一条消息和 hilog 能说清崩在哪一步、包多大）。
 */
export interface PackProgress {
  /** 正在处理第几个条目（**1 起**，配合 note 读作「第 3/8 个：photos/…」）/ 总条目数 */
  done: number;
  total: number;
  /** 已写出的字节数 */
  bytes: number;
  /** 预计总字节数（照片大小已知，JSON 部分很小，估得够准） */
  bytesTotal: number;
  /** 正在处理的条目名（照片相对路径或 JSON 文件名） */
  note: string;
}

/** 已经落进 cacheDir 的待上传包（uploadFile 只认 internal://cache/ 下的文件） */
export interface StagedUpload {
  name: string;
  cachePath: string;
  /** 实际落盘字节数（界面拿它显示这个包多大） */
  bytes: number;
}

/**
 * 一个打包条目：包内路径 + 内容来源。
 * 照片**只记绝对路径**，字节在读的那一刻才产生 —— 这是这一轮治闪退的关键
 * （老实现把全部照片读进内存、再拼一份整包字节，一个 5 张照片的包就有 17.5 MB，勾几条就崩）。
 */
interface PackJob {
  name: string;
  /** 内存里的内容（轨迹 JSON / gallery.html / manifest.json） */
  data?: Uint8Array;
  /** 照片原图的绝对路径（与 data 二选一） */
  absPath?: string;
  size: number;
}

export class Exporter {
  /**
   * 导出整个区域的全部轨迹。
   * 界面已不再直接调用（区域页删掉了重复的「导出」按钮，统一走「选择导出 → 全选」，
   * 效果等价）；保留这个 API 供以后需要一键整区导出时复用，`pack()` 也是两者共用的。
   */
  static async exportAreaZip(areaId: number, areaName: string): Promise<string> {
    const tracks: Track[] = await Store.listTracksInArea(areaId);
    if (tracks.length === 0) {
      throw new Error('该区域还没有轨迹，无法导出');
    }
    return Exporter.pack(tracks, areaId, areaName, '');
  }

  /** 只导出勾选的若干条轨迹（区域页「选择导出」用） */
  static async exportTracksZip(trackIds: number[], areaId: number, areaName: string): Promise<string> {
    if (trackIds.length === 0) {
      throw new Error('请先勾选要导出的轨迹');
    }
    const all: Track[] = await Store.listTracksInArea(areaId);
    const picked: Track[] = all.filter((t: Track) => {
      return trackIds.indexOf(t.id) >= 0;
    });
    if (picked.length === 0) {
      throw new Error('勾选的轨迹已不存在，请刷新后重试');
    }
    return Exporter.pack(picked, areaId, areaName, `_所选${picked.length}条`);
  }

  /**
   * 收集要打进包的东西：**只算元数据与照片大小（stat），不读照片字节**。
   * 分成 collect + writeZip 两步，是因为「保存到手机」这条路径要用系统对话框先拿到目标 URI
   * （而对话框又要求先给文件名），所以包名与内容要能在写之前定下来。
   */
  private static async collect(tracks: Track[], areaId: number, areaName: string): Promise<PackJob[]> {
    const ctx = Ctx.ui;
    if (!ctx) {
      throw new Error('应用未就绪，稍后再试');
    }
    const filesDir = ctx.filesDir;
    const encoder = new util.TextEncoder();
    const jobs: PackJob[] = [];
    const manifestTracks: ManifestTrack[] = [];
    const galleryTracks: GalleryTrack[] = [];
    let totalPhotos = 0;
    // 区域清单：把节点的 areaId 翻成建筑名写进导出数据与照片索引页
    const areas: Area[] = await Store.listAreas();

    for (const t of tracks) {
      const pts: TrackPoint[] = await Store.listPoints(t.id);
      const tags: TrackTag[] = await Store.listTrackTags(t.id);
      const photos: TrackPhoto[] = await Store.listTrackPhotos(t.id);
      const trackAreaId: number = t.areaId === undefined ? UNASSIGNED_AREA_ID : t.areaId;

      const ep: ExportPoint[] = pts.map((p: TrackPoint) => {
        return {
          timeMs: p.timeMs,
          latitude: p.latitude,
          longitude: p.longitude,
          altitude: p.altitude,
          accuracy: p.accuracy,
          pressureHpa: p.pressureHpa,
          magneticX: p.magneticX,
          magneticY: p.magneticY,
          magneticZ: p.magneticZ,
          headingDeg: p.headingDeg,
          wifiCount: p.wifiCount,
          wifiTop: p.wifiTop
        } as ExportPoint;
      });
      const et: ExportTag[] = tags.map((g: TrackTag) => {
        // 节点所属建筑（节点自己写的区域优先，没写就沿用轨迹的区域）
        const nodeAreaId: number = effectiveAreaId(g, trackAreaId);
        let areaName: string = '';
        for (const a of areas) {
          if (a.id === nodeAreaId) {
            areaName = a.name;
            break;
          }
        }
        return {
          timeMs: g.timeMs,
          tagType: g.tagType,
          note: g.note,
          floor: g.floor,
          area: areaName,
          latitude: g.latitude,
          longitude: g.longitude,
          altitude: g.altitude,
          accuracy: g.accuracy,
          pressureHpa: g.pressureHpa,
          headingDeg: g.headingDeg
        } as ExportTag;
      });

      // 照片：这里**只 stat 出大小**（不读字节），真正的读与写交给 writeZip 一张一张地做。
      // 缺失的仍然标记 fileMissing（在 JSON 与索引页里体现），只是不再尝试把内容读进来。
      const photoOk: boolean[] = [];
      for (const ph of photos) {
        const abs = `${filesDir}/${ph.filePath}`;
        let size = -1;
        try {
          size = fs.statSync(abs).size;
        } catch (e) {
          size = -1;
        }
        const ok: boolean = size > 0;
        photoOk.push(ok);
        if (ok) {
          jobs.push({ name: ph.filePath, absPath: abs, size: size } as PackJob);
        }
      }
      const eph: ExportPhoto[] = photos.map((ph: TrackPhoto, i: number) => {
        // 节点照用 tagIndex 指向 tags[] 里的节点（比对内部 id 更稳定，便于外部消费）
        let tagIndex: number | undefined = undefined;
        if (ph.tagId !== undefined) {
          const idx = tags.findIndex((g: TrackTag) => g.id === ph.tagId);
          if (idx >= 0) {
            tagIndex = idx;
          }
        }
        return {
          timeMs: ph.timeMs,
          file: ph.filePath,
          note: ph.note,
          kind: ph.kind,
          tagIndex: tagIndex,
          latitude: ph.latitude,
          longitude: ph.longitude,
          altitude: ph.altitude,
          headingDeg: ph.headingDeg,
          fileMissing: !photoOk[i]
        } as ExportPhoto;
      });

      let sceneryCount = 0;
      for (const ph of photos) {
        if (ph.kind === PhotoKind.SCENERY) {
          sceneryCount++;
        }
      }

      const trackJson: ExportTrackJson = {
        version: 2,
        name: t.name,
        area: areaName,
        startedAt: t.startedAt,
        endedAt: t.endedAt,
        pointCount: t.pointCount,
        points: ep,
        tags: et,
        photos: eph
      };
      const trackFile = `track_${t.id}_${safeFileName(t.name)}.json`;
      const trackBytes: Uint8Array = encoder.encodeInto(JSON.stringify(trackJson));
      jobs.push({ name: trackFile, data: trackBytes, size: trackBytes.length } as PackJob);

      manifestTracks.push({
        file: trackFile,
        name: t.name,
        startedAt: t.startedAt,
        pointCount: t.pointCount,
        nodeCount: tags.length,
        photoCount: photos.length,
        sceneryPhotoCount: sceneryCount
      } as ManifestTrack);
      galleryTracks.push({
        name: t.name,
        jsonFile: trackFile,
        startedAt: t.startedAt,
        pointCount: t.pointCount,
        tags: tags,
        photos: photos,
        photoMissing: photoOk,
        areas: areas,
        trackAreaId: trackAreaId
      } as GalleryTrack);
      totalPhotos += photos.length;
    }

    // 照片索引页：解压后用浏览器打开即可逐张核对照片、位置、朝向、备注
    const galleryBytes: Uint8Array =
      encoder.encodeInto(Exporter.buildGalleryHtml(areaName, areaId, galleryTracks, totalPhotos));
    jobs.push({ name: 'gallery.html', data: galleryBytes, size: galleryBytes.length } as PackJob);

    const areaInfo: ExportAreaInfo = {
      id: areaId === UNASSIGNED_AREA_ID ? null : areaId,
      name: areaName
    };
    const manifest: ExportManifest = {
      app: 'RoomMarker',
      exportedAt: Date.now(),
      area: areaInfo,
      trackCount: tracks.length,
      gallery: 'gallery.html',
      tracks: manifestTracks
    };
    const manifestBytes: Uint8Array = encoder.encodeInto(JSON.stringify(manifest));
    jobs.push({ name: 'manifest.json', data: manifestBytes, size: manifestBytes.length } as PackJob);

    return jobs;
  }

  /** 建议的包名。**要在开始写之前就定下来** —— 系统保存对话框得先知道文件名 */
  private static zipName(areaName: string, nameTag: string): string {
    const d = new Date();
    const stamp =
      `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}_${pad2(d.getHours())}${pad2(d.getMinutes())}`;
    return `${safeFileName(`${areaName}${nameTag}`)}_${stamp}.zip`;
  }

  /**
   * 写满一段字节（实现搬到 ZipWriter.writeAllTo 了，这样那段逻辑能在离线沙箱里
   * 用一个「只肯写几个字节」的假 sink 真跑一遍）。
   * 这里只负责把 writeSync 包成 sink：**不传 WriteOptions.offset** —— 它到底是文件位置
   * 还是缓冲区位置语义两说，显式切片在任何一种解释下都对（与 TrackMedia.copyByChunks 同一套做法）。
   */
  private static writeAll(fd: number, data: Uint8Array): void {
    writeAllTo((bytes: ArrayBuffer): number => fs.writeSync(fd, bytes), data);
  }

  /**
   * 读一张照片进内存（一次只读一个，立刻写出去）。
   * **必须走 `readFileExact`**：它按 statSync 的大小一次读满，不做倍增拷贝 ——
   * 真机 appfreeze 的堆栈就指在老的 `readAll` 上（一层层搬运，一张 4 MB 照片搬 1500 万个元素）。
   */
  private static readPhotoBytes(absPath: string): Uint8Array {
    return readFileExact(absPath);
  }

  /**
   * 把主线程让出来一次（0 ms 定时器）。
   *
   * ⚠️ **这一步不是可选的。** 打包是重活（读 17.5 MB + 逐字节算 CRC + 写出去）。全同步跑完
   * 再返回的话主线程会连续阻塞十几秒，系统的看门狗（hicollie）在 6 秒时就判定
   * **THREAD_BLOCK_6S** 把应用冻住 —— 真机 appfreeze 日志里 `Reason:` 就是这个，堆栈正好指在
   * `readAll → readFileBytes → writeZip → stageForUpload` 上（见开发日志第二十七轮）。
   * 每个条目之间让一次，事件队列才有机会排空、看门狗的计时器才会重置；
   * 队列里排队的 vSync 任务是 VIP 优先级，会先于这个 0 ms 定时器被执行，所以界面上的
   * 进度也真的能画出来（全同步的话 @State 改了也不会重绘）。
   */
  private static breathe(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, 0);
    });
  }

  /**
   * 把任务表**流式**写进目标文件，返回写出的字节数。
   *
   * 内存峰值 = 一张照片；每个条目之间让出主线程（见 breathe 的说明）。
   * 老实现是「全部照片读进内存 + 再拼一份整包字节」，一个 5 张照片的轨迹包就有 17.5 MB，
   * 勾几条轨迹就是两三百 MB（见开发日志第二十六轮）。
   *
   * 半截失败会把目标文件删掉：留一个半截的包，下次很容易被当成「上次成功的包」。
   */
  private static async writeZip(jobs: PackJob[], dstUri: string,
    onProgress: ((p: PackProgress) => void) | undefined): Promise<number> {
    const encoder = new util.TextEncoder();
    const now: number = Date.now();
    // 预估总字节：照片大小是 stat 出来的真实值，文件名与头几十字节，估得够准
    let bytesTotal = 0;
    for (const j of jobs) {
      bytesTotal += j.size + 30 + j.name.length * 3 + 46;
    }
    hilog.info(0x0000, 'RoomMarker', '打包开始：%{public}d 个条目，约 %{public}d 字节',
      jobs.length, bytesTotal);

    const dst = fs.openSync(dstUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let total = 0;
    try {
      const z: ZipStream = new ZipStream();
      let done = 0;
      for (const j of jobs) {
        // 先报再干：万一这一步崩了，界面上留下的最后一条消息就是正在处理的这个文件
        if (onProgress) {
          onProgress({
            done: done + 1, total: jobs.length, bytes: z.writtenBytes(),
            bytesTotal: bytesTotal, note: j.name
          } as PackProgress);
          // 让出主线程，界面才有机会把上面这条进度画出来（也顺手重置看门狗计时）
          await Exporter.breathe();
        }
        const data: Uint8Array = j.absPath !== undefined
          ? Exporter.readPhotoBytes(j.absPath)
          : (j.data as Uint8Array);
        const nb: Uint8Array = encoder.encodeInto(j.name);
        Exporter.writeAll(dst.fd, z.entryHeader(nb, data.length, crc32(data), now));
        Exporter.writeAll(dst.fd, data);
        hilog.info(0x0000, 'RoomMarker', '打包 %{public}d/%{public}d %{public}s (%{public}d 字节)',
          done + 1, jobs.length, j.name, data.length);
        done++;
      }
      Exporter.writeAll(dst.fd, z.finish());
      total = z.totalBytes();
    } catch (e) {
      try {
        fs.unlinkSync(dstUri);
      } catch (err) {
      }
      throw e as Error;
    } finally {
      fs.closeSync(dst);
    }
    // 对账：落盘大小必须等于流自己算出来的总长。缓存目录里 stat 一定可信；
    // 而「保存到手机」那条走的是系统文档 URI，stat 有可能不被支持 —— 那就跳过校验，
    // **绝不能因为校验做不了就把一次成功的导出报成失败**。
    let size = -1;
    try {
      size = fs.statSync(dstUri).size;
    } catch (e) {
      size = -1;
    }
    if (size >= 0 && size !== total) {
      throw new Error(`打包落盘大小不对：${size}/${total} 字节`);
    }
    hilog.info(0x0000, 'RoomMarker', '打包完成：%{public}d 字节', size >= 0 ? size : total);
    return size >= 0 ? size : total;
  }

  /** 打包后走系统保存对话框存到手机（区域页「导出所选」用的就是这条） */
  private static async pack(tracks: Track[], areaId: number, areaName: string,
    nameTag: string): Promise<string> {
    const ctx = Ctx.ui;
    if (!ctx) {
      throw new Error('应用未就绪，稍后再试');
    }
    const zipName: string = Exporter.zipName(areaName, nameTag);
    const jobs: PackJob[] = await Exporter.collect(tracks, areaId, areaName);

    const docPicker = new picker.DocumentViewPicker(ctx);
    const opt = new picker.DocumentSaveOptions();
    opt.newFileNames = [zipName];
    const uris: string[] = await docPicker.save(opt);
    if (uris.length === 0) {
      throw new Error('没有选择保存位置，导出已取消');
    }
    await Exporter.writeZip(jobs, uris[0], undefined);
    return zipName;
  }

  /**
   * 打包并写进应用缓存目录，供「上传到云端」使用。
   *
   * ⚠️ request.uploadFile 只接受 `internal://cache/<文件名>` 形式的 uri，
   * 也就是文件必须**直接放在 cacheDir 下**（不能放子目录、也不能用 filesDir），
   * 所以这里刻意不建子目录，直接用 cacheDir 根。
   */
  static async stageForUpload(trackIds: number[], areaId: number,
    areaName: string, onProgress: ((p: PackProgress) => void) | undefined): Promise<StagedUpload> {
    if (trackIds.length === 0) {
      throw new Error('请先勾选要上传的轨迹');
    }
    const all: Track[] = await Store.listTracksInArea(areaId);
    const picked: Track[] = all.filter((t: Track) => {
      return trackIds.indexOf(t.id) >= 0;
    });
    if (picked.length === 0) {
      throw new Error('勾选的轨迹已不存在，请刷新后重试');
    }
    const ctx = Ctx.ui;
    if (!ctx) {
      throw new Error('应用未就绪，稍后再试');
    }
    const zipName: string = Exporter.zipName(areaName, `_所选${picked.length}条`);
    const jobs: PackJob[] = await Exporter.collect(picked, areaId, areaName);
    const cachePath = `${ctx.cacheDir}/${zipName}`;
    const bytes: number = await Exporter.writeZip(jobs, cachePath, onProgress);
    return { name: zipName, cachePath: cachePath, bytes: bytes } as StagedUpload;
  }

  /** 上传结束后清掉缓存里的临时包（源数据还在库里，需要时可重新打包，不会丢东西） */
  static discardStaged(staged: StagedUpload): void {
    try {
      fs.unlinkSync(staged.cachePath);
    } catch (e) {
    }
  }

  /** HTML 转义，避免备注/名称里的 < > & " 破坏索引页 */
  private static esc(s: string): string {
    return s.replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /** 节点所属建筑区域名（照片索引页用；没有区域就显示「未分区」） */
  private static nodeAreaName(t: GalleryTrack, g: TrackTag): string {
    const id: number = effectiveAreaId(g, t.trackAreaId);
    if (id <= 0) {
      return '未分区';
    }
    for (const a of t.areas) {
      if (a.id === id) {
        return a.name;
      }
    }
    return `区域 #${id}`;
  }

  private static buildGalleryHtml(areaName: string, areaId: number, tracks: GalleryTrack[],
    totalPhotos: number): string {
    const out: string[] = [];
    out.push('<!DOCTYPE html>');
    out.push('<html lang="zh-CN"><head><meta charset="utf-8">');
    out.push('<meta name="viewport" content="width=device-width,initial-scale=1">');
    out.push(`<title>${Exporter.esc(areaName)} 照片索引</title>`);
    out.push('<style>');
    out.push('body{font-family:-apple-system,"Microsoft YaHei",sans-serif;margin:0;padding:24px;background:#f6f7f9;color:#1a1a1a}');
    out.push('h1{font-size:22px;margin:0 0 8px}');
    out.push('h2{font-size:17px;margin:30px 0 4px;border-left:4px solid #0A59F7;padding-left:10px}');
    out.push('h3{font-size:14px;margin:16px 0 6px;color:#333}');
    out.push('.meta{color:#666;font-size:13px;margin:0 0 4px}');
    out.push('.tip{color:#555;font-size:12px;background:#eef3ff;border-radius:6px;padding:8px 10px;margin:8px 0 0}');
    out.push('.sub{font-weight:400;color:#888;font-size:12px;margin-left:8px}');
    out.push('.grid{display:flex;flex-wrap:wrap;gap:14px;margin-top:10px}');
    out.push('.card{background:#fff;border:1px solid #e3e3e6;border-radius:10px;margin:0;width:290px;overflow:hidden}');
    out.push('.card img{display:block;width:100%;height:200px;object-fit:cover;background:#eee}');
    out.push('.none{height:200px;display:flex;align-items:center;justify-content:center;color:#999;font-size:12px;background:#f0f0f0}');
    out.push('figcaption{padding:10px 12px 12px}');
    out.push('.seq{font-size:11px;color:#0A59F7;font-weight:600}');
    out.push('.note{font-size:14px;margin:2px 0 8px;line-height:1.4}');
    out.push('dl{display:grid;grid-template-columns:64px 1fr;gap:3px 8px;margin:0;font-size:12px}');
    out.push('dt{color:#888}dd{margin:0;word-break:break-all}');
    out.push('code{font-family:Consolas,monospace;font-size:11px;color:#555}');
    out.push('ul{margin:4px 0 0;padding-left:20px;font-size:13px}li{margin:3px 0}');
    out.push('.p{color:#888;font-size:11px}');
    out.push('</style></head><body>');
    out.push('<h1>RoomMarker 照片索引</h1>');
    const areaLabel = areaId === UNASSIGNED_AREA_ID ? `${areaName}（未分区）` : areaName;
    out.push(`<p class="meta">区域：${Exporter.esc(areaLabel)} · 轨迹 ${tracks.length} 条 · 照片 ${totalPhotos} 张 · 导出时间 ${fmtFullTime(Date.now())}</p>`);
    out.push('<p class="tip">先把 zip 解压到同一个文件夹，再双击打开本文件，缩略图才会显示（图片用相对路径引用）。'
      + '每张照片下方列出的是采集时关联的真实参数：时间、经纬度、高度、手机朝向（度数 + 中文方位）与沙箱相对路径。'
      + '<b>节点</b>=标记+照片，是路引的关键信息；<b>风景照</b>只作宣传美化用，不参与节点。'
      + '路径与各轨迹 JSON 里的 photos[].file 一致（JSON 里 kind 字段区分 node/scenery），便于人工核对，也便于 AI 对照图片生成路引。</p>');

    for (let i = 0; i < tracks.length; i++) {
      const t = tracks[i];
      out.push('<section>');
      out.push(`<h2>${i + 1}. ${Exporter.esc(t.name)}<span class="sub">${fmtFullTime(t.startedAt)} · ${t.pointCount} 个采样点 · 节点 ${t.tags.length} 个 · 照片 ${t.photos.length} 张</span></h2>`);
      out.push(`<p class="meta">数据文件：<code>${Exporter.esc(t.jsonFile)}</code></p>`);

      // 把照片归位：节点照挂到对应节点（每个节点取第一张），其余进风景照
      const photosOfTag: number[] = [];
      for (let i = 0; i < t.tags.length; i++) {
        photosOfTag.push(-1);
      }
      const sceneryIdx: number[] = [];
      for (let k = 0; k < t.photos.length; k++) {
        const ph = t.photos[k];
        let placed = false;
        if (ph.kind === PhotoKind.NODE && ph.tagId !== undefined) {
          const idx = t.tags.findIndex((g: TrackTag) => g.id === ph.tagId);
          if (idx >= 0 && photosOfTag[idx] < 0) {
            photosOfTag[idx] = k;
            placed = true;
          }
        }
        if (!placed) {
          sceneryIdx.push(k);
        }
      }

      // 节点：标记 + 照片（照片是节点信息的一部分）
      if (t.tags.length > 0) {
        out.push(`<h3>节点（${t.tags.length}）· 标记 + 照片</h3>`);
        out.push('<div class="grid">');
        for (let i = 0; i < t.tags.length; i++) {
          const g = t.tags[i];
          const k = photosOfTag[i];
          out.push('<figure class="card">');
          if (k < 0) {
            out.push('<div class="none">此节点没有照片（升级前的旧标签）</div>');
          } else {
            const ph: TrackPhoto = t.photos[k];
            const fileOk = t.photoMissing.length > k ? !t.photoMissing[k] : true;
            if (fileOk) {
              out.push(`<img src="${Exporter.esc(ph.filePath)}" alt="${Exporter.esc(g.tagType)}" loading="lazy">`);
            } else {
              out.push('<div class="none">图片文件缺失</div>');
            }
          }
          out.push('<figcaption>');
          out.push(`<div class="seq">节点 ${i + 1} · ${Exporter.esc(g.tagType)}</div>`);
          out.push(`<div class="note">${g.note.length > 0 ? Exporter.esc(g.note) : '（未填写备注）'}</div>`);
          out.push('<dl>');
          out.push(`<dt>楼层</dt><dd>${g.floor.length > 0 ? Exporter.esc(g.floor) : '未填写'}</dd>`);
          out.push(`<dt>区域</dt><dd>${Exporter.esc(Exporter.nodeAreaName(t, g))}</dd>`);
          out.push(`<dt>时间</dt><dd>${fmtFullTime(g.timeMs)}</dd>`);
          out.push(`<dt>经纬度</dt><dd>${coordText(g.latitude, g.longitude)}</dd>`);
          out.push(`<dt>定位精度</dt><dd>${g.accuracy !== undefined
            ? `±${g.accuracy.toFixed(0)} m${g.accuracy > 50 ? '（网络定位，不可当实测坐标）' : ''}`
            : '未记录精度（2026-09-29 之前的节点）'}</dd>`);
          out.push(`<dt>高度</dt><dd>${g.altitude !== undefined ? `${g.altitude.toFixed(1)} m` : '无海拔数据（室内 GPS 常缺失）'}</dd>`);
          out.push(`<dt>朝向</dt><dd>${g.headingDeg !== undefined ? `${g.headingDeg.toFixed(0)}° ${compassDir(g.headingDeg)}` : '无朝向数据'}</dd>`);
          if (k >= 0) {
            out.push(`<dt>照片</dt><dd><code>${Exporter.esc(t.photos[k].filePath)}</code></dd>`);
          }
          out.push('</dl>');
          out.push('</figcaption></figure>');
        }
        out.push('</div>');
      }

      // 风景照：宣传美化用，不参与节点
      if (sceneryIdx.length > 0) {
        out.push(`<h3>风景照（${sceneryIdx.length}）· 不参与节点</h3>`);
        out.push('<div class="grid">');
        for (const k of sceneryIdx) {
          const ph: TrackPhoto = t.photos[k];
          const fileOk = t.photoMissing.length > k ? !t.photoMissing[k] : true;
          const noteTxt = ph.note.length > 0 ? Exporter.esc(ph.note) : '（未填写备注）';
          const altTxt = ph.altitude !== undefined ? `${ph.altitude.toFixed(1)} m` : '无海拔数据（室内 GPS 常缺失）';
          const headTxt = ph.headingDeg !== undefined
            ? `${ph.headingDeg.toFixed(0)}° ${compassDir(ph.headingDeg)}` : '无朝向数据';
          out.push('<figure class="card">');
          if (fileOk) {
            out.push(`<img src="${Exporter.esc(ph.filePath)}" alt="风景照" loading="lazy">`);
          } else {
            out.push('<div class="none">图片文件缺失</div>');
          }
          out.push('<figcaption>');
          out.push('<div class="seq">风景照</div>');
          out.push(`<div class="note">${noteTxt}</div>`);
          out.push('<dl>');
          out.push(`<dt>时间</dt><dd>${fmtFullTime(ph.timeMs)}</dd>`);
          out.push(`<dt>经纬度</dt><dd>${coordText(ph.latitude, ph.longitude)}</dd>`);
          out.push(`<dt>高度</dt><dd>${altTxt}</dd>`);
          out.push(`<dt>朝向</dt><dd>${headTxt}</dd>`);
          out.push(`<dt>文件</dt><dd><code>${Exporter.esc(ph.filePath)}</code></dd>`);
          out.push('</dl>');
          out.push('</figcaption></figure>');
        }
        out.push('</div>');
      }

      if (t.tags.length === 0 && sceneryIdx.length === 0) {
        out.push('<p class="meta">这条轨迹没有节点，也没有照片。</p>');
      }
      out.push('</section>');
    }

    out.push('</body></html>');
    return out.join('');
  }
}
