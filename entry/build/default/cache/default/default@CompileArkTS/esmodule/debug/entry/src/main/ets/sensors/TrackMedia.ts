import camera from "@ohos:multimedia.camera";
import cameraPicker from "@ohos:multimedia.cameraPicker";
import fs from "@ohos:file.fs";
import { Ctx } from "@bundle:com.example.roommarker/entry/ets/common/Utils";
export interface PhotoCapture {
    absPath: string;
    relPath: string;
    timeMs: number;
}
/**
 * 轨迹途中拍照：调起系统相机（cameraPicker，无需相机权限、自动回到应用），
 * 并把照片复制到 filesDir/photos/{trackId}/ 沙箱目录。
 * 用户取消或失败时抛出异常（调用方处理提示）。
 */
export async function captureTrackPhoto(trackId: number): Promise<PhotoCapture> {
    const ctx = Ctx.ui;
    if (!ctx) {
        throw new Error('context not ready');
    }
    // cameraPosition 为必填，枚举来自 @kit.CameraKit 的 camera 命名空间（cameraPicker 自身没有）
    const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
    };
    const result: cameraPicker.PickerResult = await cameraPicker.pick(ctx, [cameraPicker.PickerMediaType.PHOTO], profile);
    const srcUri: string = result.resultUri;
    const timeMs = Date.now();
    const relDir = `photos/${trackId}`;
    const absDir = `${ctx.filesDir}/${relDir}`;
    fs.mkdirSync(absDir, true);
    const relPath = `${relDir}/${timeMs}.jpg`;
    const absPath = `${absDir}/${timeMs}.jpg`;
    // 分段复制（openSync 支持 picker 返回的 URI，逐字节读入沙箱防授权过期）
    const src = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(src.fd);
    const buf = new ArrayBuffer(stat.size);
    fs.readSync(src.fd, buf);
    fs.closeSync(src);
    const dst = fs.openSync(absPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    fs.writeSync(dst.fd, buf);
    fs.closeSync(dst);
    const out: PhotoCapture = { absPath: absPath, relPath: relPath, timeMs: timeMs };
    return out;
}
/** 删除已复制的照片文件（用户放弃保存时清理） */
export function deletePhotoFile(absPath: string): void {
    try {
        fs.unlinkSync(absPath);
    }
    catch (e) {
    }
}
/** 照片文件是否还存在（显示前兜底） */
export function photoExists(absPath: string): boolean {
    try {
        fs.accessSync(absPath);
        return true;
    }
    catch (e) {
        return false;
    }
}
