"""当前窗口回到 normal 时退出网页输入框并关闭中文输入。"""
from qutebrowser.keyinput import modeman
from qutebrowser.qt.core import QProcess, QTimer
from qutebrowser.qt.widgets import QApplication
from qutebrowser.utils import objreg, usertypes

BLUR_INPUT = """(() => {
    function blur(root) {
        const el = root.activeElement;
        if (!el) return;
        if (el.shadowRoot) blur(el.shadowRoot);
        try { if (el.contentDocument) blur(el.contentDocument); } catch (_) {}
        if (el.matches('input, textarea, select, iframe') || el.isContentEditable)
            el.blur();
    }
    blur(document);
})()"""


def connect(manager):
    old = getattr(manager, '_fcitx_timer', None)
    if old is not None:
        manager.entered.disconnect(manager._fcitx_schedule)
        manager.left.disconnect(manager._fcitx_schedule)
        old.stop()
        old.deleteLater()
    timer = QTimer(manager)
    timer.setSingleShot(True)
    timer.setInterval(0)

    def reset():
        # 等本轮模式切换完成，避免经过 normal 的中间状态误关输入法。
        if manager.mode != usertypes.KeyMode.normal:
            return
        window = objreg.get('main-window', scope='window', window=manager._win_id)
        if QApplication.activeWindow() is window:
            browser = objreg.get('tabbed-browser', scope='window', window=manager._win_id)
            tab = browser.widget.currentWidget()
            if tab is not None:
                tab.run_js_async(BLUR_INPUT)
            QProcess.startDetached('fcitx5-remote', ['--check', '-c'])

    timer.timeout.connect(reset)
    manager._fcitx_schedule = lambda *args: timer.start()
    manager.entered.connect(manager._fcitx_schedule)
    manager.left.connect(manager._fcitx_schedule)
    manager._fcitx_timer = timer


if not hasattr(modeman, '_fcitx_original_init'):
    modeman._fcitx_original_init = modeman.init


def init(*args, **kwargs):
    manager = modeman._fcitx_original_init(*args, **kwargs)
    connect(manager)
    return manager


modeman.init = init
for window_id in objreg.window_registry:
    connect(objreg.get('mode-manager', scope='window', window=window_id))
