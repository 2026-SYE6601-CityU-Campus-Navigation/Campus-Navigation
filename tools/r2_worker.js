/**
 * RoomMarker 轨迹包上传 · Cloudflare Worker（绑定 R2 桶）
 *
 * 为什么要有这一层：App 里不能放 R2 的密钥（密钥进客户端 = 等于公开）。
 * Worker 持有 R2 绑定，对 App 只暴露一个地址 + 令牌；换成别的桶或别的云，
 * App 侧只需要改「上传设置」里的地址。
 *
 * 需要配置（Cloudflare 控制台 → Worker → Settings → Variables and Secrets，都选 Secret）：
 *   - `UPLOAD_TOKEN`（必需）：上传用的令牌。**支持用英文逗号写多把**，例如 `tok_mine,tok_wang`
 *                            —— 组员各一把，谁要收回就删谁那一把。
 *   - `READ_TOKEN` （可选）：只读令牌，发给组员/老师看数据用。也支持逗号分隔多把。
 *                            没有它时读取也用 UPLOAD_TOKEN（省事，但一把钥匙既能读也能传）。
 *   - Binding      ：R2 bucket，变量名必须是 `TRACKS`
 *
 * ⚠️ 一个令牌都没配时，**除 /health 外全部拒绝**（fail-closed）——避免"忘了配密钥 = 接口对所有人敞开"。
 *
 * 接口：
 *   GET  /health                 健康检查（会说明令牌配了没有，不返回令牌本身）
 *   POST /upload                 multipart/form-data，字段 file（App 发的就是这种）
 *                                · 也接受原始字节（PUT/POST，文件名走 x-filename 头）
 *   GET  /files/<key>?k=<令牌>   下载（发给组员的链接就长这样）
 *   GET  /?k=<令牌>              列表页
 *
 * ⚠️ 桶保持「私有」。里面是真实 GPS 轨迹与现场照片，别开 Public access。
 */

