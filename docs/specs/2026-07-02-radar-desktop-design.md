# Radar Desktop — Design Spec

> Status: **approved (design)**, pre-implementation. Date: 2026-07-02.
> Authoritative architecture for a standalone macOS-first desktop heap/memory
> analysis app, plus the shared-core extraction it requires.
> Read `AGENTS.md` (golden architecture rules) before implementing any of this.
> Supersedes the designer handoff (`docs/flutter_radar_desktop/`) where the two
> conflict — divergences are called out inline.

## Context

The suite today ships three surfaces on one engine (`leak_graph`) and one design
system (`radar_ui`): the on-device overlay (`flutter_leak_radar` /
`flutter_perf_radar` / `radarscope`), the runtime lint (`flutter_leak_radar_lint`),
and the **DevTools extension** (`flutter_leak_radar_devtools`) for host-side,
connection-driven heap/leak/perf analysis.

The missing surface is an **offline, dump-first** tool: open a `.dartheap` export,
analyze it, compare snapshots, and — the killer feature for soak/automation runs —
**trend a class's growth across N dumps over time**. Today that only works while
attached to a live app inside DevTools. Radar Desktop makes it a standalone
application where a VM-service connection is **optional and purely additive**.

### Format validation (done)

The DevTools Memory-tab export is the **raw `dartheap` VM snapshot** (magic bytes
`64 61 72 74 68 65 61 70`). A real 46 MB export
(`main-1_2026-07-02_...data`) was run through `leak_graph`'s `analyze` CLI and
parsed cleanly — 139 leak clusters with real retaining paths and app classes.
**`leak_graph.heapGraphFromBytes(Uint8List)` reads DevTools exports drop-in; no
format adapter is needed.** Export writes the same chunks back.

## Goals

1. A standalone desktop app (macOS-first, Flutter-desktop, cross-platform-capable)
   for **offline** heap-dump analysis: import → analyze → compare → trend.
2. An **optional** VM-service connection that *adds* live capture, Force GC, and the
   radar Performance/Stability surfaces — nothing offline looks broken or disabled.
3. **Zero new analysis engine, zero new design system.** Reuse `leak_graph` and
   `radar_ui`, and reuse the memory/perf/stability views that already exist in the
   DevTools extension — by extracting them into a host-agnostic package.
4. Leave the DevTools extension behaviorally identical after the refactor.

## Non-goals

