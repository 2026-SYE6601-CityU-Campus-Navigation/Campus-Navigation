import { request } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Ctx } from './Utils';

/**
 * 轨迹包上传（把导出的 zip 送到云端/自建服务）。
 *
 * 设计取舍：
 *  - **只依赖一个地址**：换后端（局域网自建服务 / Cloudflare Worker / Supabase / 对象存储签名接口）
 *    只需要改设置里的 URL，App 代码不动。所以这里不绑定任何厂商 SDK。
 *  - **令牌同时给两种形式**：表单字段 `token`（自建服务最好接）+ `Authorization: Bearer`（Worker /
 *    对象存储签名接口常用）。两种都发，服务端用哪种都行。
 *  - **文件必须在 cacheDir 根目录**：request.uploadFile 只认 `internal://cache/<文件名>`，
 *    子目录/其它沙箱目录都不行（打包见 Exporter.stageForUpload）。
 *
 * ⚠️ 关于事件签名（真机编译报错换来的经验，别再凭印象写）：
 *    本 SDK 版本里 `on('complete' | 'fail', callback: (states: TaskState[]) => void)` ——
 *    回调收到的是 **TaskState 数组**，不是 BusinessError；服务器的 HTTP 状态码与消息在
 *    `states[0].responseCode` / `states[0].message` 里。为了既能编译过又拿得到诊断信息，
 *    回调参数用 ESObject 声明（ArkTS 的逃生类型），再用 typeof 逐项取值。
 */
export interface UploadTarget {
  /** 上传地址，例如 http://192.168.1.5:8000/upload 或 https://xxx.workers.dev/upload */
  url: string;
  /** 可选令牌，非空时既作为表单字段 token，也作为 Authorization: Bearer 头 */
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

    // header 在 UploadConfig 里是**必填**字段；用 Record 而不是对象字面量，
    // 既不踩 arkts-no-untyped-obj-literals，也能按需塞令牌。
    const header: Record<string, string> = {};
    if (token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }

    let task: request.UploadTask;
    try {
      task = await request.uploadFile(ctx, {
        url: url,
        method: 'POST',
        header: header,
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
      task.on('complete', (states: ESObject) => {
        const info: string = Uploader.stateText(states);
        finish({
          ok: true,
          body: body,
          message: info.length > 0 ? `上传完成（${info}）` : '上传完成'
        } as UploadResult);
      });
      task.on('fail', (states: ESObject) => {
        const info: string = Uploader.stateText(states);
        hilog.error(0x0000, 'RoomMarker', 'upload failed: %{public}s', info);
        finish({
          ok: false,
          body: body,
          message: info.length > 0 ? `上传失败：${info}` : '上传失败：没有返回详细信息（检查地址/令牌/是否同一 WiFi）'
        } as UploadResult);
      });
    });
  }

  /**
   * 把 complete/fail 回调里的 TaskState[] 压成一句人话。
   * 本 SDK 版本里这个数组每项含 path / responseCode / message（HTTP 状态码就在里面）。
   */
  private static stateText(states: ESObject): string {
    if (states === undefined || states === null) {
      return '';
    }
    const count: ESObject = states.length;
    if (typeof count !== 'number' || count <= 0) {
      return '';
    }
    const s: ESObject = states[0];
    if (s === undefined || s === null) {
      return '';
    }
    const code: ESObject = s.responseCode;
    const msg: ESObject = s.message;
    let out: string = '';
    if (typeof code === 'number' && code > 0) {
      out = `HTTP ${code}`;
    }
    if (typeof msg === 'string' && msg.length > 0) {
      out = out.length > 0 ? `${out}：${msg}` : msg;
    }
    return out;
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
