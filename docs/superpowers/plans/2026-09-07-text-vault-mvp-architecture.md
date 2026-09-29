# Text Vault MVP Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Text Vault into explicit object, query, application, interaction, adapter, and renderer boundaries without changing its current pure-text behavior or database.

**Architecture:** A DOM-free workspace accepts semantic actions and exposes immutable display snapshots. Pure query and keymap modules feed it; browser adapters own URL and password effects; a tiny registry mounts a river renderer that only consumes snapshots and dispatches actions.

**Tech Stack:** Go 1.25, SQLite, browser Web Crypto, VanJS 1.6.1, native ES modules, Node test runner, Playwright 1.58.2.

**Spec:** `docs/superpowers/specs/2026-09-07-text-vault-mvp-architecture-design.md`

## Global Constraints

- Preserve the current entry schema, encrypted object envelope, API, and SQLite database without migration.
- Preserve all visible MVP behavior except replacing an insecure-context white screen with a readable error.
- Use native ES modules and ordinary functions; add no runtime dependency and no build step.
- Renderer modules must not import repository, model, save, sync, crypto, API, or tab-session modules.
- Core query and keymap modules must not read DOM or browser globals.
- Add comments at module boundaries and non-obvious state transitions; do not narrate basic syntax.
- Do not implement persisted views, structured properties, new renderers, AI, attachments, offline support, or arbitrary code execution.

---

### Task 1: Extract the Pure Query Engine

**Files:**
- Create: `apps/text-vault/web/js/core/query.js`
- Create: `apps/text-vault/web/js/core/query.test.js`
- Modify: `apps/text-vault/web/js/repository.js`
- Modify: `apps/text-vault/web/js/repository.test.js`

**Interfaces:**
- Consumes: validated object arrays and a `QuerySpec` object.
- Produces: `runQuery(spec, objects): Entry[]`.
- Supported spec: `{type: "full-text", text: string, orderBy: "createdAt", direction: "asc"}`.

- [ ] **Step 1: Write failing query-contract tests**

Test that `runQuery()` performs case-insensitive full-text matching, ignores non-entry objects, returns full entries, sorts by `createdAt` then `id`, rejects unsupported types/order/direction, and does not mutate its inputs.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `node --test web/js/core/query.test.js`

Expected: FAIL because `core/query.js` does not exist.

- [ ] **Step 3: Implement the pure query engine**

Use this public shape:

```js
export function runQuery(spec, objects) {
  validateQuery(spec);
  const needle = spec.text.trim().toLocaleLowerCase();
  const result = objects.filter(object =>
    object.kind === "entry" && (!needle || object.text.toLocaleLowerCase().includes(needle))
  );
  return result.toSorted((left, right) =>
    left.createdAt.localeCompare(right.createdAt) || left.id.localeCompare(right.id)
  );
}
```

Validate exact MVP semantics before evaluating.

- [ ] **Step 4: Redirect repository tests and remove presentation queries**

Remove `search()`, `queryEntries()`, and the private `snippet()` from `repository.js`. Update repository tests so repository coverage stops asserting presentation ordering/search and the new query tests own those behaviors.

- [ ] **Step 5: Run query and repository suites**

Run: `node --test web/js/core/query.test.js web/js/repository.test.js`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/text-vault/web/js/core/query.js apps/text-vault/web/js/core/query.test.js apps/text-vault/web/js/repository.js apps/text-vault/web/js/repository.test.js
git commit -m "refactor: extract text vault query engine"
```

### Task 2: Extract Semantic Keyboard Translation

**Files:**
- Create: `apps/text-vault/web/js/features/vim-keymap.js`
- Create: `apps/text-vault/web/js/features/vim-keymap.test.js`
- Modify: `apps/text-vault/web/js/river.js`
- Modify: `apps/text-vault/web/js/river.test.js`

**Interfaces:**
- Consumes: `{key, shiftKey, ctrlKey, metaKey, isComposing, targetTag}` plus current workspace mode.
- Produces: `actionForKey(eventLike, mode): Action | null`.

- [ ] **Step 1: Write failing keymap tests**

Cover Normal `j/k/i/Enter/o//:`, Add/Edit Enter submit, Add/Edit Shift+Enter passthrough, Escape submit/cancel, command Enter, search Enter suppression, Ctrl/Cmd+Enter selection search, input-control suppression, and IME composition suppression.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `node --test web/js/features/vim-keymap.test.js`

Expected: FAIL because the module does not exist.

- [ ] **Step 3: Implement action translation**

Return semantic values such as:

```js
{type: "selection/move", offset: 1}
{type: "entry/edit-start"}
{type: "entry/add-start"}
{type: "input/search-start"}
{type: "input/command-start"}
{type: "draft/submit"}
{type: "selection/search"}
```

Return `null` for native text insertion, including Shift+Enter.

