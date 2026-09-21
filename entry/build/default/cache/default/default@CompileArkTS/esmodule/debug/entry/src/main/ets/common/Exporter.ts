import util from "@ohos:util";
import picker from "@ohos:file.picker";
import fs from "@ohos:file.fs";
import { Store, UNASSIGNED_AREA_ID } from "@bundle:com.example.roommarker/entry/ets/data/Store";
import type { Track, TrackPhoto, TrackPoint, TrackTag } from '../data/Entities';
import { buildZip } from "@bundle:com.example.roommarker/entry/ets/common/ZipWriter";
import type { ZipEntry } from "@bundle:com.example.roommarker/entry/ets/common/ZipWriter";
import { Ctx, pad2, safeFileName } from "@bundle:com.example.roommarker/entry/ets/common/Utils";
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
    latitude?: number;
    longitude?: number;
    altitude?: number;
    headingDeg?: number;
}
interface ExportPhoto {
    timeMs: number;
    file: string;
    note: string;
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
}
interface ExportAreaInfo {
    id: number | null;
    name: string;
}
interface ExportTrackJson {
    version: number;
    name: string;
    area: string;
    startedAt: number;
    endedAt?: number;
    pointCount: number;
    points: ExportPoint[];
    tags: ExportTag[];
    photos: ExportPhoto[];
}
interface ExportManifest {
    app: string;
    exportedAt: number;
    area: ExportAreaInfo;
    trackCount: number;
    tracks: ManifestTrack[];
}
/**
 * 区域数据批量导出：
 * 打包为 zip（每条轨迹一个 JSON + photos/ 下照片原图 + manifest.json 索引），
 * 通过系统文件保存对话框让用户选择保存位置（默认 Downloads）。
 * AI 可直接读 JSON（含标签/照片元数据与相对路径）并对照照片原图。
 */
export class Exporter {
    static async exportAreaZip(areaId: number, areaName: string): Promise<string> {
        const ctx = Ctx.ui;
        if (!ctx) {
            throw new Error('应用未就绪，稍后再试');
        }
        const tracks: Track[] = await Store.listTracksInArea(areaId);
        if (tracks.length === 0) {
            throw new Error('该区域还没有轨迹，无法导出');
        }
        const filesDir = ctx.filesDir;
        const encoder = new util.TextEncoder();
        const entries: ZipEntry[] = [];
        const manifestTracks: ManifestTrack[] = [];
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
                    latitude: g.latitude,
                    longitude: g.longitude,
                    altitude: g.altitude,
                    headingDeg: g.headingDeg
                } as ExportTag;
            });
            // 先读照片原图进包，缺失的标记 fileMissing（在 JSON 里体现）
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
                }
                catch (e) {
                }
                photoOk.push(ok);
            }
            const eph: ExportPhoto[] = photos.map((ph: TrackPhoto, i: number) => {
                return {
                    timeMs: ph.timeMs,
                    file: ph.filePath,
                    note: ph.note,
                    latitude: ph.latitude,
                    longitude: ph.longitude,
                    altitude: ph.altitude,
                    headingDeg: ph.headingDeg,
                    fileMissing: !photoOk[i]
                } as ExportPhoto;
            });
            const trackJson: ExportTrackJson = {
                version: 1,
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
                pointCount: t.pointCount
            } as ManifestTrack);
        }
        const areaInfo: ExportAreaInfo = {
            id: areaId === UNASSIGNED_AREA_ID ? null : areaId,
            name: areaName
        };
        const manifest: ExportManifest = {
            app: 'RoomMarker',
            exportedAt: Date.now(),
            area: areaInfo,
            trackCount: tracks.length,
            tracks: manifestTracks
        };
        entries.push({
            name: 'manifest.json',
            data: encoder.encodeInto(JSON.stringify(manifest))
        } as ZipEntry);
        const zipBuffer: ArrayBuffer = buildZip(entries);
        const d = new Date();
        const stamp = `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}_${pad2(d.getHours())}${pad2(d.getMinutes())}`;
        const zipName = `${safeFileName(areaName)}_${stamp}.zip`;
        const docPicker = new picker.DocumentViewPicker(ctx);
        const opt = new picker.DocumentSaveOptions();
        opt.newFileNames = [zipName];
        const uris: string[] = await docPicker.save(opt);
        const uri = uris[0];
        const dst = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.writeSync(dst.fd, zipBuffer);
        fs.closeSync(dst);
        return zipName;
    }
}
