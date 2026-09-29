# Text Vault River Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the modal MVP with a three-region default web interface whose search, add, edit-on-click, click-outside save, and selection search work without keyboard modes.

**Architecture:** Keep the durable object, pure query, persistence, sync, URL, encryption, and session modules. Make one river module own the small amount of transient UI state and call those stable interfaces directly; remove workspace, modes, keymap, password feature, and view registry until a second real consumer exists.

**Tech Stack:** Go 1.25, SQLite, browser Web Crypto, VanJS 1.6.1, native ES modules, Node test runner, Playwright 1.58.2.

**Spec:** `docs/superpowers/specs/2026-09-08-text-vault-river-simplification-design.md`

## Global Constraints

- Preserve the encrypted object format, API, SQLite schema, backup behavior, automatic cross-tab unlock, incremental sync, and URL fragment queries.
- Add no dependency and no build step.
- Search input has only search semantics; the button has only add semantics.
- Clicking outside an edit submits it; blank new entries are discarded.
- Keep implementation comments about responsibility and non-obvious data flow, not elementary syntax.
- Put browser JavaScript tests under `tests/unit/`, never beside production modules.

---

### Task 1: Separate Tests from Browser Source

**Files:**
- Move: `apps/text-vault/web/js/**/*.test.js` → `apps/text-vault/tests/unit/**`
- Modify: `apps/text-vault/package.json`

**Interfaces:**
- Consumes: native ESM production modules through relative imports.
- Produces: `npm run test:unit` discovering only `tests/unit/**/*.test.js`.

- [ ] Move every browser unit test to the matching path under `tests/unit/` and adjust imports to point into `web/js/`.
- [ ] Change `test:unit` to `node --test tests/unit/*.test.js tests/unit/*/*.test.js`.
- [ ] Run `npm run test:unit`; all existing unit contracts must pass before behavior changes.
- [ ] Commit as `refactor: separate text vault tests from source`.

### Task 2: Replace Modal Interaction with the Default River Interface

**Files:**
- Rewrite: `apps/text-vault/web/js/views/river.js`
- Modify: `apps/text-vault/web/js/app.js`
- Modify: `apps/text-vault/web/styles.css`
- Modify: `apps/text-vault/tests/e2e/text-vault.spec.mjs`
- Delete: `apps/text-vault/web/js/application/workspace.js`
- Delete: `apps/text-vault/web/js/modes.js`
- Delete: `apps/text-vault/web/js/features/vim-keymap.js`
- Delete: `apps/text-vault/web/js/features/change-password.js`
- Delete: `apps/text-vault/web/js/views/registry.js`
- Delete: the corresponding tests now under `apps/text-vault/tests/unit/`

**Interfaces:**
- Consumes: `{root, repository, saver, sync, queryLocation, openSelectedTextSearch, now}`.
- Produces: `createRiverView(context): () => void`.

- [ ] Replace the old modal E2E expectations with one main-flow scenario: type search, clear search, click add, type multiline text, click outside, await clean status, click entry, edit, click outside, await clean status, select text, and click the nearby new-tab button.
- [ ] Run that browser scenario and verify it fails against the modal view for the expected missing add button/click editing behavior.
- [ ] Implement river-local state `{`query`, `editing`, `draft`, `adding`, `message`} and derive displayed entries with `runQuery({type: "full-text", text: query, orderBy: "createdAt", direction: "asc"}, repository.values())`.
- [ ] Render only status strip, river, and bottom bar. The bottom bar contains `textarea[aria-label="搜索"]` and `button[aria-label="新增"]`.
- [ ] On add or entry click, start one inline textarea. A document `pointerdown` outside that editor calls one `commitEdit()` function; blank adds cancel, edits call `repository.updateEntryText`, adds call `repository.upsert(createEntry(...))`, and mutations call `saver.save()`.
- [ ] While editing, disable search and add. Preserve native textarea Enter/newline behavior.
- [ ] On `selectionchange`, position one fixed selection-search button from `Range.getBoundingClientRect()` only when the selection belongs to `.entry-text`; its click opens `queryLocation.url(text)` with `_blank,noopener`.
- [ ] Subscribe rendering/status refresh to repository, saver, and sync; pull on window focus; warn on unload for an active edit or pending repository changes; return cleanup for every subscription/listener.
- [ ] Simplify `app.js` to construct the river directly after repository/save/sync/query-location, then start sync. Remove all deleted-module imports and password UI wiring.
- [ ] Reduce CSS to the three-region layout, inline editor, bottom search/add row, save strip, auth shell, and selection-search button.
- [ ] Run the focused browser scenario and all unit tests.
- [ ] Commit as `refactor: simplify text vault river interaction`.

### Task 3: Documentation and Final Verification

**Files:**
- Modify: `apps/text-vault/README.md`

**Interfaces:**
- Produces: operating instructions and architecture map matching the shipped code.

- [ ] Remove Vim, command, change-password, and workspace/registry documentation. Describe click editing, click-outside save, search/add controls, selected-text new-tab search, and the `repository → query → river` extension boundary.
- [ ] Run `npm run test:unit`, `go test ./...`, `go vet ./...`, and `npm run test:e2e`.
- [ ] Inspect `web/js/` to confirm it contains no `*.test.js` and search deleted module names to confirm no imports remain.
- [ ] Commit as `docs: explain simplified text vault`.