- [ ] **Step 4: Remove exported key semantics from the renderer**

Remove `modeForKey()` from `river.js` and its tests. Keep DOM-only `nextIndex()` temporarily until Task 3 moves selection into the workspace.

- [ ] **Step 5: Run the complete unit suite**

Run: `npm run test:unit`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/text-vault/web/js/features/vim-keymap.js apps/text-vault/web/js/features/vim-keymap.test.js apps/text-vault/web/js/river.js apps/text-vault/web/js/river.test.js
git commit -m "refactor: extract text vault keymap"
```

### Task 3: Introduce the DOM-Free Workspace

**Files:**
- Create: `apps/text-vault/web/js/application/workspace.js`
- Create: `apps/text-vault/web/js/application/workspace.test.js`
- Modify: `apps/text-vault/web/js/modes.js`
- Modify: `apps/text-vault/web/js/modes.test.js`

**Interfaces:**
- Consumes: `{repository, saver, sync, initialQuery, openPassword, runQuery, now}`.
- Produces: `createWorkspace(dependencies)` returning `snapshot()`, `dispatch(action)`, `subscribe(listener)`, and `destroy()`.
- Snapshot shape: `{query, view, selectedId, mode, draft, entries, status, message}`.

- [ ] **Step 1: Write failing workspace action tests**

Using real repositories and deterministic `now`, cover:

- initial full-text snapshot;
- stable selection and bounded movement;
- Edit/Add mode entry and draft changes;
- unchanged edit cancellation;
- non-empty add and changed edit updating the repository only on `draft/submit`;
- empty add cancellation;
- query change updating results and selection;
- save invocation after entry mutation;
- repository/saver/sync notifications producing one workspace notification;
- active draft text surviving a remote repository notification;
- derived clean/editing/saving/failed status;
- `password/open` calling only the injected capability;
- listener cleanup in `destroy()`.

- [ ] **Step 2: Run workspace tests and verify RED**

Run: `node --test web/js/application/workspace.test.js`

Expected: FAIL because `application/workspace.js` does not exist.

- [ ] **Step 3: Implement workspace state and dispatch**

Keep `modes.js` as the private pure draft-state helper or fold its behavior into workspace only if doing so reduces the public surface. The workspace must be the only caller that combines `createEntry()`, repository mutation, `saver.save()`, and QuerySpec evaluation.

`dispatch()` may return a promise for actions that save or open a capability. Synchronous state changes notify immediately; save completion notifies through the saver subscription.

- [ ] **Step 4: Run workspace and existing coordinator suites**

Run: `node --test web/js/application/workspace.test.js web/js/modes.test.js web/js/repository.test.js web/js/save.test.js web/js/sync.test.js`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/text-vault/web/js/application/workspace.js apps/text-vault/web/js/application/workspace.test.js apps/text-vault/web/js/modes.js apps/text-vault/web/js/modes.test.js
git commit -m "refactor: centralize text vault workspace actions"
```

### Task 4: Extract Browser Features and View Registry

**Files:**
- Create: `apps/text-vault/web/js/browser/query-location.js`
- Create: `apps/text-vault/web/js/browser/query-location.test.js`
- Create: `apps/text-vault/web/js/features/change-password.js`
- Create: `apps/text-vault/web/js/views/registry.js`
- Create: `apps/text-vault/web/js/views/registry.test.js`

**Interfaces:**
- `createQueryLocation({location, history, addEventListener, removeEventListener})` returns `{read(), write(query), subscribe(listener), destroy()}`.
- `createPasswordFeature({key, api, tabSession})` returns `{element, open(), destroy()}`.
- `createViewRegistry(renderers)` returns `{mount(spec, context), destroy()}`.

- [ ] **Step 1: Write failing URL-adapter tests**

Test reading/decoding `#q=`, preserving unrelated URL parts, empty-query fragment removal, hashchange subscription, and listener cleanup with small hand-written fake browser objects.

- [ ] **Step 2: Write failing registry tests**

Test mounting the requested renderer, cleanup before renderer replacement, final cleanup, and explicit rejection of unknown renderer types.

- [ ] **Step 3: Run focused tests and verify RED**

Run: `node --test web/js/browser/query-location.test.js web/js/views/registry.test.js`

Expected: FAIL because both modules are absent.

- [ ] **Step 4: Implement URL and registry modules**

Keep both modules independent of VanJS. The registry calls a renderer factory with context and stores the returned cleanup function.

- [ ] **Step 5: Extract password feature**

Move the existing dialog, `rewrapVault()`, `api.rekey()`, and `tabSession.offer()` flow out of the river renderer. Password fields and errors stay private inside this feature. Reuse existing crypto/API E2E coverage rather than mocking Web Crypto in a DOM-free unit test.

- [ ] **Step 6: Run unit tests**

