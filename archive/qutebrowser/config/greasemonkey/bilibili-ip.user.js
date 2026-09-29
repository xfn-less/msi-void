// ==UserScript==
// @name Bilibili comment IP location
// @namespace voidlinux-config
// @version 1.0.0
// @description 在新版 B站评论时间旁显示已有的 IP 属地。
// @match https://*.bilibili.com/*
// @run-at document-start
// @noframes
// @grant none
// @license MIT
// ==/UserScript==

// Adapted from BiliReveal by MaxChang3 (MIT).
// https://github.com/maxchang3/BiliReveal — see BiliReveal.LICENSE.
(() => {
    const tag = 'bili-comment-action-buttons-renderer';
    const marker = Symbol.for('qute.bilibili.ip');

    function showLocation(element) {
        const root = element.shadowRoot;
        const date = root?.querySelector('#pubdate');
        if (!date) return;
        const location = element.data?.reply_control?.location;
        let label = root.querySelector('#qute-ip-location');
        if (!location || root.querySelector('#location')) {
            label?.remove();
            return;
        }
        if (!label) {
            label = document.createElement('div');
            label.id = 'qute-ip-location';
            date.after(label);
        }
        label.textContent = location;
    }

    customElements.whenDefined(tag).then(() => {
        const prototype = customElements.get(tag).prototype;
        if (prototype[marker]) return;
        prototype[marker] = true;
        const update = prototype.update;
        prototype.update = function (...args) {
            const result = Reflect.apply(update, this, args);
            showLocation(this);
            return result;
        };
        // Also cover components rendered before the script was injected.
        function visit(root) {
            for (const element of root.querySelectorAll('*')) {
                if (element.localName === tag) showLocation(element);
                if (element.shadowRoot) visit(element.shadowRoot);
            }
        }
        visit(document);
    });
})();
