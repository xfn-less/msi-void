# Text Vault River View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the split search/editor application with one flat, full-text river controlled by small Vim-style Normal, Edit, Add, Search, and Command modes.

**Architecture:** Keep the encrypted repository, save coordinator, sync coordinator, server API, and SQLite schema. Add a pure mode reducer and a focused VanJS river component; `app.js` composes them and only writes drafts into the repository when Escape commits Edit or Add.

**Tech Stack:** Go 1.25, SQLite, browser Web Crypto, VanJS 1.6.1, native ES modules, Node test runner, Playwright 1.58.2.

**Spec:** `docs/superpowers/specs/2026-09-07-text-vault-river-view-design.md`

## Global Constraints

- No database migration or backend API change.
- No build step and no new runtime dependency.
- Every entry is flat and ordered by `createdAt` ascending; edits never reorder it.
- Only Escape commits an Edit/Add draft; blur, visibility changes, and timers do not.
- Incremental pull, conflict preservation, quarantine, and cross-tab automatic unlock remain active.
- The UI remains usable on desktop and iPhone with the same DOM structure.

---

### Task 1: Chronological Full-Entry Query

**Files:**
- Modify: `apps/text-vault/web/js/repository.js`
- Modify: `apps/text-vault/web/js/repository.test.js`

**Interfaces:**
- Consumes: repository entry objects already validated by `validateObject()`.
- Produces: `repository.queryEntries(query: string): Entry[]`, returning cloned or read-only-use entry values whose text contains the case-insensitive trimmed query, sorted by `createdAt` ascending then `id` ascending.

- [ ] **Step 1: Write the failing query tests**

Add tests that insert entries whose `createdAt` and `updatedAt` disagree, assert `queryEntries("")` follows `createdAt`, assert editing does not reorder them, and assert `queryEntries("EXAMPLE.com")` returns full entry objects rather than snippets.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `node --test web/js/repository.test.js`

Expected: FAIL because `repository.queryEntries` is undefined.

- [ ] **Step 3: Implement the minimal query**

Inside `createRepository`, add:

```js
function queryEntries(query) {
  const needle = String(query ?? "").trim().toLocaleLowerCase();
  return [...objects.values()]
    .filter(object => object.kind === "entry" && (!needle || object.text.toLocaleLowerCase().includes(needle)))
    .sort((left, right) => left.createdAt.localeCompare(right.createdAt) || left.id.localeCompare(right.id));
}
```

Expose `queryEntries` without changing legacy `search()` until the old UI is removed.

- [ ] **Step 4: Run the focused and complete unit suites**

Run: `node --test web/js/repository.test.js && npm run test:unit`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/text-vault/web/js/repository.js apps/text-vault/web/js/repository.test.js
git commit -m "feat: query vault entries chronologically"
```

### Task 2: Pure Vim Mode State Machine

**Files:**
- Create: `apps/text-vault/web/js/modes.js`
- Create: `apps/text-vault/web/js/modes.test.js`
- Delete: `apps/text-vault/web/js/commands.js`
- Delete: `apps/text-vault/web/js/commands.test.js`

**Interfaces:**
- Consumes: normalized keyboard events and bottom-input strings supplied by the view.
- Produces: `createModes()` with `state()`, `enterEdit(id, text)`, `enterAdd()`, `enterSearch(query)`, `enterCommand()`, `setDraft(text)`, `escape()`, and `executeCommand(value)`.
- `escape()` returns `{type: "edit", id, text}`, `{type: "add", text}`, `{type: "search", query}`, `{type: "cancel"}`, or `{type: "none"}` and leaves Normal mode.
- `executeCommand(":changepwd")` returns `{type: "change-password"}`; other values return `{type: "error", message: "未知命令"}`.

- [ ] **Step 1: Write failing state transition tests**

Cover Normal → Edit/Add/Search/Command, changed Edit Escape, unchanged Edit Escape, whitespace-only Add Escape, Search Escape preserving its query, `:changepwd`, unknown commands, and the invariant that setting a draft does not call repository or network code.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `node --test web/js/modes.test.js`

Expected: FAIL because `modes.js` does not exist.

- [ ] **Step 3: Implement the reducer-sized module**

Store only `{name, id, original, draft, query}` in closure state. Return copied state from `state()`. Strip exactly the leading `/` or `:` marker when returning search queries or parsing commands; do not trim saved entry text except when deciding whether a new entry is empty.

- [ ] **Step 4: Remove the legacy command module and run unit tests**

Run: `npm run test:unit`

Expected: PASS with mode tests replacing command tests.

- [ ] **Step 5: Commit**

```bash
git add apps/text-vault/web/js/modes.js apps/text-vault/web/js/modes.test.js apps/text-vault/web/js/commands.js apps/text-vault/web/js/commands.test.js
git commit -m "feat: add vim-style vault modes"
```

### Task 3: River UI and Explicit Escape Save

**Files:**
- Create: `apps/text-vault/web/js/river.js`
- Create: `apps/text-vault/web/js/river.test.js`
- Modify: `apps/text-vault/web/js/app.js`
- Modify: `apps/text-vault/web/styles.css`

**Interfaces:**
- Consumes: `{repository, saver, sync, key, api, tabSession}` from `openVault()` and `createModes()` from Task 2.
- Produces: `renderRiverApplication(dependencies)` which mounts the authenticated UI and returns `{destroy()}` for listeners/timers.
- Produces pure helpers `nextIndex(index, length, direction)`, `modeForKey(eventLike)`, and `selectedSearchText(selection)` for unit testing.

- [ ] **Step 1: Write failing helper tests**

Test bounded `j/k` navigation (no wrap), shortcut suppression in text controls and during composition, `o`, `/`, `:`, `i`, Enter, Escape dispatch, and trimmed non-empty selected text for Ctrl/Cmd+Enter.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `node --test web/js/river.test.js`

Expected: FAIL because `river.js` does not exist.

- [ ] **Step 3: Implement the river component**

Render a semantic list of full-text entries with a bullet and `white-space: pre-wrap`. Replace only the active entry body with an auto-growing `textarea`. Maintain the selection by entry ID; when filtering removes it, select the first match. Prevent outside clicks from changing the active entry while Edit/Add is active.

Use one bottom `textarea`:

- `o` sets Add with an empty value.
- `/` sets Search with `/${currentQuery}` selected after the slash and filters on every input.
- `:` sets Command with `:`.
- Escape in Edit/Add calls the mode action, updates/creates the repository object, calls `await sync.pull()` best-effort, then calls `saver.save()`.
- Escape in Search writes `#q=` and returns Normal without saving.
- Enter in Command runs `:changepwd` or shows `未知命令`.

