# Text Vault MVP Architecture Design

## Purpose

Refactor the current pure-text MVP so its logic follows a stable data → query → view direction. The visible product remains the same: encrypted flat text entries, live full-text search, river display, in-place editing, Vim-style keys, password rotation, automatic cross-tab unlock, explicit Enter/Escape submission, and incremental synchronization.

This refactor creates extension seams for future structured properties, saved queries, renderer widgets, and user-configured views. It does not implement those future features now.

## Design Principles

1. Persistable concepts are data. Entries are the only user-facing persisted object in this MVP; the existing `kind`, `properties`, and object envelope remain future-compatible.
2. Queries are pure descriptions evaluated against objects. They do not render DOM or save data.
3. Renderers turn a prepared view model into browser UI. They do not know encryption, SQLite, revisions, or HTTP endpoints.
4. Browser input is translated into semantic actions before application state changes.
5. Side effects live at the boundary: persistence, synchronization, URL state, Web Crypto, BroadcastChannel, and DOM.
6. Extensibility is source-level and explicit. Native ES modules and small registries are used; there is no dependency-injection container, runtime plugin loader, event bus, arbitrary JavaScript evaluator, or build step.
7. Modules are separated by responsibility, not by function count. A module may contain several related functions when they change for the same reason.

## Runtime Data Flow

```text
keyboard / pointer / touch
          ↓
interaction translator
          ↓ semantic Action
workspace application state
          ↓
object store ──→ persistence and sync adapters
          ↓
query engine(QuerySpec, objects)
          ↓
ViewModel
          ↓
view registry → river renderer → DOM
```

The reverse direction is always an action. A renderer never reaches into the repository to modify an entry.

## Current MVP Data

The persisted entry schema remains unchanged:

```js
{
  schemaVersion: 1,
  id,
  kind: "entry",
  text,
  properties: {},
  createdAt,
  updatedAt,
  revision
}
```

`properties` remains unused by the MVP interface. Future features may add namespaced structured values without changing plain-text content.

The initial query description is deliberately small:

```js
{
  type: "full-text",
  text: "example.com",
  orderBy: "createdAt",
  direction: "asc"
}
```

The initial view description is:

```js
{type: "river"}
```

Query and view descriptions are runtime data in this MVP. Persisting them as `query` or `view` objects is future work.

## Module Boundaries

### Core query

`web/js/core/query.js` exports `runQuery(querySpec, objects)`. It validates the supported query description, performs case-insensitive full-text filtering, and returns full entries in stable creation order. It is a pure function and imports no DOM, API, crypto, repository, or synchronization code.

The repository continues to own object identity, dirty tracking, revisions, remote merging, conflict preservation, and quarantine. Its existing `search()` and `queryEntries()` presentation-specific methods are removed after all callers use the query engine.

### Workspace application

`web/js/application/workspace.js` owns the current transient workspace state:

```js
{
  query,
  view: {type: "river"},
  selectedId,
  mode,
  draft,
  saveState,
  message
}
```

It exposes:

```js
workspace.snapshot()
workspace.dispatch(action)
workspace.subscribe(listener)
workspace.destroy()
```

`snapshot()` returns a ViewModel containing query results and display state. `dispatch()` accepts semantic actions such as `selection/move`, `entry/edit-start`, `draft/change`, `draft/submit`, `query/change`, and `password/open`. The workspace is the only layer allowed to coordinate repository updates with save and sync operations.

The workspace listens to repository, saver, and sync changes and emits one application-state notification. It protects Edit/Add drafts from remote redraws and retains current conflict behavior.

### Interaction keymap

`web/js/features/vim-keymap.js` translates normalized browser keyboard input plus current mode into semantic actions. It owns `j`, `k`, `i`, `o`, `/`, `:`, Enter, Shift+Enter, Escape, and selection-search shortcut rules. It does not touch DOM nodes, repositories, URLs, or network services.

Removing this module removes Vim shortcuts without removing pointer/touch editing or application actions.

### Search location adapter

