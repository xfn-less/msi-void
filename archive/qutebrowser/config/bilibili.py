"""装入 App 本机桥接；网页脚本运行在隔离 world，网页拿不到桥接凭据。"""
import importlib.util
import json
from pathlib import Path
from qutebrowser.browser.webengine import webenginesettings
from qutebrowser.qt.webenginecore import QWebEngineScript
from qutebrowser.utils import standarddir

base = Path(config.configdir)
spec = importlib.util.spec_from_file_location('qute_bili_api', base / 'bilibili-api.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)
server = getattr(webenginesettings, '_bili_server', None)
auth_path = Path(standarddir.data()) / 'bilibili-app-auth.json'
if server is None or not hasattr(server, 'connection'):
    if server is not None:
        server.shutdown()
        server.server_close()
    server, connection = api.start(auth_path)
else:
    # 保持端口和凭据，普通配置重载不会让已打开的首页断开。
    connection = server.connection
    old = server.client
    server.client = api.Client(auth_path)
    server.client.idx = old.idx
webenginesettings._bili_server = server
source = ('if (location.origin === "https://www.bilibili.com" && location.pathname === "/") {\n'
          + 'window.__quteBili = ' + json.dumps(connection) + ';\n'
          + 'document.addEventListener("DOMContentLoaded", () => {\n'
          + (base / 'lib/qrcode.min.js').read_text() + '\nwindow.__quteQR = QRCode;\n}, {once:true});\n}')


def install(profile):
    if profile.isOffTheRecord():
        return
    scripts = profile.scripts()
    for old in scripts.find('qute-bili-bridge'):
        scripts.remove(old)
    script = QWebEngineScript()
    script.setName('qute-bili-bridge')
    script.setWorldId(QWebEngineScript.ScriptWorldId.ApplicationWorld)
    script.setInjectionPoint(QWebEngineScript.InjectionPoint.DocumentCreation)
    script.setRunsOnSubFrames(False)
    script.setSourceCode(source)
    scripts.insert(script)


if not hasattr(webenginesettings, '_bili_init_profile'):
    webenginesettings._bili_init_profile = webenginesettings._init_profile


def init_profile(profile):
    webenginesettings._bili_init_profile(profile)
    install(profile)


webenginesettings._init_profile = init_profile
for name in ('default_profile', 'private_profile'):
    profile = getattr(webenginesettings, name, None)
    if profile is not None:
        install(profile)
