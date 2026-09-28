import { util } from '@kit.ArkTS';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { PhotoKind, Track, TrackPhoto, TrackPoint, TrackTag } from '../data/Entities';
import { buildZip, ZipEntry } from './ZipWriter';
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
  latitude?: number;
  longitude?: number;
  altitude?: number;
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
}

/**
 * 轨迹数据导出：
 * 打包为 zip（每条轨迹一个 JSON + photos/ 下照片原图 + manifest.json + gallery.html 照片索引），
 * 通过系统文件保存对话框让用户选择保存位置（默认 Downloads）。
 * AI 可直接读 JSON（含标签/照片元数据与相对路径）并对照照片原图；
 * 人工则可以解压后双击 gallery.html 逐张核对照片、位置、朝向与备注。
 */
/** 打包结果：zip 字节 + 建议文件名（导出到手机与上传到云端共用） */
export interface ExportPackage {
  name: string;
  data: ArrayBuffer;
}

/** 已经落进 cacheDir 的待上传包（uploadFile 只认 internal://cache/ 下的文件） */
export interface StagedUpload {
  name: string;
  cachePath: string;
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

  /** 打包成 zip 字节（不落盘、不弹对话框）：「存到手机」与「上传到云端」都从这里拿数据 */
  private static async build(tracks: Track[], areaId: number, areaName: string,
    nameTag: string): Promise<ExportPackage> {
    const ctx = Ctx.ui;
    if (!ctx) {
      throw new Error('应用未就绪，稍后再试');
    }
    const filesDir = ctx.filesDir;
    const encoder = new util.TextEncoder();
    const entries: ZipEntry[] = [];
    const manifestTracks: ManifestTrack[] = [];
    const galleryTracks: GalleryTrack[] = [];
    let totalPhotos = 0;

    for (const t of tracks) {
      const pts: TrackPoint[] = await Store.listPoints(t.id);
      const tags: TrackTag[] = await Store.listTrackTags(t.id);
      const photos: TrackPhoto[] = await Store.listTrackPhotos(t.id);

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
        return {
          timeMs: g.timeMs,
          tagType: g.tagType,
          note: g.note,
          floor: g.floor,
          latitude: g.latitude,
          longitude: g.longitude,
          altitude: g.altitude,
          headingDeg: g.headingDeg
        } as ExportTag;
      });

      // 先读照片原图进包，缺失的标记 fileMissing（在 JSON 与索引页里体现）
      const photoOk: boolean[] = [];
      for (const ph of photos) {
        const abs = `${filesDir}/${ph.filePath}`;
        let ok = false;
        try {
          const stat = fs.statSync(abs);
          const f = fs.openSync(abs, fs.OpenMode.READ_ONLY);
          const buf = new ArrayBuffer(stat.size);
          fs.readSync(f.fd, buf);
          fs.closeSync(f);
          entries.push({
            name: ph.filePath,
            data: new Uint8Array(buf)
          } as ZipEntry);
          ok = true;
        } catch (e) {
        }
        photoOk.push(ok);
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
      entries.push({
        name: trackFile,
        data: encoder.encodeInto(JSON.stringify(trackJson))
      } as ZipEntry);

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
        photoMissing: photoOk
      } as GalleryTrack);
      totalPhotos += photos.length;
    }

    // 照片索引页：解压后用浏览器打开即可逐张核对照片、位置、朝向、备注
    entries.push({
      name: 'gallery.html',
      data: encoder.encodeInto(Exporter.buildGalleryHtml(areaName, areaId, galleryTracks, totalPhotos))
    } as ZipEntry);

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
    entries.push({
      name: 'manifest.json',
      data: encoder.encodeInto(JSON.stringify(manifest))
    } as ZipEntry);

    const zipBuffer: ArrayBuffer = buildZip(entries);
    const d = new Date();
    const stamp =
      `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}_${pad2(d.getHours())}${pad2(d.getMinutes())}`;
    const zipName = `${safeFileName(`${areaName}${nameTag}`)}_${stamp}.zip`;
    return { name: zipName, data: zipBuffer } as ExportPackage;
  }

  /** 打包后走系统保存对话框存到手机（区域页「导出所选」用的就是这条） */
  private static async pack(tracks: Track[], areaId: number, areaName: string,
    nameTag: string): Promise<string> {
    const ctx = Ctx.ui;
    if (!ctx) {
      throw new Error('应用未就绪，稍后再试');
    }
    const pkg: ExportPackage = await Exporter.build(tracks, areaId, areaName, nameTag);

    const docPicker = new picker.DocumentViewPicker(ctx);
    const opt = new picker.DocumentSaveOptions();
    opt.newFileNames = [pkg.name];
    const uris: string[] = await docPicker.save(opt);
    const uri = uris[0];
    const dst = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    fs.writeSync(dst.fd, pkg.data);
    fs.closeSync(dst);
    return pkg.name;
  }

  /**
   * 打包并写进应用缓存目录，供「上传到云端」使用。
   *
   * ⚠️ request.uploadFile 只接受 `internal://cache/<文件名>` 形式的 uri，
   * 也就是文件必须**直接放在 cacheDir 下**（不能放子目录、也不能用 filesDir），
   * 所以这里刻意不建子目录，直接用 cacheDir 根。
   */
  static async stageForUpload(trackIds: number[], areaId: number,
    areaName: string): Promise<StagedUpload> {
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
    const pkg: ExportPackage = await Exporter.build(picked, areaId, areaName,
      `_所选${picked.length}条`);
    const cachePath = `${ctx.cacheDir}/${pkg.name}`;
    const f = fs.openSync(cachePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(f.fd, pkg.data);
    fs.closeSync(f);
    return { name: pkg.name, cachePath: cachePath } as StagedUpload;
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
          out.push(`<dt>时间</dt><dd>${fmtFullTime(g.timeMs)}</dd>`);
          out.push(`<dt>经纬度</dt><dd>${coordText(g.latitude, g.longitude)}</dd>`);
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
