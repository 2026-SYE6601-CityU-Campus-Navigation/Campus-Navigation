#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
轨迹包接收服务（零依赖，只用 Python 标准库；Python 3.9+ 均可直接跑）。

用途：手机 App 里「上传到云端」按钮的接收端。先在电脑上跑起来，手机与电脑连同一个 WiFi 即可
（出门采集回来、或者当场把数据传回电脑都行）。之后换成 Cloudflare Worker / Supabase / 对象存储
签名接口时，App 里只需改一个地址，代码不用动。

用法：
    python3 upload_server.py                 # 监听 0.0.0.0:8000，文件存到 ./uploads/
    python3 upload_server.py --port 9000 --dir D:\\traj_data
    python3 upload_server.py --token mysecret   # 要求表单里的 token 字段一致（App 的「上传令牌」填同一个）

接口：
    POST /upload    multipart/form-data
                      file  —— 轨迹包（App 发的 zip）
                      token —— 可选，服务端启用 --token 时必填
                    → {"ok": true, "file": "...", "size": 123, "sha256": "...", "url": "http://..."}
    GET  /files/<name>   下载某个已上传的文件
    GET  /               列出已收到的文件（浏览器直接打开即可点给队友/老师）
    GET  /health         健康检查（用来确认手机能不能连上）
"""
import argparse
import hashlib
import hmac
import html
import json
import os
import re
import socket
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, unquote, urlsplit


def human_size(n: int) -> str:
    if n < 1024:
        return f'{n} B'
    for unit in ('KB', 'MB', 'GB'):
        n /= 1024.0
        if n < 1024 or unit == 'GB':
            return f'{n:.1f} {unit}'
    return f'{n} B'


class LimitedRequestReader:
    """Length-bounded HTTP body reader with a small pushback buffer."""

    def __init__(self, stream, length):
        self.stream = stream
        self.remaining = length
        self.pending = bytearray()

    def read(self, count):
        output = bytearray()
        if self.pending:
            take = min(count, len(self.pending))
            output.extend(self.pending[:take])
            del self.pending[:take]
        if len(output) < count and self.remaining:
            chunk = self.stream.read(min(count - len(output), self.remaining))
            self.remaining -= len(chunk)
            output.extend(chunk)
        return bytes(output)

    def unread(self, data):
        self.pending = bytearray(data) + self.pending

    def readline(self, limit=16 * 1024):
        output = bytearray()
        while len(output) < limit:
            byte = self.read(1)
            if not byte:
                break
            output.extend(byte)
            if output.endswith(b'\n'):
                break
        if len(output) >= limit and not output.endswith(b'\n'):
            raise ValueError('multipart header line too long')
        return bytes(output)


def stream_until(reader, delimiter, write, maximum):
    """Copy one multipart value while retaining only a small boundary window."""
    buffer = bytearray()
    total = 0
    while True:
        chunk = reader.read(64 * 1024)
        if not chunk:
            raise ValueError('multipart boundary missing')
        buffer.extend(chunk)
        match = buffer.find(delimiter)
        if match >= 0:
            data = bytes(buffer[:match])
            if total + len(data) > maximum:
                raise ValueError('multipart part too large')
            write(data)
            total += len(data)
            reader.unread(buffer[match + len(delimiter):])
            return total
        keep = len(delimiter) - 1
        if len(buffer) > keep:
            data = bytes(buffer[:-keep])
            if total + len(data) > maximum:
                raise ValueError('multipart part too large')
            write(data)
            total += len(data)
            del buffer[:-keep]


def content_disposition(value):
    name = re.search(r'(?:^|;\s*)name="([^"\r\n]*)"', value)
    filename = re.search(r'(?:^|;\s*)filename="([^"\r\n]*)"', value)
    return (name.group(1) if name else None, filename.group(1) if filename else None)


def safe_upload_name(name):
    base = str(name or 'upload.zip').replace('\\', '/').split('/')[-1]
    cleaned = ''.join('_' if ord(char) < 32 or char in '/\\:*?"<>|' else char for char in base)
    return (cleaned[:160] or 'upload.zip')


class Handler(BaseHTTPRequestHandler):
    server_version = 'RoomMarkerUpload/1.0'

    # ---------- 工具 ----------
    def _json(self, code: int, obj: dict) -> None:
        payload = json.dumps(obj, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _html(self, code: int, html: str) -> None:
        payload = html.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _base_url(self) -> str:
        host = self.headers.get('Host') or f'{self.server.server_address[0]}:{self.server.server_address[1]}'
        return f'http://{host}'

    def _provided_token(self, query=''):
        auth = self.headers.get('Authorization', '')
        bearer = auth[7:].strip() if auth.startswith('Bearer ') else ''
        parameter = parse_qs(query, keep_blank_values=True).get('k', [''])[0]
        return bearer or parameter

    def _authorized(self, query=''):
        return not self.server.token or hmac.compare_digest(self._provided_token(query), self.server.token)

    def log_message(self, fmt, *args):  # 精简日志：带时间戳，方便对着手机上的报错时间点看
        sys.stdout.write('  [%s] %s\n' % (time.strftime('%H:%M:%S'), fmt % args))
        sys.stdout.flush()

    def handle_one_request(self):
        # 手机中途取消上传、或探测端口时提前断开，都会让写响应抛 BrokenPipe/ConnectionReset。
        # 这是正常的网络行为，记一行就够，不要吐一大段 traceback 把真正的错误淹掉。
        try:
            super().handle_one_request()
        except (BrokenPipeError, ConnectionResetError) as e:
            self.close_connection = True
            print(f'  （客户端提前断开：{type(e).__name__}，已忽略）')

    # ---------- GET ----------
    def do_GET(self):
        request = urlsplit(self.path)
        if request.path == '/health':
            self._json(200, {'ok': True, 'service': 'RoomMarker upload'})
            return
        if not self._authorized(request.query):
            self._json(403, {'ok': False, 'error': 'bad token'})
            return
        if request.path.startswith('/files/'):
            name = unquote(request.path[len('/files/'):])
            path = os.path.join(self.server.upload_dir, os.path.basename(name))
            if not os.path.isfile(path):
                self._json(404, {'ok': False, 'error': 'no such file'})
                return
            size = os.path.getsize(path)
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', f'attachment; filename="{quote(os.path.basename(path))}"')
            self.send_header('Content-Length', str(size))
            self.end_headers()
            with open(path, 'rb') as f:
                while True:
                    chunk = f.read(64 * 1024)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
            return
        if request.path not in ('', '/'):
            self._json(404, {'ok': False, 'error': 'unknown path'})
            return
        # 首页：列出收到的包（给队友/老师看的入口）
        files = sorted(
            (f for f in os.listdir(self.server.upload_dir) if os.path.isfile(os.path.join(self.server.upload_dir, f))),
            key=lambda f: os.path.getmtime(os.path.join(self.server.upload_dir, f)),
            reverse=True,
        ) if os.path.isdir(self.server.upload_dir) else []
        rows = []
        query = '' if not self.server.token else '?k=' + quote(self._provided_token(request.query), safe='')
        for f in files:
            p = os.path.join(self.server.upload_dir, f)
            shown = html.escape(f)
            rows.append(
                f'<li><a href="/files/{quote(f)}{query}">{shown}</a>'
                f'<span class="meta">{time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(p)))}'
                f' · {human_size(os.path.getsize(p))}</span></li>'
            )
        self._html(200, f"""<!doctype html><html lang="zh"><meta charset="utf-8">
