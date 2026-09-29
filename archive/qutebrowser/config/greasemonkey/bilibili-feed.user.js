// ==UserScript==
// @name         Bilibili 精简推荐
// @namespace    voidlinux-config
// @version      1.0
// @description  普通视频推荐、PC/App 切换、扫码授权和真正的不感兴趣反馈。
// @match        https://www.bilibili.com/*
// @run-at       document-start
// @qute-js-world application
// @noframes
// @grant        none
// ==/UserScript==

function isEpisode(v) {
    return /(?:\/bangumi\/|bilibili:\/\/bangumi)/.test(v.redirect_url || v.uri || '');
}

function videos(items, mode, seen = new Set()) {
    return items.filter(v => {
        if (!v || v.goto !== 'av' || v.is_ad || v.isAd || v.ad_info || v.ad_cb ||
            v.card_goto?.includes('ad') || (v.creative_id && v.source_id === 5614)) return false;
        if (isEpisode(v) || (mode === 'app' && (!v.player_args || (v.player_args.type && v.player_args.type !== 'av')))) return false;
        const id = String(mode === 'app' ? v.param : v.id);
        if (!/^\d+$/.test(id) || seen.has(id)) return false;
        seen.add(id);
        return true;
    });
}

function cardInfo(v, source) {
    const count = n => n == null ? '' : n >= 10000 ? (n/10000).toFixed(1).replace(/\.0$/, '')+'万' : String(n);
    const appCount = icon => [1,2,3].map(i => [v['cover_left_icon_'+i],v['cover_left_text_'+i]]).find(x => x[0] === icon)?.[1] || '';
    const seconds = v.duration ?? v.player_args?.duration;
    const duration = seconds == null ? (v.cover_right_text || '') :
        (seconds >= 3600 ? Math.floor(seconds/3600)+':' : '') +
        String(Math.floor(seconds/60)%60).padStart(2,'0')+':'+String(seconds%60).padStart(2,'0');
    const date = v.pubdate ? new Date(v.pubdate*1000).toLocaleDateString('zh-CN',{month:'long',day:'numeric'}) :
        (v.desc || '').split('·').slice(1).join('·').trim();
    return {
        author:v.owner?.name || v.args?.up_name || (v.desc || '').split('·')[0].trim(),
        face:v.owner?.face || v.avatar?.cover || '', mid:v.owner?.mid || v.args?.up_id,
        play:source === 'app' ? appCount(1) : count(v.stat?.view),
        danmaku:source === 'app' ? appCount(3) : count(v.stat?.danmaku),
        duration,date,
    };
}