Run: `npm run test:unit`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/text-vault/web/js/browser apps/text-vault/web/js/features/change-password.js apps/text-vault/web/js/views
git commit -m "refactor: isolate text vault browser features"
```

### Task 5: Make River a Renderer-Only Module

**Files:**
- Create: `apps/text-vault/web/js/views/river.js`
- Create: `apps/text-vault/web/js/views/river.test.js`
- Delete: `apps/text-vault/web/js/river.js`
- Delete: `apps/text-vault/web/js/river.test.js`
- Modify: `apps/text-vault/web/js/app.js`
- Modify: `apps/text-vault/web/styles.css`
- Modify: `apps/text-vault/tests/e2e/text-vault.spec.mjs`

**Interfaces:**
- Consumes: `{root, workspace, keymap, passwordFeature, openSelectedTextSearch}`.
- Produces: `createRiverView(context): () => void`.
- River emits only semantic actions through `workspace.dispatch()` and reads only `workspace.snapshot()`.

- [ ] **Step 1: Add failing renderer-helper tests**

Use Node tests to exercise renderer-owned helpers for bounded selection and selected-text normalization. Architectural imports are checked during code review rather than with brittle source-text assertions.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `node --test web/js/views/river.test.js`

Expected: FAIL because the new renderer path does not exist.

- [ ] **Step 3: Move DOM rendering behind workspace snapshots**

Port the current status strip, river entries, active textarea, bottom input, settings button, focus, auto-height, scroll, beforeunload, and selected-text browser behavior. Event handlers translate with `keymap.actionForKey()` and dispatch the resulting Action. They must not construct entries, mutate repositories, or call saver/sync/crypto/API/session methods.

- [ ] **Step 4: Rebuild the composition root**

After unlock, `app.js` constructs repository/save/sync, query-location, password feature, workspace, keymap, registry, and river view in that order. It wires URL changes to `query/change`, workspace query changes back to the URL adapter, and destroys owned resources on page unload.

- [ ] **Step 5: Run E2E and correct integration defects**

Run: `npm run test:e2e`

Expected: existing setup, add/edit, search, mobile, cross-tab sync, automatic unlock, and password scenarios all PASS without changing their user-visible expectations.

- [ ] **Step 6: Run all unit tests**

Run: `npm run test:unit`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/text-vault/web/js/app.js apps/text-vault/web/js/views/river.js apps/text-vault/web/js/views/river.test.js apps/text-vault/web/js/river.js apps/text-vault/web/js/river.test.js apps/text-vault/web/styles.css apps/text-vault/tests/e2e/text-vault.spec.mjs
git commit -m "refactor: render text vault through workspace"
```

### Task 6: Secure-Context Failure and Learning Documentation

**Files:**
- Create: `apps/text-vault/web/js/environment.js`
- Create: `apps/text-vault/web/js/environment.test.js`
- Modify: `apps/text-vault/web/js/app.js`
- Modify: `apps/text-vault/tests/e2e/text-vault.spec.mjs`
- Modify: `apps/text-vault/README.md`

**Interfaces:**
- Consumes: `{isSecureContext, crypto}`.
- Produces: `checkEnvironment(environment): {ok: true} | {ok: false, message: string}`.

- [ ] **Step 1: Write failing environment tests**

Test success with `crypto.subtle`, failure without a secure context, failure without `crypto.subtle`, and a stable Chinese message that tells the user to use HTTPS or localhost.

- [ ] **Step 2: Run focused test and verify RED**

Run: `node --test web/js/environment.test.js`

Expected: FAIL because `environment.js` does not exist.

- [ ] **Step 3: Implement startup validation and error rendering**

Call `checkEnvironment(window)` before creating tab sessions or requesting vault data. Render the normal authentication-message shell with the environment explanation; do not invoke `crypto.randomUUID` or `crypto.subtle` first.

- [ ] **Step 4: Add browser coverage**

Use Playwright `page.addInitScript()` to override the testable environment seam rather than depending on browser flags. Assert the readable message renders and no uncaught page error occurs.

- [ ] **Step 5: Update README architecture map**

Document the data flow, module responsibilities, extension path for a future QuerySpec/renderer, and why comments explain boundaries rather than syntax. Update the key list only if integration changed it.

- [ ] **Step 6: Run the complete verification matrix**

Run: `npm run test:unit && go test ./... && go vet ./... && npm run test:e2e`

Expected: every command exits 0; JavaScript unit tests and all Chrome scenarios report zero failures and no unexpected console/page/HTTP errors.

- [ ] **Step 7: Commit**

```bash
git add apps/text-vault/web/js/environment.js apps/text-vault/web/js/environment.test.js apps/text-vault/web/js/app.js apps/text-vault/tests/e2e/text-vault.spec.mjs apps/text-vault/README.md
git commit -m "docs: explain text vault architecture"
```