- Not a general Dart profiler (CPU, allocation timelines) — that is DevTools.
- No `.dartheap` re-implementation; no bespoke chart/design framework.
- No live *leak-findings* stream in v1 (see [§7](#7-the-connected-leak-gap)).
- The prototype's `support.js` is preview-only and is never shipped or ported.

---

## 1. Architecture: three packages

```
                 ┌───────────────────────────┐
                 │        radar_ui            │  design system (published 0.1.1 → 0.2.0)
                 │  tokens, widgets, theme    │  + RadarTrendChart, RadarLinearProgress (new)
                 └─────────────┬─────────────┘
                               │
        ┌──────────────────────┴───────────────────────┐
        │                                               │
┌───────▼────────┐                            ┌─────────▼──────────┐
│   leak_graph   │  pure analysis (0.2.2)     │  radar_workbench   │  NEW, host-agnostic
│  heapGraph +   │◄───────────────────────────│  models · views ·  │  (publish_to: none)
│  GraphLeak…    │                            │  controllers ·     │
└────────────────┘                            │  interfaces        │
                                              └───┬────────────┬───┘
                                                  │            │
                            ┌─────────────────────▼──┐   ┌─────▼───────────────────┐
                            │ flutter_leak_radar_     │   │     radar_desktop        │  NEW app
                            │ devtools  (thin shell)  │   │  (publish_to: none)      │
                            │  serviceManager→RadarConn│   │  window shell · workspace│
                            │  DTD→SnapshotStore       │   │  file I/O · trends ·     │
                            │  web_download→Exporter   │   │  VmServiceUri connection │
                            └──────────────────────────┘   └──────────────────────────┘
```

- **`radar_workbench`** *(new)* — the shared brain + UI. Holds `SnapshotBundle`,
  the perf/stability DTOs, `FilterExpression`, the analysis orchestration, and
  **all host-side views** (memory, performance, stability), behind small interfaces
  (`RadarConnection`, `SnapshotSource`, `SnapshotExporter`, `SnapshotStore`).
  Depends only on `flutter`, `leak_graph`, `radar_ui`, `vm_service`. **No
  `devtools_extensions`, no `dart:io`, no `dart:html`** — so it still compiles to
  web for the DevTools extension.
- **`flutter_leak_radar_devtools`** *(refactored → thin shell)* — keeps the DevTools
  entry, DTD persistence, web download, and a `serviceManager → RadarConnection`
  adapter; imports every view from `radar_workbench`. No UX change.
- **`radar_desktop`** *(new, `publish_to: none`, macOS-first)* — the app: custom
  radar-dark frameless window, workspace, file import/export, Trends, and a direct
  `ws://` VM-service connection for connected mode.

### Why extract instead of copy

The DevTools memory/perf/stability views are already host-agnostic in all but
~6 files (mapped below). Copying them into the desktop app would fork the UI and
double every future fix. Extracting once behind interfaces is the standard
"improve the code you're working in" move: one source of truth, two thin shells.

---

## 2. Package `radar_workbench` — extraction manifest

Every `flutter_leak_radar_devtools/lib` file is classified **MOVE** (wholesale),
**ADAPT** (portable once a coupling is abstracted), or **STAY** (DevTools-specific).
Host-coupling markers are `devtools_extensions`, `devtools_app_shared`, `dtd`,
`package:web` / `dart:js_interop`, `serviceManager`, `dtdManager`.

| File | Classification | Note |
|------|----------------|------|
| `main.dart` | STAY | extension entry |
| `src/app.dart` | STAY | wraps `DevToolsExtension`, wires DTD; scaffold inside moves |
| `capture/snapshot_bundle.dart` | MOVE | pure DTO (leak_graph only) |
| `capture/snapshot_service.dart` | ADAPT | takes `VmService`+`IsolateRef` → becomes a `SnapshotSource` impl behind the DevTools adapter |
| `connection/connection_state_notifier.dart` | STAY→adapter | `serviceManager`-specific; wrapped by `DevToolsRadarConnection` |
| `filter/filter_expression.dart` | MOVE | pure parser |
| `filter/filter_bar.dart` | MOVE | pure UI |
| `memory/filter_target.dart` | MOVE | pure `FilterTarget` adapter |
| `memory/memory_controller.dart` | MOVE | inject `SnapshotSource` + `RadarConnection` instead of `SnapshotService` + `ConnectionStateNotifier` |
| `memory/memory_view.dart` | MOVE | enum |
| `memory/class_histogram_view.dart` | MOVE | pure view |
| `memory/diff_table.dart` | MOVE | pure view (also serves desktop **Compare**) |
| `memory/snapshots_view.dart` | ADAPT | uses `web_download` → inject `SnapshotExporter` |
| `memory/retaining_paths_view.dart` | MOVE | pure view |
| `memory/class_detail_panel.dart` | MOVE | per-path distribution UI |
| `memory/root_kind_ui.dart` | MOVE | `RootBucket` + `RootDot` |
| `memory/mem_format.dart` | MOVE | formatters |
| `memory/sort_header_cell.dart` | MOVE | widget |
| `perf/perf_data_controller.dart` | MOVE | already injectable via `callExtension`; default derives from `RadarConnection` |
| `perf/perf_snapshot_dto.dart` | MOVE | pure DTOs |
| `perf/frames_view.dart` | MOVE | pure view |
| `perf/traces_view.dart` | MOVE | pure view |
| `perf/perf_state_views.dart` | MOVE | state widgets |
| `presentation/main_scaffold.dart` | MOVE | UI composition over injected controllers |
| `presentation/retaining_path_tile.dart` | MOVE | hop-by-hop tile |
| `session/snapshot_store.dart` | MOVE | interface + `PersistedSession` + in-memory impl |
| `session/dtd_snapshot_store.dart` | STAY | DTD backend |
| `session/session_persistence.dart` | MOVE | debounced-persist orchestration |
| `session/radar_session.dart` | ADAPT | accept injected controller factories |
| `shell/radar_view.dart` | MOVE | nav enum |
| `shell/left_rail.dart` | MOVE | nav rail (desktop adds MEMORY items) |
| `shell/connection_bar.dart` | MOVE | binds to `RadarConnection` |
| `stability/errors_view.dart` | MOVE | pure view |
| `stability/stalls_view.dart` | MOVE | pure view |
| `util/web_download.dart` | STAY | web-only; behind `SnapshotExporter` |

**Net effect:** the DevTools package shrinks to `main.dart`, `app.dart`,
`connection_state_notifier.dart`, `dtd_snapshot_store.dart`, `web_download.dart`,
and a new `adapters/` folder. Everything else lives in `radar_workbench`.

### 2.1 Interfaces (radar_workbench `lib/src/core/`)

Keep the surface minimal — only abstract genuine host differences.

```dart
// connection.dart
enum ConnectionPhase { disconnected, connecting, connected }
final class ConnectionState {
  const ConnectionState(this.phase, {this.vmName, this.isolateName});
  final ConnectionPhase phase;
  final String? vmName;
  final String? isolateName;
}
/// The one seam between a host and the workbench. DevTools implements it over
/// serviceManager; desktop implements it over a direct vm_service ws client.
abstract interface class RadarConnection implements Listenable {
  ConnectionState get state;
  VmService? get vmService;   // null when disconnected
  IsolateRef? get isolateRef; // main isolate, null when disconnected
}

// snapshot_source.dart
/// Produces a fully-analyzed bundle from a *live* connection. File import is NOT
/// a SnapshotSource (it lives host-side; see SnapshotAnalyzer). Never throws;
/// returns a bundle carrying an error result on failure.
abstract interface class SnapshotSource {
  Future<SnapshotBundle> capture({String label = ''});
}

// snapshot_exporter.dart
abstract interface class SnapshotExporter {
  Future<void> export(SnapshotBundle bundle, {String? suggestedName});
}

// snapshot_store.dart  (already exists; moves as-is)
abstract interface class SnapshotStore {
  Future<void> persist(PersistedSession session);
  Future<PersistedSession?> restore();
  Future<void> clear();
}
```

We deliberately do **not** introduce a `PerfRadarService` interface: the existing
`PerfDataController` already accepts an injectable
`Future<Map<String,Object?>> Function(String method) callExtension`. The default is
derived from a `RadarConnection`:
`(m) => conn.vmService!.callServiceExtension(m, isolateId: conn.isolateRef!.id!)`,
with the same wrap/unwrap and `-32601 → ExtensionNotAvailableException` handling the
DevTools controller does today. Tests keep injecting a fake closure.

### 2.2 Web-safe analysis orchestration

`radar_workbench` must compile to web, so it **cannot** read files (`dart:io`).
It exposes a pure, web-safe analyzer and lets each host feed it bytes or a graph:

```dart
// snapshot_analyzer.dart
final class SnapshotAnalyzer {
  const SnapshotAnalyzer({GraphAnalysisOptions options});
  /// Parse + analyze raw dartheap bytes on a background isolate/worker.
  /// Uses `compute` (works on web and native). Never throws.
  Future<SnapshotBundle> fromBytes(Uint8List bytes, {String label});
  /// Analyze an already-parsed graph (live capture path).
  Future<SnapshotBundle> fromGraph(HeapGraphView graph, {String label});
}
```

- **Desktop file import** reads `File.readAsBytes()` (host-side, `dart:io`) then calls
  `analyzer.fromBytes(bytes)`. The raw bytes (`Uint8List`, trivially sendable) cross
  into the isolate; `heapGraphFromBytes` + `GraphLeakAnalyzer.analyze` run there.
- **Live capture** (`SnapshotSource.capture`) obtains a `HeapSnapshotGraph` from the
  connection (`HeapSnapshotGraph.getSnapshot`), wraps it in `VmSnapshotGraphView`,
  and calls `analyzer.fromGraph` (which `compute`s the analysis, as the current
  `snapshot_service` already does).
- Desktop may prefer `Isolate.run` over `compute` for true off-main-isolate work;
  the analyzer keeps the host-agnostic `compute` default and exposes the pure
  top-level functions so desktop can wrap them in `Isolate.run` if profiling shows
  a need. All `leak_graph` analysis is confirmed isolate-safe (no Flutter/`dart:ui`).

### 2.3 `MemoryController` after extraction

```dart
MemoryController({
  required SnapshotSource snapshotSource, // was SnapshotService + VmService
  required RadarConnection connection,    // was ConnectionStateNotifier
});
```

Everything else is unchanged and already host-agnostic: `snapshots`,
`selectedIds` (≤2), `pair`/`focused`/`comparison`, `diff` (via `leak_graph`'s
`computeDiff`, incl. the empty-baseline "show all" mode), `capture`,
`toggleSelection`, `remove`, `clearAll`, `rehydrate`, `forceGc`
(via `connection.vmService`).

### 2.4 New shared widgets (land in `radar_ui`)

The mockup needs two primitives `radar_ui` lacks; they belong in the design system
so both hosts (and future surfaces) get them:

- **`RadarTrendChart`** — full-size line + filled-area + point-markers chart with
  per-point value/timestamp labels (Trends screen). Generalize the existing
  `_SparklinePainter` approach; amber accent by default.
- **`RadarLinearProgress`** — indeterminate sweep bar for the "Analyzing…" grace
  state (the prototype's `rdr-indet`). Pairs with existing `RadarLivePulseDot`.

Adding widgets bumps `radar_ui` to **0.2.0**. During development the workspace
resolves it locally; publishing follows the existing tiered
`tool/sync-constraints.sh` + `tool/publish-all.sh` flow.

---

## 3. Package `flutter_leak_radar_devtools` — thin shell

After the move it contains only host-specific glue plus a new `src/adapters/`:

- `DevToolsRadarConnection` — wraps `ConnectionStateNotifier`, implements
  `RadarConnection`.
- `DevToolsSnapshotSource` — wraps the (moved) capture logic + `RadarConnection`,
  implements `SnapshotSource`.
- `DevToolsSnapshotExporter` — implements `SnapshotExporter` via `web_download`.
- DTD `SnapshotStore` stays (`dtd_snapshot_store.dart`).

`app.dart` builds these adapters and hands them to the (moved) `RadarSession` /
`MemoryController` / `PerfDataController`, then renders the (moved)
`LeakRadarMainScaffold` under `radarDarkTheme()`. **Acceptance: the extension is
pixel- and behavior-identical, and its existing tests pass unchanged** (run with
`flutter test --platform chrome` — the web-interop deps do not compile on the VM
target). Bump the extension to **0.3.0**; update `extension/config.yaml` version
(drives the header) and rebundle into `flutter_leak_radar/extension/devtools/build/`.

---

## 4. Package `radar_desktop` — the app

`publish_to: none`. macOS-first, structured so Windows/Linux are reachable later.

### 4.1 Window shell (custom radar-dark)

Per the locked decision, use a **custom frameless shell**, not `macos_ui`
(supersedes the handoff's `macos_ui` suggestion):

- `window_manager` — frameless window (`titleBarStyle: hidden`), draggable custom
  title bar, min-size, remembered bounds. On macOS keep native traffic lights
  visible over the custom bar; on other platforms render custom window controls.
- Title bar: traffic-light gutter · centered `"{workspace} — Radar Desktop"`.
- `radarDarkTheme()` for all content; left rail (210px) + toolbar per the mockup.

### 4.2 State & controllers

- Reuse `radar_workbench`'s `MemoryController` for the **active dump** (histogram,
  retaining paths) and 2-way **Compare** selection.
- New desktop **`WorkspaceController`** owns what is genuinely desktop-scoped:
  - the dump list as a **workspace** (files + captures), each row's metadata;
  - the **multi-select set** (`checked[]`) that drives Compare and Trends (N-way,
    beyond the controller's 2-way compare selection);
  - **Recent files**, drag-drop import, and the active `.radarworkspace` path.
  - Import flow: `File.readAsBytes` → `SnapshotAnalyzer.fromBytes` (isolate) →
    add `SnapshotBundle` to the workspace; surface the `Analyzing…` state
    (`RadarLinearProgress`) while in flight.
- **Trends** is desktop-only. Add a pure `computeTrend(List<SnapshotBundle>,
  className) → TrendSeries` (list of `{capturedAt, instances, shallowBytes}`) to
  `radar_workbench` (pure, unit-testable), rendered by `RadarTrendChart`. "Growing
  classes" for the picker chips = classes with positive first→last instance delta.

### 4.3 Screens (offline)

Wired from the mockup inventory (columns, sort defaults, filter chips, empty states
as specified in `docs/flutter_radar_desktop`):

- **Dumps / Workspace** — checklist table (`24px 2.4fr 0.8fr 1fr 0.8fr 0.9fr`),
  file/capture icon, source, captured, classes, retained; drop zone + Recent.
- **Class histogram** — reuse the moved `class_histogram_view`; sort default
  `bytes ↓`, chips `all · leak-prone · app · collections`, root-kind color tags.
- **Retaining paths + class detail** — reuse `retaining_paths_view` +
  `class_detail_panel`: root-kind breakdown tiles + per-path instance distribution
  (proportional bars, %, expand-to-hop-by-hop, first row expanded).
- **Compare** — two dump pickers → `MemoryController` selection → reuse `diff_table`
  (growth red / shrink green, largest growers first).
- **Trends** — class picker chips + `RadarTrendChart` + first→last net-delta headline;
  empty state until ≥2 dumps checked.

### 4.4 Output & persistence

- **Export report** — JSON via `SnapshotBundle.toJson`; Markdown via `renderReport`
  (leak_graph) adapted; save through a `DesktopSnapshotExporter`
  (`SnapshotExporter` impl using `file_selector` save dialog).
- **Workspace file** — `.radarworkspace` = a `PersistedSession` JSON (bundles are
  compact *analysis results*, not raw dumps). Explicit Save/Open via `file_selector`.
- **Auto-restore** — a desktop `FileSnapshotStore` (`SnapshotStore` impl using
  `path_provider`'s app-support dir) restores the last session on launch, mirroring
  the DevTools DTD behavior.

### 4.5 Desktop dependencies

`radar_workbench`, `radar_ui`, `leak_graph`, `vm_service`, `window_manager`,
`file_selector`, `desktop_drop`, `path_provider`, `path`. `resolution: workspace`.

---

## 5. Data flow

**Offline (default):**
```
.dartheap file ──readAsBytes──▶ Uint8List ──compute/Isolate──▶
  heapGraphFromBytes ▶ GraphLeakAnalyzer.analyze ▶ SnapshotBundle ▶
  WorkspaceController ▶ (histogram / paths / compare / trends views)
```

**Connected (optional):**
```
ws:// URI ──vmServiceConnectUri──▶ VmServiceUriConnection (RadarConnection)
  ├─ capture: HeapSnapshotGraph.getSnapshot ▶ analyzer.fromGraph ▶ SnapshotBundle
  ├─ Force GC: vmService.getAllocationProfile(isolateId, reset:true)
  └─ perf/stability: PerfDataController.callExtension('ext.perf_radar.snapshot')
                     ▶ PerfSnapshotDto ▶ (traces / frames / errors / stalls views)
```

The `ext.perf_radar.snapshot` contract (traces/frames/stability DTOs, HOT/dedup,
percentiles, span-correlated stalls) is unchanged from the extension; the desktop
just calls it over its own connection. Force-GC + capture reuse `vm_service` exactly
as `leak_graph`'s `capture.dart` CLI already demonstrates.

---

## 6. Connected mode

- **`VmServiceUriConnection implements RadarConnection`** — connects with
  `vmServiceConnectUri(wsUri)` (http/https auto-converted to ws/wss, as in
  `capture.dart`), resolves the main isolate, exposes `vmService`/`isolateRef`/
  `state`, and notifies listeners on connect/disconnect.
- Connect UI: a ws-URI field behind the toolbar connection chip (Offline grey /
  Connected green + `RadarLivePulseDot`). Transition = "more appears": the
  Performance/Stability rail groups unlock; toolbar gains Capture + Force GC.
- Offline shows Performance/Stability **locked-but-visible** (🔒, dimmed,
  non-clickable) + the OFFLINE callout — exactly the mockup treatment.

## 7. The connected-leak gap

`flutter_perf_radar` registers `ext.perf_radar.snapshot` / `ext.perf_radar.resetFrames`,
so Performance/Stability work over any connection. **`flutter_leak_radar` registers
no service extension** — live `LeakReport`s cannot be pulled remotely, because leak
detection needs the heap graph, not a small JSON.

Therefore, in v1, connected **memory** analysis = *capture a heap snapshot → run the
same offline pipeline*. That is the honest, complete story (identical downstream
analysis to an imported dump). A live-findings feed would require a new
`ext.leak_radar.report` extension serializing `LeakReport`s — **out of scope for v1**,
noted as a clean future extension. The handoff's "plus live leak-detector findings"
line is descoped accordingly.

---

## 8. Testing

Per repo rules (80% target; unit + integration + E2E where meaningful):

- **Golden fixture (format E2E).** Capture a *small* (<1 MB) real `.dartheap` from
  the example app, commit it as a test asset, and assert `SnapshotAnalyzer.fromBytes`
  yields stable class/cluster counts and a known retaining path. (The 46 MB export
  validated the format and is **not** committed.)
- **Unit (radar_workbench):** `computeTrend` series math; `computeDiff` empty-baseline
  "show all"; `FilterExpression` parse/match (existing tests move with it);
  `PersistedSession` toJson/fromJson round-trip; analyzer error-path (malformed bytes
  → error bundle, never throws).
- **Unit (radar_desktop):** `.radarworkspace` save/open round-trip; `FileSnapshotStore`
  restore; import-adds-bundle; "growing classes" selection.
- **Widget (radar_desktop):** Workspace table (multi-select drives Compare/Trends),
  Trends (`RadarTrendChart` + ≥2-dump gate), shell offline↔connected rail/toolbar
  states, connection chip.
- **Widget (radar_ui):** `RadarTrendChart`, `RadarLinearProgress`.
- **Regression:** the extension's existing tests pass unchanged after extraction
  (`flutter test --platform chrome`); `radar_workbench` pure tests run on the VM.
- **CI gate:** `melos run ci` (format-check → analyze `--fatal-infos` → test →
  custom_lint). Desktop widget tests run on the default VM target; keep
  `dart:io`/`window_manager` calls behind the `WorkspaceController` so tests don't
  need a real window.

---

## 9. Build phases

v1 ships all three, but they are built and planned in order. **Each phase gets its
own `writing-plans` implementation plan; this spec is the shared contract.**

1. **Extract `radar_workbench` + refactor the DevTools extension onto it.**
   Foundation, no user-visible change. Done when the manifest is moved, the three
   adapters (`DevToolsRadarConnection`, `DevToolsSnapshotSource`,
   `DevToolsSnapshotExporter`) exist, the extension is behavior-identical, and all
   tests are green.
2. **`radar_desktop` offline core.** Window shell + `WorkspaceController` + file
   import (drag-drop + browse) + isolate analysis + Dumps/Histogram/RetainingPaths/
   Compare/Trends + report export + `.radarworkspace` save/reopen + auto-restore.
   Ships a usable offline app. Adds `RadarTrendChart`/`RadarLinearProgress` to
   `radar_ui` (0.2.0).
3. **Connected mode.** `VmServiceUriConnection` + connect UI + live capture +
   Force GC + Performance (Traces/Frames) + Stability (Errors/Stalls) wired over the
   direct connection; locked-but-visible rail offline.

---

## 10. Workspace, versioning, publish

- Add `packages/radar_workbench` and `packages/radar_desktop` to the root
  `pubspec.yaml` `workspace:` list (melos globs `packages/**` already).
- `radar_workbench` — `version: 0.1.0`, `publish_to: none` (internal shared code;
  only `publish_to: none` consumers use it — the extension bundles at build time,
  the desktop app is unpublished). Promote to published later only if a standalone
  consumer emerges.
- `flutter_leak_radar_devtools` — add `radar_workbench: ^0.1.0`; bump to `0.3.0`.
- `radar_ui` — bump to `0.2.0` in Phase 2 for the two new widgets; run
  `tool/sync-constraints.sh` and the tiered `tool/publish-all.sh` when publishing.
- `radar_desktop` — `version: 0.1.0`, `publish_to: none`.

## 11. Risks & mitigations

- **Large dumps (100s MB).** Peak memory to hold bytes + graph is real. Mitigate:
  stream `readAsBytes`, run analysis in an isolate, **drop the graph after analysis**
  (keep only the compact `SnapshotBundle`), virtualize class/diff lists, and show the
  `Analyzing…` grace state.
- **Isolate sendability.** Send `Uint8List` bytes (not a `HeapSnapshotGraph`) into
  the isolate for file import; the live-capture graph is already produced on the main
  isolate and analyzed via `compute`, as today.
- **macOS frameless + traffic lights.** Known `window_manager` pattern; verify the
  traffic-light overlay and drag region early in Phase 2.
- **radar_ui version cascade.** Bumping `radar_ui` touches downstream constraints;
  handled by the existing sync-constraints/publish tooling and only at publish time.

## 12. Open questions (non-blocking)

- `.radarworkspace` as a single JSON vs. a zipped bundle set — start with single
  JSON (bundles are small analysis results); revisit if soak workspaces get large.
- Whether to promote `radar_workbench` to a published package — defer (YAGNI).
