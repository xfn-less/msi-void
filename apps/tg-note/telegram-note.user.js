// ==UserScript==
// @name         Telegram File Note
// @namespace    local.telegram.file-note
// @version      0.2.0
// @description  当前群的纯文本便签：Go 文件后端、Ctrl+S 保存、未保存时浅红提示
// @match        https://web.telegram.org/k/*
// @run-at       document-start
// @grant        GM_xmlhttpRequest
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @connect      memo.xfnss.top
// ==/UserScript==

(() => {
  'use strict';
  const MAX_BYTES = 256 * 1024;
  const notes = new Map();
  const stored = GM_getValue('drafts', []);
  const drafts = new Map(Array.isArray(stored) ? stored.filter(x => Array.isArray(x) && typeof x[0] === 'string' && typeof x[1] === 'string') : []);
  let config = GM_getValue('config', {base: 'https://memo.xfnss.top:8443', token: ''});
  let collapsed = GM_getValue('collapsed', false);
  let currentTitle = '', observedTitle = null, changeTimer;
  let showingList = false, changingChat = false, wasFilled = false;
  let expanded = GM_getValue('expanded', false);
  let floatingPosition = GM_getValue('position', null);
  const files = {titles: [], loading: false, message: ''};
  let host, panel, editor, titleLabel, saveButton, refreshButton, collapseButton, fillButton, backButton, fileList, status;


  // Capture before Telegram's document listeners: Shadow DOM retargets the
  // textarea to our host div, which its global shortcuts mistake for chat focus.
  // Stop propagation only; native typing, selection, IME and clipboard still work.
  for (const type of ['keydown', 'keypress', 'keyup', 'copy', 'cut', 'paste']) {
    window.addEventListener(type, event => {
      if (!host || !event.composedPath().includes(host)) return;
      event.stopImmediatePropagation();
      if (type === 'keydown' && !event.isComposing &&
          (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
        event.preventDefault();
        saveNote();
      }
    }, true);
  }

  // Telegram DOM compatibility is contained here. Preserve the exact title.
  function getCurrentChatTitle() {
    if (!location.hash.slice(1)) return '';
    const candidates = document.querySelectorAll('#column-center .chat-info .peer-title, .chat-info .peer-title');
    const node = [...candidates].find(element => {
      const rect = element.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0 && getComputedStyle(element).visibility !== 'hidden';
    });
    if (!node) return '';
    const copy = node.cloneNode(true);
    for (const image of copy.querySelectorAll('img[alt]')) image.replaceWith(document.createTextNode(image.alt));
    return copy.textContent || '';
  }

  function request(method, title, content) {
    if (!config.base || !config.token) return Promise.reject(new Error('请先点设置，填写服务器地址和 Token'));
    return new Promise((resolve, reject) => {
      GM_xmlhttpRequest({
        method,
        url: title === null ? `${config.base}/api/notes` : `${config.base}/api/note?title=${encodeURIComponent(title)}`,
        headers: {Authorization: `Bearer ${config.token}`, 'Content-Type': 'text/plain; charset=utf-8'},
        data: content,
        anonymous: true,
        timeout: 12000,
        onload(response) {
          if (response.finalUrl && new URL(response.finalUrl).origin !== new URL(config.base).origin) {
            reject(new Error('接口重定向到了其他站点')); return;
          }
          if (response.status === 200 || response.status === 204 || (method === 'GET' && title !== null && response.status === 404)) resolve(response);
          else reject(new Error(response.status === 401 ? 'Token 无效' : `HTTP ${response.status}`));
        },
        onerror() { reject(new Error('无法连接服务器')); },
        ontimeout() { reject(new Error('请求超时')); },
        onabort() { reject(new Error('请求已取消')); },
      });
    });
  }

  function rememberDraft(note) {
    if (note.text === note.saved) drafts.delete(note.title);
    else drafts.set(note.title, note.text);
    GM_setValue('drafts', [...drafts]);
  }

  function noteFor(title) {
    if (!notes.has(title)) notes.set(title, {title, text: drafts.get(title) ?? '', saved: '', ready: false, loading: false, saving: false, message: '', sequence: 0});
    return notes.get(title);
  }

  async function fetchNote(title, discardDraft = false) {
    const note = noteFor(title);
    if (note.loading || note.saving) return;
    const sequence = ++note.sequence;
    note.loading = true;
    note.ready = false;
    note.message = '读取中…';
    renderNote();
    try {
      const response = await request('GET', title);
      if (sequence !== note.sequence) return;
      note.saved = response.status === 404 ? '' : response.responseText;
      if (discardDraft) drafts.delete(title);
      note.text = drafts.has(title) ? drafts.get(title) : note.saved;
      note.ready = true;
      note.message = response.status === 404 ? '未找到便签，输入后保存即可' : '已读取';
      rememberDraft(note);
    } catch (error) {
      note.message = `读取失败：${error.message}`;
    } finally {
      note.loading = false;
      renderNote();
    }
  }

  async function saveNote() {
    if (showingList) return;
    const note = notes.get(currentTitle);
    if (!note?.ready || note.loading || note.saving) return;
    const text = note.text;
    if (new TextEncoder().encode(text).length > MAX_BYTES) {
      note.message = '保存失败：正文不能超过 256 KiB'; renderNote(); return;
    }
    note.saving = true;
    note.message = '保存中…';
    renderNote();
    try {
      await request('PUT', note.title, text);
      note.saved = text;
      rememberDraft(note);
      note.message = '已保存';
      if (!files.titles.includes(note.title)) files.titles.push(note.title);
    } catch (error) {
      note.message = `保存失败：${error.message}，草稿已保留`;
    } finally {
      note.saving = false;
      renderNote();
    }
  }

  async function fetchFiles() {
    if (files.loading) return;
    files.loading = true;
    files.message = '读取文件列表…';
    renderNote();
    try {
      const response = await request('GET', null);
      const data = JSON.parse(response.responseText);
      if (!Array.isArray(data.titles) || !data.titles.every(title => typeof title === 'string')) throw new Error('文件列表格式错误');
      files.titles = data.titles;
      files.message = `${files.titles.length} 个文件`;
    } catch (error) {
      files.message = `读取失败：${error.message}`;
    } finally {
      files.loading = false;
      renderNote();
    }
  }

  function openFile(title) {
    currentTitle = title;
    showingList = false;
    noteFor(title);
    fetchNote(title);
    renderNote();
  }

  function showFiles() {
    currentTitle = '';
    showingList = true;
    fetchFiles();
    renderNote();
  }

  function renderFiles() {
    const titles = [...new Set([...files.titles, ...drafts.keys()])].sort((a, b) => a.localeCompare(b));
    fileList.replaceChildren();
    for (const title of titles) {
      const button = document.createElement('button');
      button.className = 'file-entry';
      button.textContent = `${title}.txt`;
      button.classList.toggle('file-dirty', drafts.has(title));
      button.title = drafts.has(title) ? '有未保存草稿' : title;
      button.addEventListener('click', () => openFile(title));
      fileList.append(button);
    }
    if (!titles.length && !files.loading) {
      const empty = document.createElement('p');
      empty.className = 'empty';
      empty.textContent = files.message.startsWith('读取失败') ? files.message : '还没有便签文件';
      fileList.append(empty);
    }
  }

  function isFilled() { return !observedTitle || expanded; }

  function renderNote() {
    if (!host) return;
    host.hidden = changingChat;
    const filled = isFilled();
    panel.classList.toggle('filled', filled);
    panel.classList.toggle('collapsed', collapsed && !filled);
    panel.classList.toggle('dirty', !showingList && drafts.has(currentTitle));
    titleLabel.textContent = showingList ? '全部便签' : currentTitle;
    titleLabel.title = titleLabel.textContent;
    editor.hidden = showingList;
    fileList.hidden = !showingList;
    saveButton.hidden = showingList;
    backButton.hidden = Boolean(observedTitle) || showingList;
    fillButton.hidden = !observedTitle;
    fillButton.textContent = expanded ? '还原' : '铺满';
    fillButton.setAttribute('aria-label', fillButton.textContent);
    collapseButton.hidden = filled;
    collapseButton.textContent = collapsed ? '+' : '−';
    collapseButton.title = collapsed ? '展开' : '折叠';
    collapseButton.setAttribute('aria-label', collapseButton.title);
    if (showingList) {
      renderFiles();
      refreshButton.disabled = files.loading;
      status.textContent = files.message;
    } else {
      const note = notes.get(currentTitle);
      if (note) {
        if (editor.value !== note.text) editor.value = note.text;
        editor.disabled = !note.ready || note.loading;
        saveButton.disabled = !note.ready || note.loading || note.saving;
        refreshButton.disabled = note.loading || note.saving;
        status.textContent = drafts.has(currentTitle) ? `未保存 · ${note.message}` : note.message;
      }
    }
    applyLayout();
  }

  function watchChatChange() {
    const title = getCurrentChatTitle();
    if (title === observedTitle) return;
    observedTitle = title;
    clearTimeout(changeTimer);
    changingChat = true;
    host.hidden = true;
    changeTimer = setTimeout(() => {
      changingChat = false;
      if (!title) showFiles();
      else openFile(title);
    }, 300);
  }

  // Geometry is kept separate from note rendering so Telegram sidebar resizes
  // and the empty-chat screen use the same right-hand region.
  function getChatBounds() {
    const center = document.querySelector('#column-center')?.getBoundingClientRect();
    if (center?.width > 0 && center.height > 0) {
      const left = Math.max(0, center.left), top = Math.max(0, center.top);
      return {left, top, width: Math.max(0, Math.min(innerWidth, center.right) - left), height: Math.max(0, Math.min(innerHeight, center.bottom) - top)};
    }
    const sidebar = document.querySelector('#column-left')?.getBoundingClientRect();
    if (!sidebar?.width) return null;
    const left = Math.min(innerWidth, Math.max(0, sidebar.right));
    return {left, top: 0, width: innerWidth - left, height: innerHeight};
  }

  function applyLayout() {
    if (!host || changingChat) return;
    if (isFilled()) {
      const bounds = getChatBounds();
      host.hidden = !bounds || bounds.width <= 0 || bounds.height <= 0;
      if (host.hidden) return;
      Object.assign(host.style, {left: `${bounds.left}px`, top: `${bounds.top}px`, width: `${bounds.width}px`, height: `${bounds.height}px`, maxWidth: 'none', right: 'auto'});
      wasFilled = true;
    } else {
      host.hidden = false;
      Object.assign(host.style, {width: '360px', height: 'auto', maxWidth: 'calc(100vw - 12px)'});
      if (wasFilled) {
        host.style.left = `${Number.isFinite(floatingPosition?.left) ? floatingPosition.left : innerWidth - 384}px`;
        host.style.top = `${Number.isFinite(floatingPosition?.top) ? floatingPosition.top : 90}px`;
      }
      wasFilled = false;
      clampPosition();
    }
  }

  function clampPosition() {
    if (host.hidden) return;
    const rect = host.getBoundingClientRect();
    host.style.left = `${Math.max(0, Math.min(rect.left, innerWidth - rect.width))}px`;
    host.style.top = `${Math.max(0, Math.min(rect.top, innerHeight - rect.height))}px`;
    host.style.right = 'auto';
  }

  function setupDragging(header) {
    let drag = null;
    header.addEventListener('pointerdown', event => {
      if (isFilled() || event.button !== 0 || event.target.closest('button')) return;
      const rect = host.getBoundingClientRect();
      drag = {x: event.clientX - rect.left, y: event.clientY - rect.top};
      header.setPointerCapture(event.pointerId);
      event.preventDefault();
    });
    header.addEventListener('pointermove', event => {
      if (!drag) return;
      host.style.left = `${event.clientX - drag.x}px`;
      host.style.top = `${event.clientY - drag.y}px`;
      host.style.right = 'auto';
      clampPosition();
    });
    const end = () => {
      if (!drag) return;
      drag = null;
      floatingPosition = {left: parseFloat(host.style.left), top: parseFloat(host.style.top)};
      GM_setValue('position', floatingPosition);
    };
    header.addEventListener('pointerup', end);
    header.addEventListener('pointercancel', end);
  }

  function configure() {
    if ([...notes.values()].some(note => note.saving || note.loading)) { alert('请等待当前请求完成'); return; }
    const input = prompt('服务器地址（公网使用 HTTPS；本机可用 http://127.0.0.1:8790）', config.base);
    if (input === null) return;
    let base;
    try {
      const url = new URL(input.trim());
      if (url.username || url.password || url.search || url.hash || (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)))) throw new Error();
      base = url.href.replace(/\/+$/, '');
    } catch { alert('请填写有效的 HTTPS 地址，或本机 localhost HTTP 地址'); return; }
    if (config.base && base !== config.base && drafts.size) { alert('切换服务器前，请先保存或放弃未保存草稿'); return; }
    const token = prompt('服务器 TG_NOTE_TOKEN', config.token);
    if (token === null) return;
    if (token.trim().length < 32) { alert('Token 至少 32 个字符'); return; }
    config = {base, token: token.trim()};
    GM_setValue('config', config);
    notes.clear();
    if (showingList) fetchFiles();
    else if (currentTitle) fetchNote(currentTitle);
  }

  function createPanel() {
    host = document.createElement('div');
    host.id = 'tg-file-note';
    host.hidden = true;
    Object.assign(host.style, {position: 'fixed', zIndex: '2147483647', top: '90px', right: '24px', width: '360px', maxWidth: 'calc(100vw - 12px)'});
    const position = floatingPosition;
    if (Number.isFinite(position?.left) && Number.isFinite(position?.top)) Object.assign(host.style, {left: `${position.left}px`, top: `${position.top}px`, right: 'auto'});
    const root = host.attachShadow({mode: 'open'});
    for (const type of ['beforeinput', 'input', 'compositionstart', 'compositionupdate', 'compositionend', 'pointerdown', 'mousedown', 'click', 'dblclick', 'contextmenu', 'focusin', 'focusout']) {
      root.addEventListener(type, event => event.stopPropagation());
    }
    // Static UI only. All titles and note content use textContent / textarea.value.
    root.innerHTML = `
      <style>
        :host { color-scheme: dark; }
        * { box-sizing: border-box; }
        [hidden] { display:none !important; }
        .panel { --bg:#242426; --field:#202022; --line:#454548; --text:#f2f2f3; background:var(--bg); color:var(--text); border:1px solid var(--line); border-radius:10px; box-shadow:0 8px 28px #0004; overflow:hidden; font:13px/1.5 system-ui,sans-serif; }
        .panel.dirty { --bg:#f3dddc; --field:#f8e8e6; --line:#d9b5b3; --text:#583b3b; color-scheme:light; }
        header { display:flex; align-items:center; gap:4px; padding:7px; cursor:move; touch-action:none; user-select:none; border-bottom:1px solid var(--line); }
        button { color:inherit; font:inherit; background:transparent; border:0; border-radius:5px; padding:4px 7px; cursor:pointer; }
        button:hover { background:#8882; }
        button:focus-visible,textarea:focus-visible { outline:2px solid #ab8b82; outline-offset:-2px; }
        button:disabled { opacity:.45; cursor:default; }
        .title { display:block; padding:4px 7px; flex:1; min-width:0; text-align:left; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; font-weight:600; }
        .drag { padding:0 4px; opacity:.6; }
        textarea { display:block; width:100%; height:220px; max-height:calc(70vh - 100px); min-height:70px; resize:vertical; border:0; padding:12px; background:var(--field); color:inherit; font:13px/1.7 ui-monospace,monospace; }
        footer { display:flex; align-items:center; gap:6px; border-top:1px solid var(--line); padding:6px 9px; }
        .status { flex:1; min-width:0; font-size:11px; overflow-wrap:anywhere; }
        .save { border:1px solid var(--line); white-space:nowrap; }
        .collapsed textarea,.collapsed footer { display:none; }
        .collapsed header { border-bottom:0; }
        .filled { height:100%; display:flex; flex-direction:column; border-radius:0; box-shadow:none; }
        .filled header { cursor:default; flex-shrink:0; }
        .filled .drag { display:none; }
        .filled textarea { flex:1; height:auto; min-height:0; max-height:none; resize:none; padding:20px; font-size:14px; }
        .filled footer { flex-shrink:0; }
        .files { flex:1; overflow:auto; min-height:0; padding:16px; }
        .file-entry { display:block; width:100%; text-align:left; padding:14px 12px; border-bottom:1px solid var(--line); border-radius:0; overflow-wrap:anywhere; }
        .file-dirty { color:#f0b8b3; }
        .empty { margin:12px; opacity:.7; }
      </style>
      <section class="panel" aria-label="群便签">
        <header><span class="drag" title="拖动">⋮</span><button class="back" aria-label="全部文件" hidden>← 全部文件</button><span class="title"></span><button class="fill" aria-label="铺满">铺满</button><button class="refresh" aria-label="刷新" title="刷新">↻</button><button class="settings" aria-label="设置" title="设置">设置</button><button class="collapse" aria-label="折叠" title="折叠">−</button></header>
        <div class="files" aria-label="便签文件列表" hidden></div>
        <textarea aria-label="便签内容" spellcheck="false" placeholder="输入便签，Ctrl+S 保存"></textarea>
        <footer><span class="status" role="status"></span><button class="save">保存</button></footer>
      </section>`;
    panel = root.querySelector('.panel');
    editor = root.querySelector('textarea');
    titleLabel = root.querySelector('.title');
    fillButton = root.querySelector('.fill');
    backButton = root.querySelector('.back');
    fileList = root.querySelector('.files');
    saveButton = root.querySelector('.save');
    refreshButton = root.querySelector('.refresh');
    collapseButton = root.querySelector('.collapse');
    status = root.querySelector('.status');
    editor.addEventListener('input', () => {
      const note = notes.get(currentTitle);
      note.text = editor.value;
      note.message = note.saving ? '保存中，新增修改尚未保存' : 'Ctrl+S 或点保存';
      rememberDraft(note);
      renderNote();
    });
    saveButton.addEventListener('click', saveNote);
    refreshButton.addEventListener('click', () => {
      if (showingList) { fetchFiles(); return; }
      if (drafts.has(currentTitle) && !confirm('放弃这个群的未保存草稿，重新读取服务器文件？')) return;
      fetchNote(currentTitle, true);
    });
    root.querySelector('.settings').addEventListener('click', configure);
    collapseButton.addEventListener('click', () => { collapsed = !collapsed; GM_setValue('collapsed', collapsed); renderNote(); });
    backButton.addEventListener('click', showFiles);
    fillButton.addEventListener('click', () => {
      expanded = !expanded;
      GM_setValue('expanded', expanded);
      renderNote();
    });
    setupDragging(root.querySelector('header'));
    document.body.append(host);
    addEventListener('resize', applyLayout);
    addEventListener('beforeunload', event => { if (drafts.size) { event.preventDefault(); event.returnValue = ''; } });
  }

  function start() {
    if (document.getElementById('tg-file-note')) return;
    createPanel();
    GM_registerMenuCommand('设置便签服务器', configure);
    setInterval(() => { watchChatChange(); applyLayout(); }, 250);
    watchChatChange();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, {once: true});
  else start();
})();
