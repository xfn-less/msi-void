"""导航开始时应用 B站原生 150% 缩放；依赖 qute 3.7 内部接口。"""
from functools import partial

from qutebrowser.browser.browsertab import AbstractZoom
from qutebrowser.utils import objreg

# 热加载时撤下旧版“加载完成后缩放”的补丁。
if hasattr(AbstractZoom, "_site_zoom_original"):
    AbstractZoom.reapply = AbstractZoom._site_zoom_original
if not hasattr(AbstractZoom, "_site_zoom_init"):
    AbstractZoom._site_zoom_init = AbstractZoom.__init__


def apply_zoom(zoom, url):
    host = url.host()
    if host == "bilibili.com" or host.endswith(".bilibili.com"):
        if not hasattr(zoom, "_before_bilibili"):
            zoom._before_bilibili = zoom.factor()
        zoom.set_factor(1.5)
    elif hasattr(zoom, "_before_bilibili"):
        zoom.set_factor(zoom._before_bilibili)
        del zoom._before_bilibili
    else:
        return
    # QtWebEngine 会在加载完成时恢复此值，避免又跳回旧比例。
    if getattr(zoom._tab, "_saved_zoom", None) is not None:
        zoom._tab._saved_zoom = zoom.factor()


def connect(zoom):
    if hasattr(zoom, "_site_zoom_slot"):
        zoom._tab.before_load_started.disconnect(zoom._site_zoom_slot)
        zoom._tab.url_changed.disconnect(zoom._site_zoom_slot)
    zoom._site_zoom_slot = partial(apply_zoom, zoom)
    zoom._tab.before_load_started.connect(zoom._site_zoom_slot)
    zoom._tab.url_changed.connect(zoom._site_zoom_slot)


def init(zoom, *args, **kwargs):
    AbstractZoom._site_zoom_init(zoom, *args, **kwargs)
    connect(zoom)


AbstractZoom.__init__ = init

# 同时接入已有标签；重复 :config-source 不叠加监听。
for window_id in objreg.window_registry:
    browser = objreg.get("tabbed-browser", scope="window", window=window_id)
    for tab in browser.widgets():
        connect(tab.zoom)
        apply_zoom(tab.zoom, tab.url())