`web/js/browser/query-location.js` reads and writes `#q=` and converts `hashchange` into `query/change`. It is the only module that knows URL fragment encoding. The query engine never reads `location`.

### Password feature

`web/js/features/change-password.js` owns the password dialog DOM and the rewrap/rekey workflow. It exposes an `open()` capability and a `destroy()` cleanup. Password values never enter workspace state, query text, URLs, command history, or persisted objects.

The `:changepwd` command resolves to the semantic `password/open` action. The workspace invokes the injected password capability without understanding its UI or cryptography.

### View registry

`web/js/views/registry.js` is a small explicit map from a view type to a renderer factory:

```js
const views = createViewRegistry({river: createRiverView});
views.mount({type: "river"}, context);
```

It validates unknown renderer names and owns renderer replacement/cleanup. It is not a general plugin framework.

### River renderer

`web/js/views/river.js` receives only:

```js
{
  root,
  getViewModel,
  subscribe,
  dispatch,
  openPassword,
  openSelectedTextSearch
}
```

It renders the status strip, flat entry river, active textarea, bottom input, and settings control. DOM events emit semantic actions. It does not import the repository, save/sync coordinators, model constructors, crypto functions, API client, or tab session.

The renderer may own DOM-only details such as textarea auto-height, focus placement, and scroll positioning. These are visual mechanics, not application state.

### Composition root

`web/js/app.js` remains the composition root. It handles setup/unlock, constructs API/crypto/repository/save/sync/session adapters, constructs the workspace, registers the river renderer, installs the query-location and password features, and mounts the selected view.

No other module is allowed to construct the complete application graph.

## Feature Removal Test

The architecture is considered clean when these examples hold:

- Removing `vim-keymap.js` and one registration removes keyboard shortcuts while touch/mouse actions still work.
- Removing `change-password.js` and one capability registration removes password rotation without affecting entry editing.
- Adding a renderer requires a new renderer module and one registry entry, not changes to river code.
- Replacing URL-backed query state requires changing `query-location.js`, not the query engine or renderer.
- Replacing HTTP persistence does not change queries or views.

## Comments and Readability

Each architectural module begins with a short comment stating its responsibility, allowed dependencies, and forbidden knowledge. Non-obvious state transitions and boundary crossings receive block comments explaining why and how data flows. Comments do not narrate basic JavaScript syntax.

Public factory functions use descriptive names and small returned interfaces. Tests demonstrate each public contract. Avoid generic framework vocabulary where a concrete Text Vault term is clearer.

## Error Handling

- Unsupported QuerySpec or view type fails explicitly instead of silently returning empty output.
- Save and sync failures retain in-memory changes and produce the existing red status.
- A remote update never overwrites an active draft.
- Password errors stay inside the password feature.
- Missing secure-context APIs produce a readable authentication/startup error rather than an unhandled blank page. This is error presentation only; insecure HTTP remains unsupported because encryption requires Web Crypto.
- Every installed browser listener and subscription has an owned cleanup path.

## Testing Strategy

Pure unit tests cover QuerySpec evaluation, workspace actions/state, key translation, registry selection, and URL encoding. Existing repository, crypto, save, sync, API, and session tests remain.

Playwright tests preserve all visible workflows:

- setup/unlock;
- Add/Edit with Enter, Shift+Enter, and Escape;
- live URL search;
- keyboard navigation;
- mobile river behavior;
- cross-tab automatic unlock and incremental synchronization;
- `:changepwd` and settings-driven password rotation;
- light theme and status colors;
- a readable secure-context failure instead of a blank screen.

The refactor is complete only when the full JavaScript unit suite, Go tests, `go vet`, and Chrome E2E suite pass with no database migration.

## Explicit Non-Goals

- Persisted query or view objects
- User-authored view syntax or visual view builder
- Structured property editor
- Music, map, table, attachment, AI, or embed renderer
- Runtime third-party plugins
- Arbitrary JavaScript, HTML, or CSS execution
- Offline support
- Database or API schema changes
