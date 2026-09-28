import { BusinessError, request } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Ctx } from './Utils';

/**
 * 轨迹包上传（把导出的 zip 送到云端/自建服务）。
 *
 * 设计取舍：
 *  - **只依赖一个地址**：换后端（局域网自建服务 / Cloudflare Worker / Supabase / 对象存储签名接口）
 *    只需要改设置里的 URL，App 代码不动。所以这里不绑定任何厂商 SDK。
 *  - **令牌走表单字段而不是请求头**：ArkTS 里 `header` 的声明类型是 Object，直接写对象字面量容易踩
 *    arkts-no-untyped-obj-literals；放进 multipart 的 data 字段既安全又够用（自建服务与 Worker 都好接）。
 *  - **文件必须在 cacheDir 根目录**：request.uploadFile 只认 `internal://cache/<文件名>`，
 *    子目录/其它沙箱目录都不行（打包见 Exporter.stageForUpload）。
 */
export interface UploadTarget {
  /** 上传地址，例如 http://192.168.1.5:8000/upload 或 https://xxx.workers.dev/upload */
  url: string;
  /** 可选令牌，非空时作为表单字段 token 一起发过去（后端自己校验） */
  token: string;
  /** 表单里文件字段的名字，空字符串则用 'file' */
  fieldName: string;
}

export interface UploadProgress {
  uploaded: number;
  total: number;
}

export interface UploadResult {
  ok: boolean;
  /** 服务器返回的原始响应体（自建服务会返回 JSON，里面有保存路径/下载链接） */
  body: string;
  /** 给用户看的一句话 */
  message: string;
}

export class Uploader {
  /** 默认表单字段名（后端按这个名字取文件） */
  static readonly DEFAULT_FIELD: string = 'file';

  /**
   * 上传 cacheDir 里的一个文件。
   * 不会抛异常：成功失败都通过 UploadResult 返回，调用方只负责展示。
   */
  static async upload(cacheName: string, target: UploadTarget,
    onProgress: (p: UploadProgress) => void): Promise<UploadResult> {
    const ctx = Ctx.ui;
    if (!ctx) {
      return Uploader.fail('应用未就绪，稍后再试');
    }
    const url: string = target.url.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return Uploader.fail('上传地址要以 http:// 或 https:// 开头（可在「上传设置」里改）');
    }
    const field: string = target.fieldName.trim().length > 0
      ? target.fieldName.trim() : Uploader.DEFAULT_FIELD;
    const token: string = target.token.trim();

    let task: request.UploadTask;
    try {
      task = await request.uploadFile(ctx, {
        url: url,
        method: 'POST',
        files: [
          {
            filename: cacheName,
            name: field,
            uri: `internal://cache/${cacheName}`,
            type: 'application/zip'
          }
        ],
        data: token.length > 0 ? [{ name: 'token', value: token }] : []
      });
    } catch (e) {
      return Uploader.fail(`发起上传失败：${Uploader.why(e)}`);
    }

    return new Promise<UploadResult>((resolve: (r: UploadResult) => void) => {
      let body: string = '';
      let settled: boolean = false;
      const finish = (r: UploadResult): void => {
        if (!settled) {
          settled = true;
          resolve(r);
        }
      };

      task.on('progress', (uploaded: number, total: number) => {
        onProgress({ uploaded: uploaded, total: total } as UploadProgress);
      });
      task.on('headerReceive', (headers: ESObject) => {
        const b: ESObject = headers?.body;
        if (typeof b === 'string') {
          body = b as string;
        }
      });
      task.on('complete', () => {
        finish({
          ok: true,
          body: body,
          message: body.length > 0 ? '上传完成' : '上传完成（服务器没有返回内容）'
        } as UploadResult);
      });
      task.on('fail', (err: BusinessError) => {
        hilog.error(0x0000, 'RoomMarker', 'upload failed: %{public}s', Uploader.why(err));
        finish({
          ok: false,
          body: body,
          message: `上传失败：${Uploader.why(err)}`
        } as UploadResult);
      });
    });
  }

  private static fail(message: string): UploadResult {
    return { ok: false, body: '', message: message } as UploadResult;
  }

  /** 把各种异常/错误对象压成一句人话（code + message 最常见） */
  private static why(e: ESObject): string {
    if (e === undefined || e === null) {
      return '未知原因';
    }
    const code: ESObject = e.code;
    const msg: ESObject = e.message;
    if (typeof code === 'number' && typeof msg === 'string') {
      return `code ${code}：${msg as string}`;
    }
    try {
      return JSON.stringify(e);
    } catch (err) {
      return '未知原因';
    }
  }
}
