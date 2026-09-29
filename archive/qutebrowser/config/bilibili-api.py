"""B站 App 推荐的小型本机桥接；只提供列出的接口，不代理任意 URL。"""
import hashlib
import json
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

# 与 Bilibili-Gate 使用相同的公开 TV 客户端签名参数。
APPKEY = '4409e2ce8ffd12b8'
APPSEC = '59b43e04ad6965f34319062b478f83dd'
ORIGIN = 'https://www.bilibili.com'


def signed(params):
    params = dict(params, appkey=APPKEY)
    query = urlencode(sorted(params.items()))
    return dict(params, sign=hashlib.md5((query + APPSEC).encode()).hexdigest())


class Client:
    def __init__(self, path):
        self.path = path
        self.auth = {}
        self.idx = 0
        try:
            self.auth = json.loads(path.read_text())
        except (OSError, ValueError):
            pass

    def save_auth(self, data):
        auth = {'access_token': data['access_token'], 'expires': time.time() + data['expires_in']}
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix('.tmp')
        with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as f:
            os.fchmod(f.fileno(), 0o600)
            json.dump(auth, f)
        tmp.replace(self.path)
        self.auth = auth

    def request(self, path, params, login=False):
        host = 'https://passport.bilibili.com' if login else 'https://app.bilibili.com'
        if not login:
            params = dict(params, access_key=self.auth['access_token'])
        query = urlencode(signed(params))
        req = Request(host + path + ('' if login else '?' + query),
                      data=query.encode() if login else None,
                      headers={'User-Agent': 'Mozilla/5.0', 'Referer': ORIGIN + '/'})
        with urlopen(req, timeout=15) as res:
            data = json.load(res)
        if data.get('code') in (-101, -400, -663) and not login:
            # Keep the credential until expiry; show the real failure rather than relogin loops.
            raise ValueError(data.get('message') or 'App 授权失效，请重新扫码')
        return data

    def call(self, action, params):
        if action == 'status':
            return {'logged_in': bool(self.auth.get('access_token')) and self.auth.get('expires', 0) > time.time()}
        if action == 'qr':
            data = self.request('/x/passport-tv-login/qrcode/auth_code', {'local_id':'0', 'ts':'0'}, login=True)
            if data.get('code') != 0:
                raise ValueError(data.get('message') or '获取二维码失败')
            return {'url':data['data']['url'], 'auth_code':data['data']['auth_code']}
        if action == 'poll':
            code = str(params.get('auth_code', ''))
            if not code.isalnum() or len(code) > 128:
                raise ValueError('请先获取二维码')
            data = self.request('/x/passport-tv-login/qrcode/poll', {'auth_code':code, 'local_id':'0', 'ts':'0'}, login=True)
            if data.get('code') == 0:
                self.save_auth(data['data'])
                return {'code':0}
            return {'code':data.get('code'), 'message':data.get('message')}
        if action not in ('feed', 'dislike', 'undo'):
            raise ValueError('未知操作')
        if not self.call('status', {})['logged_in']:
            raise ValueError('请先扫码授权 App 推荐')
        if action == 'feed':
            self.idx += 1
            path = '/x/v2/feed/index'
            query = dict(actionKey='appkey', platform='ios', mobi_app='iphone', device='pad',
                         build='90300100', c_locale='zh-Hans_CN', s_locale='zh-Hans_CN',
                         idx=int(time.time()) + 100*self.idx)
        else:
            video_id, reason = str(params.get('id', '')), str(params.get('reason', ''))
            if not video_id.isdigit() or not reason.isdigit():
                raise ValueError('无效的视频或反馈选项')
            path = '/x/feed/dislike' + ('/cancel' if action == 'undo' else '')
            query = dict(goto='av', id=video_id, reason_id=reason, build='1', mobi_app='android', idx=int(time.time()))
        data = self.request(path, query)
        if data.get('code') != 0:
            raise ValueError(data.get('message') or 'B站接口请求失败')
        return data.get('data') or {}


def start(path):
    client = Client(path)
    key = secrets.token_urlsafe(32)
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # 不记录登录或推荐请求。

        def allowed(self):
            return self.headers.get('Origin') == ORIGIN and self.headers.get('Host') == f'127.0.0.1:{self.server.server_port}'

        def reply(self, code, data):
            body = json.dumps(data, ensure_ascii=False).encode()
            self.send_response(code)
            if self.allowed():
                self.send_header('Access-Control-Allow-Origin', ORIGIN)
                self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-Qute-Bili')
                self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
                self.send_header('Access-Control-Allow-Private-Network', 'true')
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_OPTIONS(self):
            self.reply(200 if self.allowed() else 403, {})

        def do_POST(self):
            if not self.allowed() or not secrets.compare_digest(self.headers.get('X-Qute-Bili', ''), key):
                self.reply(403, {'error':'拒绝访问'})
                return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 4096:
                    raise ValueError('请求过大或为空')
                params = json.loads(self.rfile.read(length))
                if not isinstance(params, dict):
                    raise ValueError('无效参数')
                with lock:
                    result = self.server.client.call(self.path.removeprefix('/'), params)
                self.reply(200, {'data':result})
            except ValueError as e:
                self.reply(400, {'error':str(e)})
            except Exception:
                self.reply(502, {'error':'连接 B站失败，请稍后重试'})

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.client = client
    server.connection = {'url':f'http://127.0.0.1:{server.server_port}', 'key':key}
    threading.Thread(target=server.serve_forever, daemon=True, name='bili-api').start()
    return server, server.connection