function json(obj, status) {
  return new Response(JSON.stringify(obj, null, 2), {
    status: status || 200,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

/** 配置里可以写多把令牌（逗号分隔），返回清洗后的数组 */
function tokenList(configured) {
  return String(configured || '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

function matches(given, configured) {
  const list = tokenList(configured);
  return list.length > 0 && list.indexOf(String(given || '').trim()) >= 0;
}

/** 令牌两种递交方式都收：Authorization: Bearer（App 会发）+ 表单字段/查询参数 token */
function providedToken(request, extra, formToken) {
  const auth = request.headers.get('Authorization') || '';
  const bearer = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  return (formToken || bearer || extra || '').trim();
}

function safeName(name) {
  const base = String(name || '').split('/').pop() || 'upload.zip';
  return base.replace(/[\\/:*?"<>|]/g, '_').slice(0, 120);
}

function stamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}_${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}`;
}

const NOT_CONFIGURED =
  '未配置令牌：请在 Worker 的 Settings → Variables and Secrets 里添加 Secret `UPLOAD_TOKEN`（以及可选的 `READ_TOKEN`）';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const bucket = env.TRACKS;
    const uploadOk = tokenList(env.UPLOAD_TOKEN).length > 0;
    const readConfigured = tokenList(env.READ_TOKEN).length > 0 || uploadOk;

    if (!bucket) {
      return json({ ok: false, error: 'R2 绑定缺失：请把桶绑定到变量名 TRACKS' }, 500);
    }

    // ---------- 健康检查（不返回令牌本身，只说配没配） ----------
    if (url.pathname === '/health') {
      return json({
        ok: true,
        service: 'RoomMarker R2 upload',
        uploadTokenConfigured: uploadOk,
        readTokenConfigured: tokenList(env.READ_TOKEN).length > 0,
      });
    }

    if (!uploadOk) {
      return json({ ok: false, error: NOT_CONFIGURED }, 500);
    }

    /** 读取（列表/下载）允许：READ_TOKEN 里的任意一把，或 UPLOAD_TOKEN 里的任意一把 */
    const canRead = (given) => matches(given, env.READ_TOKEN) || matches(given, env.UPLOAD_TOKEN);
    /** 组装下载链接时优先用只读令牌（这样发出去的链接不带上传权限） */
    const linkToken = tokenList(env.READ_TOKEN)[0] || tokenList(env.UPLOAD_TOKEN)[0];

    // ---------- 下载 ----------
    if (request.method === 'GET' && url.pathname.startsWith('/files/')) {
      const key = decodeURIComponent(url.pathname.slice('/files/'.length));
      const given = providedToken(request, url.searchParams.get('k'));
      if (!canRead(given)) {
        return json({ ok: false, error: 'bad token' }, 403);
      }
      const obj = await bucket.get(key);
      if (!obj) {
        return json({ ok: false, error: 'no such file' }, 404);
      }
      const headers = new Headers();
      if (typeof obj.writeHttpMetadata === 'function') {
        obj.writeHttpMetadata(headers);
      }
      headers.set('content-type', 'application/octet-stream');
      // ⚠️ HTTP 头只能是 Latin-1：文件名里有中文时，直接塞进 Content-Disposition 会抛
      // "Cannot convert argument to a ByteString"。所以按 RFC 5987 给两种形式：
      // 回落用的 ASCII 名 + UTF-8 百分号编码名。
      const shown = safeName(key);
      const ascii = shown.replace(/[^\x20-\x7E]/g, '_');
      const enc = encodeURIComponent(shown).replace(/['()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase());
      headers.set('content-disposition', `attachment; filename="${ascii}"; filename*=UTF-8''${enc}`);
      headers.set('etag', obj.httpEtag || '');
      return new Response(obj.body, { headers });
    }

    // ---------- 列表页 ----------
    if (request.method === 'GET' && (url.pathname === '/' || url.pathname === '')) {
      const given = providedToken(request, url.searchParams.get('k'));
      if (!canRead(given)) {
        return json({ ok: false, error: 'bad token' }, 403);
      }
      const list = await bucket.list({ limit: 200 });
      const rows = (list.objects || [])
        .sort((a, b) => (b.uploaded || 0) - (a.uploaded || 0))
        .map((o) => {
          const when = new Date(o.uploaded || Date.now()).toISOString().slice(0, 16).replace('T', ' ');
          const mb = ((o.size || 0) / 1024 / 1024).toFixed(1);
          const href = `/files/${encodeURIComponent(o.key)}?k=${encodeURIComponent(linkToken)}`;
          return `<li><a href="${href}">${o.key}</a><span class="meta">${when} · ${mb} MB</span></li>`;
        })
        .join('');
      const html = `<!doctype html><html lang="zh"><meta charset="utf-8">
<title>RoomMarker 轨迹包</title>
<style>
 body{font:15px/1.7 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"PingFang SC","Microsoft YaHei",sans-serif;
      max-width:760px;margin:40px auto;padding:0 18px;color:#2b1b22;background:#fbf7f2}
 h1{font-size:21px;color:#8c1d40} .meta{color:#8a7c82;font-size:13px;margin-left:8px}
 li{margin:6px 0} .box{background:#fff;border:2px solid #ece2da;border-radius:14px;padding:16px 20px}
 code{background:#f3eae2;padding:1px 5px;border-radius:5px}
</style>
<div class="box">
<h1>RoomMarker 轨迹包（${(list.objects || []).length} 个）</h1>
<p>点文件名即可下载。分享给组员时，把本页地址（带 <code>?k=只读令牌</code>）发过去即可 —— 只读令牌不能上传。</p>
<ul>${rows || '<li>还没有收到文件</li>'}</ul>
</div></html>`;
      return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
    }

    // ---------- 上传 ----------
    if (request.method !== 'POST' && request.method !== 'PUT') {
      return json({ ok: false, error: 'use POST /upload' }, 405);
    }

    const ctype = request.headers.get('content-type') || '';
    let payload = null;
    let filename = '';
    let formToken = '';

    try {
      if (ctype.includes('multipart/form-data')) {
        const form = await request.formData();
        for (const [key, value] of form.entries()) {
          if (key === 'token' && typeof value === 'string') {
            formToken = value;
          } else if (typeof value === 'object' && value !== null && typeof value.stream === 'function') {
            payload = value.stream();
            filename = value.name || '';
          }
        }
      } else {
        // 原始字节上传：文件名走请求头，省掉 multipart 解析（大文件更省 CPU）
        payload = request.body;
        filename = request.headers.get('x-filename') || `upload_${Date.now()}.zip`;
      }
    } catch (e) {
      return json({ ok: false, error: `解析请求体失败：${e.message}` }, 400);
    }

    const given = providedToken(request, url.searchParams.get('k'), formToken);
    // 上传只认 UPLOAD_TOKEN —— 只读令牌拿不到上传权限
    if (!matches(given, env.UPLOAD_TOKEN)) {
      return json({ ok: false, error: 'bad token（上传需要 UPLOAD_TOKEN；只读令牌不能上传）' }, 403);
    }
    if (!payload) {
      return json({ ok: false, error: 'no file field found' }, 400);
    }

    const name = safeName(filename);
    const dot = name.lastIndexOf('.');
    const stem = dot > 0 ? name.slice(0, dot) : name;
    const ext = dot > 0 ? name.slice(dot) : '.zip';
    const key = `${stem}_${stamp()}${ext}`;

    await bucket.put(key, payload);

    const head = await bucket.head(key);
    const size = head ? head.size : 0;
    return json({
      ok: true,
      file: key,
      size: size,
      url: `${url.origin}/files/${encodeURIComponent(key)}?k=${encodeURIComponent(linkToken)}`,
    });
  },
};