if (typeof module !== 'undefined') module.exports = {videos, cardInfo};
else (async () => {
    if (document.getElementById('qute-bili-style')) return;
    const home = location.pathname === '/';
    const style = document.createElement('style');
    style.id = 'qute-bili-style';
    style.textContent = `
        .ad-report, #slide_ad, .slide-ad-exp, .strip-ad, .video-card-ad-small,
        .video-card-ad-small-inner, .left-banner, .bili-feed-card:has(a[href*="cm.bilibili.com"]),
        .bili-video-card:has(a[href*="cm.bilibili.com"]) {display:none!important}
    ` + (home ? `
        html, body {min-height:100%;background:var(--bg1,#fff)!important}
        .bili-header__banner, .bili-header__channel, .header-channel, .channel-floor, .palette-button-wrap,
        .desktop-download-tip, .download-entry, .vip-entry {display:none!important}
        .bili-header .left-entry {display:none!important}
        .bili-header.large-header {height:44px!important;min-height:44px!important;background:none!important}
        .bili-header .bili-header__bar {height:44px!important;min-height:44px!important;position:relative!important;background:var(--bg1,#fff)!important;gap:12px;padding:0 6px!important}
        .bili-header__bar:not(:has(#qute-bili-toolbar)) {visibility:hidden}
        .bili-header .center-search-container {flex:1!important;min-width:0!important;margin:0!important}
        .bili-feed4-layout {display:block!important;width:100%!important;max-width:none!important;min-height:calc(100vh - 44px);margin:0!important;padding:4px 6px!important;box-sizing:border-box}
        .bili-feed4-layout > :not(#qute-bili-feed) {display:none!important}
        #qute-bili-feed {color:var(--text1,#18191c);font-size:14px}
        #qute-bili-feed button, #qute-bili-toolbar button, #qute-bili-login button {font:inherit;cursor:pointer;border:1px solid var(--line_regular,#ddd);border-radius:6px;padding:6px 8px;background:var(--bg1,#fff);color:inherit}
        #qute-bili-feed button:disabled {opacity:.5;cursor:default}
        #qute-bili-toolbar {display:flex;gap:6px;align-items:center;flex-shrink:0;white-space:nowrap;font-size:14px;color:var(--text1,#18191c)}
        #qute-bili-status {display:block;position:fixed;bottom:8px;left:8px;z-index:30;padding:4px 8px;border-radius:4px;background:var(--bg1,#fff);font-size:13px;color:var(--text2,#777)}
        #qute-bili-status:empty {display:none}
        #qute-bili-grid {display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px 6px}
        #qute-bili-grid article {min-width:0;position:relative}
        #qute-bili-grid .dismissed > .cover, #qute-bili-grid .dismissed > .info {visibility:hidden}
        #qute-bili-grid .dismissed-note {position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;color:var(--text3,#888);border:1px dashed #8883;border-radius:6px;font-size:12px}
        #qute-bili-grid .placeholder {pointer-events:none}
        #qute-bili-grid .placeholder .cover, #qute-bili-grid .placeholder .line {background:var(--bg2,#eee)}
        #qute-bili-grid .placeholder .line {height:10px;width:85%;border-radius:3px;margin-top:9px}
        #qute-bili-grid .placeholder .line:last-child {width:55%;margin-bottom:10px}
        #qute-bili-grid a {color:inherit;text-decoration:none}
        #qute-bili-grid .cover {display:block;position:relative;aspect-ratio:16/9;max-height:calc((100dvh - 72px)/3 - 50px);overflow:hidden;border-radius:6px;background:var(--bg2,#eee)}
        #qute-bili-grid .cover > img {width:100%;height:100%;object-fit:cover}
        #qute-bili-grid .cover video {position:absolute;inset:0;width:100%;height:100%;object-fit:contain;background:#000}
        #qute-bili-grid .stats {position:absolute;left:0;right:0;bottom:0;padding:18px 7px 5px;color:#fff;background:linear-gradient(transparent,#0009);font-size:12px;display:flex;gap:8px;pointer-events:none}
        #qute-bili-grid .stats .length {margin-left:auto}
        #qute-bili-grid .info {display:flex;gap:6px;margin-top:6px;font-size:10px;line-height:1.4}
        #qute-bili-grid .avatar {width:calc(4.2em + 2px);height:calc(4.2em + 2px);border-radius:50%;object-fit:cover;flex-shrink:0}
        #qute-bili-grid .text {min-width:0;flex:1}
        #qute-bili-grid .title {display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;height:2.8em;margin:0 0 2px;line-height:1.4}
        #qute-bili-grid .byline {display:flex;align-items:center;gap:6px;color:var(--text3,#888);font-size:inherit;line-height:1.4}
        #qute-bili-grid .author {flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
        #qute-bili-grid .date {flex-shrink:0;white-space:nowrap}
        #qute-bili-grid details {flex-shrink:0}
        #qute-bili-grid summary {cursor:pointer;list-style:none;padding:0 3px;font-size:inherit;line-height:inherit}
        #qute-bili-grid .reasons {position:absolute;top:0;left:0;width:100%;aspect-ratio:16/9;max-height:calc((100dvh - 72px)/3 - 50px);box-sizing:border-box;overflow:auto;z-index:5;background:var(--bg1,#fff);border:1px solid var(--line_regular,#ddd);border-radius:6px;display:flex;flex-direction:column;justify-content:safe center}
        #qute-bili-grid .reasons button {display:block;width:100%;border:0;text-align:left;white-space:normal;flex-shrink:0}
        #qute-bili-more {display:block;position:fixed;bottom:8px;right:8px;z-index:30}
        #qute-bili-more[hidden] {display:none}
        #qute-bili-login {background:var(--bg1,#fff);color:var(--text1,#18191c);border:1px solid #8886;border-radius:10px;padding:24px;text-align:center;max-width:340px}
        #qute-bili-login::backdrop {background:#0008}
        #qute-bili-login .qr {color-scheme:only light;background:#fff!important;padding:20px;width:max-content;margin:16px auto}
        #qute-bili-login .qr canvas, #qute-bili-login .qr img {color-scheme:only light;image-rendering:pixelated;filter:none!important}
        #qute-bili-login p {margin:12px 0;font-size:14px}
    ` : '');
    // 在首帧前注入；document-start 时 html/head 可能还没创建。
    function attachStyle() {
        const parent = document.head || document.documentElement;
        if (!parent) return false;
        parent.append(style);
        return true;
    }
    if (!attachStyle()) {
        const observer = new MutationObserver(() => {if (attachStyle()) observer.disconnect();});
        observer.observe(document, {childList:true,subtree:true});
    }
    if (!home) return;
    if (document.readyState === 'loading') {
        await new Promise(resolve => document.addEventListener('DOMContentLoaded',resolve,{once:true}));
    }
    const main = document.querySelector('.bili-feed4-layout');
    if (!main) return;

    function el(tag, text, cls) {
        const node = document.createElement(tag);
        if (text) node.textContent = text;
        if (cls) node.className = cls;
        return node;
    }
    function button(text, action) {
        const b = el('button', text);
        b.type = 'button';
        b.onclick = action;
        return b;
    }
    async function web(path, params, post = false) {
        const query = new URLSearchParams(params);
        if (post) {
            const csrf = document.cookie.match(/(?:^|;\s*)bili_jct=([^;]+)/)?.[1];
            if (!csrf) throw Error('请先登录 B站网页账号');
            query.set('csrf', csrf);
        }
        const response = await fetch('https://api.bilibili.com' + path + (post ? '' : '?' + query), {
            method:post ? 'POST' : 'GET', credentials:'include',
            body:post ? query : undefined, signal:AbortSignal.timeout(20000),
        });
        const data = await response.json();
        if (data.code !== 0) throw Object.assign(Error(data.message || 'B站请求失败'), {code:data.code});
        return data.data || {};
    }
    async function app(action, params = {}) {
        const bridge = window.__quteBili;
        if (!bridge) throw Error('App 桥接未加载，请重载 qute 配置后刷新首页');
        const response = await fetch(bridge.url + '/' + action, {
            method:'POST', headers:{'Content-Type':'application/json','X-Qute-Bili':bridge.key},
            body:JSON.stringify(params), signal:AbortSignal.timeout(25000),
        });
        const data = await response.json();
        if (data.error) throw Error(data.error);
        return data.data;
    }

    let mode = localStorage.getItem('qute-bili-mode') === 'app' ? 'app' : 'pc';
    let generation = 0, busy = false, page = 0, seen = new Set();
    let batches = [], batchIndex = -1, pending = [];
    const root = el('section'); root.id = 'qute-bili-feed';
    const toolbar = el('div'); toolbar.id = 'qute-bili-toolbar';
    const status = el('span'); status.id = 'qute-bili-status'; status.setAttribute('role','status');
    const grid = el('div'); grid.id = 'qute-bili-grid';
    const toggle = button('', () => change(mode === 'pc' ? 'app' : 'pc'));
    const previous = button('←', () => turn(-1)); previous.title = '上一批（左方向键）';
    const refresh = button('→', () => turn(1)); refresh.title = '下一批（右方向键）';
    const batchLabel = el('span','');
    const login = button('扫码授权', showLogin);
    const more = button('重试', load); more.id = 'qute-bili-more'; more.hidden = true;
    toolbar.append(toggle, previous, batchLabel, refresh, login);
    root.append(status, grid, more);
    (document.querySelector('.bili-header__bar') || root).prepend(toolbar);
    main.prepend(root);

    function card(v, source, epoch) {
        const node = el('article');
        const id = String(source === 'app' ? v.param : v.id);
        node.dataset.videoId = id;
        const url = 'https://www.bilibili.com/video/' + (v.bvid || 'av' + id) + '/';
        const cover = el('a', '', 'cover'); cover.href = url;
        const img = el('img'); img.loading = 'lazy'; img.alt = '';
        const pic = v.pic || v.cover || '';
        if (/^(https?:)?\/\//.test(pic)) img.src = pic.replace(/^http:/, 'https:') + '@480w_270h_1c.webp';
        const info = cardInfo(v, source);
        const stats = el('div', '', 'stats');
        if (info.play) stats.append(el('span', 'P'+info.play));
        if (info.danmaku) stats.append(el('span', 'D'+info.danmaku));
        stats.append(el('span',info.duration,'length'));
        cover.append(img, stats);
        preview(cover, v, id);
        const title = el('a', v.title, 'title'); title.href = url; title.title = v.title;
        for (const link of [cover, title]) {
            link.target = '_blank';
            link.rel = 'noopener';
        }
        const byline = el('div', '', 'byline');
        const author = el('a', info.author, 'author');
        author.title = info.author;
        if (info.mid) author.href = 'https://space.bilibili.com/'+info.mid;
        byline.append(author);
        if (info.date) byline.append(el('span', info.date, 'date'));
        const reasons = source === 'app' ? (v.three_point?.dislike_reasons || []) :
            [{id:1,name:'内容不感兴趣'}, {id:4,name:'不想看此UP主'}];
        if (reasons.length) {
            const menu = el('details');
            const dislike = el('summary', '⊘');
            dislike.title = '不感兴趣'; dislike.setAttribute('aria-label','不感兴趣');
            menu.append(dislike);
            menu.addEventListener('toggle', () => {
                if (!menu.open) return;
                stopPreview();
                grid.querySelectorAll('details[open]').forEach(other => {if (other !== menu) other.open = false;});
            });
            const options = el('div', '', 'reasons');
            for (const reason of reasons) {
                const option = button(reason.name, async () => {
                    if (option.disabled) return;
                    const buttons = options.querySelectorAll('button');
                    buttons.forEach(b => b.disabled = true);
                    try {
                        await feedback(false, v, source, reason.id);
                        if (epoch !== generation) return;
                        stopPreview();
                        node.classList.add('dismissed');
                        const note = el('div', '', 'dismissed-note');
                        const undo = button('撤销', null);
                        note.append(el('span', '已不感兴趣'), undo);
                        node.append(note);
                        status.textContent = '已提交：' + reason.name;
                        undo.onclick = async () => {
                            undo.disabled = true;
                            try {
                                await feedback(true, v, source, reason.id);
                                if (epoch !== generation) return;
                                node.classList.remove('dismissed'); note.remove();
                                status.textContent = '已向 B站撤销';
                            } catch (e) {status.textContent = e.message;}
                            finally {undo.disabled = false;}
                        };
                    } catch (e) {status.textContent = e.message;}
                    finally {buttons.forEach(b => b.disabled = false); menu.open = false;}
                });
                options.append(option);
            }
            menu.append(options); byline.append(menu);
        }
        const details = el('div','','info'), text = el('div','','text');
        if (/^(https?:)?\/\//.test(info.face)) {
            const avatar = el('img','','avatar'); avatar.src = info.face.replace(/^http:/,'https:');
            avatar.loading = 'lazy'; avatar.alt = ''; details.append(avatar);
        }
        text.append(title,byline);
        details.append(text); node.append(cover,details);
        return node;
    }
    let stopPreview = () => {};
    function preview(cover, v, id) {
        let timer, video, active = false, attempt = 0;
        function stop() {
            active = false; attempt++; clearTimeout(timer);
            if (video) {video.pause(); video.removeAttribute('src'); video.load(); video.remove(); video = null;}
        }
        cover.addEventListener('mouseenter', () => {
            stopPreview(); stopPreview = stop; active = true;
            const current = attempt;
            timer = setTimeout(async () => {
                try {
                    const cid = v.cid || v.player_args?.cid || (await web('/x/web-interface/view',{aid:id})).cid;
                    if (!active || current !== attempt || !cover.isConnected) return;
                    const data = await web('/x/player/playurl',{avid:id,cid,qn:16,fnval:1});
                    if (!active || current !== attempt || !cover.isConnected) return;
                    const src = data.durl?.[0]?.url || data.dash?.video?.[0]?.baseUrl;
                    if (!src) return;
                    video = el('video'); video.muted = true; video.loop = true; video.playsInline = true;
                    video.src = src.replace(/^http:/,'https:'); cover.append(video);
                    await video.play();
                } catch {if (current === attempt) stop();} // 预览失败仍保留封面。
            }, 650);
        });
        cover.addEventListener('mouseleave',stop);
    }
    document.addEventListener('visibilitychange', () => {if (document.hidden) stopPreview();});
    document.addEventListener('scroll', () => stopPreview(), {passive:true});
    async function feedback(cancel, v, source, reason) {
        if (source === 'app') return app(cancel ? 'undo' : 'dislike', {id:v.param, reason});
        return web('/x/web-interface/feedback/dislike' + (cancel ? '/cancel' : ''), {
            app_id:100, platform:5, from_spmid:'', spmid:'333.1007.0.0', goto:'av',
            id:v.id, mid:v.owner?.mid || 0, track_id:v.track_id || '', feedback_page:1, reason_id:reason,
        }, true);
    }
    async function change(next) {
        stopPreview();
        const keepCards = next === mode && grid.querySelector('article');
        mode = next; localStorage.setItem('qute-bili-mode', mode);
        generation++; busy = false; page = 0; seen = new Set();
        batches = []; batchIndex = -1; pending = []; batchLabel.textContent = '';
        previous.disabled = true;
        if (!keepCards) {
            grid.replaceChildren(...Array.from({length:12}, () => {
                const placeholder = el('div','','placeholder');
                placeholder.setAttribute('aria-hidden','true');
                placeholder.append(el('div','','cover'),el('div','','line'),el('div','','line'),el('div','','line'));
                return placeholder;
            }));
        }
        toggle.textContent = (mode === 'pc' ? '网页推荐' : 'App 推荐') + ' ⇄';
        toggle.title = '切换到' + (mode === 'pc' ? 'App 推荐' : '网页推荐');
        await load();
    }
    function showBatch(index) {
        stopPreview(); batchIndex = index;
        grid.replaceChildren(...batches[index]);
        batchLabel.textContent = String(index+1);
        previous.disabled = index === 0;
        status.textContent = '';
        window.scrollTo(0,0);
    }
    function turn(direction) {
        if (busy || document.querySelector('#qute-bili-login[open]')) return;
        const index = batchIndex + direction;
        if (index < 0) return;
        if (index < batches.length) showBatch(index);
        else load();
    }
    const editing = () => document.activeElement?.matches('input,textarea,select') || document.activeElement?.isContentEditable;
    document.addEventListener('keydown', e => {
        if (editing() || e.ctrlKey || e.metaKey || e.shiftKey || e.repeat) return;
        if (e.altKey) {
            if (e.key.toLowerCase() === 'r') {
                e.preventDefault();
                if (!busy && !document.querySelector('#qute-bili-login[open]')) change(mode === 'pc' ? 'app' : 'pc');
            }
            return;
        }
        if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
        e.preventDefault();
        turn(e.key === 'ArrowLeft' ? -1 : 1);
    });
    // 触控板一段连续横滑只翻一次，惯性停止后才能再次翻页。
    let swipeTotal = 0, swipeUsed = false, swipeTimer;
    document.addEventListener('wheel', e => {
        if (editing() || e.ctrlKey || Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return;
        e.preventDefault();
        clearTimeout(swipeTimer);
        swipeTimer = setTimeout(() => { swipeTotal = 0; swipeUsed = false; }, 250);
        swipeTotal += e.deltaX * (e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? innerWidth : 1);
        if (!swipeUsed && Math.abs(swipeTotal) >= 70) {
            swipeUsed = true;
            turn(swipeTotal > 0 ? 1 : -1);
        }
    }, {passive:false});
    let touchStart;
    document.addEventListener('touchstart', e => {
        touchStart = !editing() && e.touches.length === 1 ? {x:e.touches[0].clientX,y:e.touches[0].clientY} : null;
    }, {passive:true});
    document.addEventListener('touchend', e => {
        if (!touchStart) return;
        const dx = e.changedTouches[0].clientX - touchStart.x, dy = e.changedTouches[0].clientY - touchStart.y;
        touchStart = null;
        if (Math.abs(dx) >= 70 && Math.abs(dx) > Math.abs(dy) * 1.5) turn(dx < 0 ? 1 : -1);
    }, {passive:true});
    document.addEventListener('touchcancel', () => { touchStart = null; });
    const episodeCache = new Map();
    async function checkEpisodes(list, source) {
        let cursor = 0;
        const result = [];
        // av 也可能跳转番剧；限 4 个并发查详情，缓存本页已核验的结果。
        await Promise.all(Array.from({length:Math.min(4,list.length)}, async () => {
            while (cursor < list.length) {
                const i = cursor++, v = list[i], id = String(source === 'app' ? v.param : v.id);
                if (!episodeCache.has(id)) {
                    try {episodeCache.set(id, isEpisode(await web('/x/web-interface/view',{aid:id})));}
                    catch (e) {
                        if (e.code !== -404) throw e;
                        episodeCache.set(id,true); // 已失效的视频只跳过本张。
                    }
                }
                if (!episodeCache.get(id)) result[i] = v;
            }
        }));
        return result.filter(Boolean);
    }
    async function load() {
        if (busy) return;
        const epoch = generation, source = mode;
        busy = true; more.hidden = true; more.disabled = true;
        refresh.disabled = true;
        grid.setAttribute('aria-busy','true');
        status.textContent = '正在加载' + (source === 'app' ? 'App' : '网页') + '推荐…';
        try {
            if (source === 'app') {
                const authorized = (await app('status')).logged_in;
                if (epoch !== generation) return;
                login.textContent = authorized ? '重新授权' : '扫码授权';
                if (!authorized) {
                    status.textContent = 'App 推荐需要扫码授权';
                    showLogin(); return;
                }
            }
            // 每次点击最多请求两批；过滤后不足 12 张就显示实际数量。
            for (let attempts=0; pending.length<12 && attempts<2; attempts++) {
                const data = source === 'app' ? await app('feed') :
                    await web('/x/web-interface/wbi/index/top/feed/rcmd', {
                        fresh_type:8, fresh_idx:++page, fresh_idx_1h:page, ps:20,
                        web_location:1430650, feed_version:'V8', homepage_ver:1,
                    });
                if (epoch !== generation) return;
                const candidates = videos(source === 'app' ? data.items || [] : data.item || [], source);
                const list = await checkEpisodes(candidates.filter(v => !seen.has(String(source === 'app' ? v.param : v.id))), source);
                if (epoch !== generation) return;
                list.forEach(v => seen.add(String(source === 'app' ? v.param : v.id)));
                pending.push(...list);
            }
            if (pending.length) {
                batches.push(pending.splice(0,12).map(v => card(v, source, epoch)));
                showBatch(batches.length-1);
            } else status.textContent = '没有新的普通视频，稍后再试';
        } catch (e) {if (epoch === generation) {status.textContent = e.message; more.hidden = false;}}
        finally {
            if (epoch === generation) {
                grid.querySelectorAll('.placeholder').forEach(x => x.remove());
                grid.setAttribute('aria-busy','false');
                busy = false; more.disabled = false; refresh.disabled = false;
            }
        }
    }
    async function showLogin() {
        if (document.getElementById('qute-bili-login')) return;
        const dialog = el('dialog'); dialog.id = 'qute-bili-login';
        const qr = el('div', '', 'qr');
        const hint = el('p', '正在获取二维码…');
        let run = 0;
        const close = button('关闭', () => dialog.close());
        const retry = button('刷新二维码', create);
        dialog.append(el('p','用 B站 App 扫码确认授权'), qr,
            el('p','确认页面可能显示为电视端设备'), hint, retry, close);
        dialog.onclose = () => {run++; dialog.remove();};
        document.body.append(dialog); dialog.showModal();
        async function create() {
            const current = ++run;
            retry.disabled = true; hint.textContent = '正在获取二维码…'; qr.replaceChildren();
            try {
                const data = await app('qr');
                if (current !== run) return;
                new window.__quteQR(qr, {text:data.url,width:256,height:256,correctLevel:window.__quteQR.CorrectLevel.M});
                hint.textContent = '等待扫码';
                while (current === run) {
                    await new Promise(resolve => setTimeout(resolve,1800));
                    if (current !== run) return;
                    const result = await app('poll', {auth_code:data.auth_code});
                    if (current !== run) return;
                    if (result.code === 0) {
                        dialog.close(); login.textContent = '重新授权';
                        if (mode === 'app') await change('app');
                        return;
                    }
                    if (result.code === 86038) throw Error('二维码已过期，请刷新');
                    if (![86039,86090].includes(result.code)) throw Error(result.message || '授权失败');
                    hint.textContent = result.code === 86090 ? '请在手机上确认' : '等待扫码';
                }
            } catch (e) {if (current === run) hint.textContent = e.message;}
            finally {if (current === run) retry.disabled = false;}
        }
        create();
    }
    change(mode);
})();