<title>RoomMarker 轨迹包</title>
<style>
 body{{font:15px/1.7 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"PingFang SC","Microsoft YaHei",sans-serif;
      max-width:760px;margin:40px auto;padding:0 18px;color:#2b1b22;background:#fbf7f2}}
 h1{{font-size:21px;color:#8c1d40}} .meta{{color:#8a7c82;font-size:13px;margin-left:8px}}
 li{{margin:6px 0}} code{{background:#f3eae2;padding:1px 5px;border-radius:5px}}
 .box{{background:#fff;border:2px solid #ece2da;border-radius:14px;padding:16px 20px}}
</style>
<div class="box">
<h1>RoomMarker 轨迹包（{len(files)} 个）</h1>
<p>这些是手机「上传到云端」传上来的 zip。点文件名直接下载；给队友或老师看时，把这个页面的局域网地址发过去即可（需在同一 WiFi）。</p>
<ul>{''.join(rows) or '<li>还没有收到文件</li>'}</ul>
<p class="meta">接收接口：<code>POST /upload</code></p>
</div></html>""")

    # ---------- POST ----------
    def do_POST(self):
        if not self.path.startswith('/upload'):
            self._json(404, {'ok': False, 'error': 'unknown path, use /upload'})
            return
        ctype = self.headers.get('Content-Type', '')
        if 'multipart/form-data' not in ctype:
            self._json(400, {'ok': False, 'error': f'expect multipart/form-data, got {ctype}'})
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            length = 0
        if length <= 0:
            self._json(400, {'ok': False, 'error': 'empty body'})
            return
        if length > self.server.max_bytes:
            self._json(413, {'ok': False, 'error': 'upload too large'})
            return
        match = re.search(r'(?:^|;)\s*boundary=(?:"([^"]+)"|([^;\s]+))', ctype)
        if not match:
            self._json(400, {'ok': False, 'error': 'multipart boundary missing'})
            return
        boundary_text = match.group(1) or match.group(2)
        if not 1 <= len(boundary_text) <= 200 or any(ord(c) < 33 or ord(c) > 126 for c in boundary_text):
            self._json(400, {'ok': False, 'error': 'invalid multipart boundary'})
            return
        boundary = boundary_text.encode('ascii')
        reader = LimitedRequestReader(self.rfile, length)
        temporary = os.path.join(self.server.upload_dir, f'.incoming-{time.time_ns()}-{id(self)}.part')
        fname = None
        form_token = ''
        digest = hashlib.sha256()
        size = 0
        try:
            if reader.readline() != b'--' + boundary + b'\r\n':
                raise ValueError('invalid initial multipart boundary')
            final = False
            while not final:
                headers = {}
                while True:
                    line = reader.readline()
                    if line == b'\r\n':
                        break
                    if not line:
                        raise ValueError('truncated multipart headers')
                    key, separator, value = line.decode('utf-8', 'strict').partition(':')
                    if not separator:
                        raise ValueError('invalid multipart header')
                    headers[key.strip().lower()] = value.strip()
                field, filename = content_disposition(headers.get('content-disposition', ''))
                if not field:
                    raise ValueError('multipart field name missing')
                delimiter = b'\r\n--' + boundary
                if filename is not None:
                    if fname is not None:
                        raise ValueError('multiple files are not allowed')
                    fname = safe_upload_name(filename)
                    with open(temporary, 'xb') as output:
                        def write_file(data):
                            output.write(data)
                            digest.update(data)
                        size = stream_until(reader, delimiter, write_file, self.server.max_bytes)
                else:
                    value = bytearray()
                    stream_until(reader, delimiter, value.extend, 4096)
                    if field == 'token':
                        form_token = value.decode('utf-8', 'strict')
                suffix = reader.read(2)
                if suffix == b'--':
                    ending = reader.read(2)
                    if ending not in (b'', b'\r\n'):
                        raise ValueError('invalid final multipart boundary')
                    final = True
                elif suffix != b'\r\n':
                    raise ValueError('invalid multipart continuation')
            if reader.remaining or reader.pending:
                raise ValueError('unexpected multipart trailing data')
            if fname is None or not os.path.isfile(temporary):
                raise ValueError('no file field found')
            with open(temporary, 'rb') as incoming:
                if incoming.read(4) != b'PK\x03\x04':
                    raise ValueError('file is not a ZIP archive')
            if not fname.lower().endswith('.zip'):
                raise ValueError('file name must end in .zip')
        except (OSError, UnicodeError, ValueError) as error:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass
            self._json(400, {'ok': False, 'error': str(error)})
            return

        if self.server.token:
            auth = self.headers.get('Authorization', '')
            bearer = auth[7:].strip() if auth.startswith('Bearer ') else ''
            if not (hmac.compare_digest(form_token, self.server.token) or
                    hmac.compare_digest(bearer, self.server.token)):
                os.unlink(temporary)
                print('  ✗ 令牌不匹配（值未记录）')
                self._json(403, {'ok': False, 'error': 'bad token'})
                return
            print('  ✓ 令牌校验通过')

        # 文件名加上传时刻，避免覆盖；同秒重复再补序号
        stamp = time.strftime('%Y%m%d_%H%M%S')
        base, ext = os.path.splitext(fname)
        name = f'{base}_{stamp}{ext}'
        path = os.path.join(self.server.upload_dir, name)
        seq = 1
        while os.path.exists(path):
            name = f'{base}_{stamp}_{seq}{ext}'
            path = os.path.join(self.server.upload_dir, name)
            seq += 1

        os.replace(temporary, path)
        digest_text = digest.hexdigest()
        print(f'  ✓ 已保存 {name}（{human_size(size)}，sha256 {digest_text[:12]}…）')

        self._json(200, {
            'ok': True,
            'file': name,
            'size': size,
            'sha256': digest_text,
            'url': f'{self._base_url()}/files/{quote(name)}',
        })


def lan_ips():
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))          # 不发包，只为拿到本机出口地址
        ips.append(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips and not ip.startswith('127.'):
                ips.append(ip)
    except Exception:
        pass
    return ips


def main():
    ap = argparse.ArgumentParser(description='RoomMarker 轨迹包接收服务')
    ap.add_argument('--port', type=int, default=8000)
    ap.add_argument('--host', default='0.0.0.0')
    ap.add_argument('--dir', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'uploads'),
                    help='文件保存目录（默认脚本同级的 uploads/）')
    ap.add_argument('--token', default='', help='启用令牌校验：App 的「上传令牌」要填同一个值')
    ap.add_argument('--max-bytes', type=int, default=2 * 1024 * 1024 * 1024,
                    help='单次请求上限（默认 2 GiB）')
    args = ap.parse_args()

    os.makedirs(args.dir, exist_ok=True)
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    httpd.upload_dir = args.dir
    httpd.token = args.token
    httpd.max_bytes = args.max_bytes

    print('RoomMarker 轨迹包接收服务已启动')
    print(f'  保存目录：{args.dir}')
    print(f'  令牌校验：{"开启" if args.token else "关闭"}')
    print('  App「上传设置」里填下面任一地址（手机要和这台电脑在同一个 WiFi）：')
    local_name = socket.gethostname().split('.')[0]
    if local_name:
        print(f'    http://{local_name}.local:{args.port}/upload')
    for ip in lan_ips():
        print(f'    http://{ip}:{args.port}/upload')
    print(f'  本机自测：http://127.0.0.1:{args.port}/upload　·　文件列表页 http://127.0.0.1:{args.port}/')
    print('  按 Ctrl+C 结束\n')
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print('\n已停止')
        httpd.server_close()


if __name__ == '__main__':
    main()