Use a native `dialog` shared by the gear button and `:changepwd`. It contains two password inputs with `minlength=16`; matching values run `rewrapVault`, `api.rekey`, and refresh `tabSession.offer`.

Remove `saver.schedule()` calls and the blur/visibility autosave listeners. Keep `beforeunload` active for both an uncommitted mode draft and repository pending changes. Keep sync polling and focus pull. Keep query serialization in `#q=`.

- [ ] **Step 4: Replace the old app composition**

Make `app.js` retain setup/unlock/openVault and delegate the authenticated UI to `renderRiverApplication`. Delete old split-pane rendering, selection button, mobile history pane, `/s`, and old inline password-command flow.

- [ ] **Step 5: Reduce CSS to the four-area dark layout**

Implement the 4px status strip, unobtrusive gear, scrolling centered river, bullet column, selected row, active textarea, bottom wrapping textarea, password dialog, and one small-screen media rule. Map `data-state=editing` to green, `saving` to gray, `clean` to background, and `failed` to red.

- [ ] **Step 6: Run unit tests and static browser-serving tests**

Run: `npm run test:unit && go test ./... && go vet ./...`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/text-vault/web/js/app.js apps/text-vault/web/js/river.js apps/text-vault/web/js/river.test.js apps/text-vault/web/styles.css
git commit -m "feat: replace vault editor with river view"
```

### Task 4: End-to-End River Workflows

**Files:**
- Modify: `apps/text-vault/tests/e2e/text-vault.spec.mjs`
- Modify: `apps/text-vault/README.md`

**Interfaces:**
- Consumes: accessible names and `data-mode`/`data-state` attributes from the river UI.
- Produces: regression coverage for the complete browser workflow and updated operator/user documentation.

- [ ] **Step 1: Replace the legacy E2E expectations before changing behavior assertions**

Write serial scenarios that:

1. set up a vault, press `o`, enter multiline text, verify green, press Escape, verify saved/transparent state and full text in the river;
2. press `/`, type a keyword, verify live filtering and `#q=`, press Escape, reload and verify the query remains;
3. navigate with `j/k`, enter Edit with `i`, change text, click outside and verify Edit remains, press Escape and verify persistence;
4. open a second page in the same context, verify automatic unlock and that a different-entry update appears without refresh;
5. enter `:changepwd`, verify the password dialog opens, change the password, and unlock a fresh context with the new password;
6. use a 390×844 viewport and verify the same river and bottom input remain visible.

- [ ] **Step 2: Run E2E and verify RED**

Run: `npm run test:e2e`

Expected: at least one FAIL against any river behavior not completed correctly.

- [ ] **Step 3: Correct only the observed integration defects**

Adjust the river/app implementation until the scenarios pass; do not add drawer, attachments, deletion, hierarchy, or rich text.

- [ ] **Step 4: Update README**

Document `j`, `k`, `i`, `Enter`, `o`, `/`, `:`, Escape-only submission, status-strip colors, the gear/password flow, URL search restoration, incremental cross-tab updates, and the risk that a browser crash loses a draft that never received Escape.

- [ ] **Step 5: Run the complete verification matrix**

Run: `npm run test:unit && go test ./... && go vet ./... && npm run test:e2e`

Expected: all commands exit 0 with no unexpected browser console, page, or HTTP errors.

- [ ] **Step 6: Commit**

```bash
git add apps/text-vault/tests/e2e/text-vault.spec.mjs apps/text-vault/README.md apps/text-vault/web
git commit -m "test: verify daily river workflow"
```
