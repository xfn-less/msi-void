"""只覆盖日常需要的设置，其余使用 qute 默认值。"""
config.load_autoconfig()

# 普通模式下，未匹配 qute 快捷键的按键交给网页。
c.input.forward_unbound_keys = "all"
for key in ('<Left>', '<Right>', '<Up>', '<Down>'):
    c.bindings.commands.setdefault('normal', {})[key] = None

# QtWebEngine 6.11：启用 Linux OpenGL 视频硬解。
c.qt.args = ["enable-features=AcceleratedVideoDecodeLinuxGL"]

# 恢复会话；最后一个标签保持 qute 默认的保留行为。
c.auto_save.session = True
# 网页全屏只占满当前 qute 窗口，不改变 niri 的窗口大小。
c.content.fullscreen.window = True
c.tabs.show = "multiple"
c.tabs.indicator.width = 0
c.tabs.title.alignment = "center"

# 当前标签暗灰底，其余黑底；固定标签使用相同配色。
c.colors.tabs.odd.bg = "black"
c.colors.tabs.bar.bg = "black"
# 网页首次绘制前使用深色底，避免新标签先闪白。
c.colors.webpage.bg = "#111111"
c.colors.tabs.even.bg = "black"
c.colors.tabs.selected.odd.bg = "#303030"
c.colors.tabs.selected.even.bg = "#303030"
c.colors.tabs.pinned.odd.bg = "black"
c.colors.tabs.pinned.even.bg = "black"
c.colors.tabs.pinned.selected.odd.bg = "#303030"
c.colors.tabs.pinned.selected.even.bg = "#303030"

# 本地空白首页，后续功能直接在 start.html 中添加。
c.url.default_page = (config.configdir / "start.html").as_uri()
c.url.start_pages = [c.url.default_page]
c.url.searchengines = {"DEFAULT": "https://www.google.com/search?q={}"}
c.editor.command = ["alacritty", "-e", "vis", "{file}"]
# 一个输入框直接进入，多个输入框显示提示标签。
c.hints.auto_follow = "always"
# 三个运行时增强共用一个入口；等 qute 初始化完成后逐个加载。
import runpy
import sys
from qutebrowser.config import configinit
from qutebrowser.qt.widgets import QApplication


def load_extensions():
    for filename in ('site-zoom.py', 'bilibili.py', 'fcitx.py'):
        try:
            runpy.run_path(str(config.configdir / filename), init_globals={'config': config})
        except Exception as error:
            print(f'qutebrowser extension {filename} disabled: {error}', file=sys.stderr)


if QApplication.instance() is None:
    if not hasattr(configinit, '_personal_late_init'):
        configinit._personal_late_init = configinit.late_init

    def late_init(*args, **kwargs):
        configinit._personal_late_init(*args, **kwargs)
        load_extensions()

    configinit.late_init = late_init
else:
    load_extensions()

# 临时穿透一秒；提前离开穿透模式会取消计时，不影响之后的模式。
from qutebrowser.api import cmdutils
from qutebrowser.misc import objects
from qutebrowser.qt.core import QTimer
from qutebrowser.utils import objreg, usertypes

objects.commands.pop('pass-briefly', None)

@cmdutils.register(name='pass-briefly')
@cmdutils.argument('win_id', value=cmdutils.Value.win_id)
def pass_briefly(win_id: int):
    """Pass keys to the webpage for one second."""
    manager = objreg.get('mode-manager', scope='window', window=win_id)
    timer = getattr(manager, '_brief_timer', None)
    if timer is None:
        timer = QTimer(manager)
        timer.setSingleShot(True)
        timer.timeout.connect(lambda: manager.leave(usertypes.KeyMode.passthrough, reason='temporary passthrough expired'))
        manager.left.connect(timer.stop)
        manager._brief_timer = timer
    manager.enter(usertypes.KeyMode.passthrough, reason='temporary passthrough')
    timer.start(1000)

for key in ('xo', 'xO'):
    c.bindings.commands.setdefault('normal', {})[key] = None
config.bind('x', 'tab-close')
# 直接滚动页面，避免默认 scroll 命令模拟方向键触发网页操作。
config.bind('h', 'scroll-px -40 0')
config.bind('j', 'scroll-px 0 40')
config.bind('k', 'scroll-px 0 -40')
config.bind('l', 'scroll-px 40 0')
config.bind('e', 'scroll-page 0 -0.5')
config.bind('d', 'scroll-page 0 0.5')
config.bind('z', 'pass-briefly')

# 原生补全按键，候选窗口按内容收缩。
c.completion.show = "always"
c.completion.shrink = True

# 广告与跟踪拦截：通用规则、隐私规则、中文网站规则。
c.content.blocking.method = "adblock"
c.content.blocking.adblock.lists = [
    "https://easylist.to/easylist/easylist.txt",
    "https://easylist.to/easylist/easyprivacy.txt",
    "https://raw.githubusercontent.com/easylist/easylistchina/master/easylistchina.txt",
]
