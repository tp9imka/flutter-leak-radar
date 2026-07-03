# Android Profiling — Phase 3: desktop UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Wire the merged backend + widgets into `radar_desktop` as a new **ANDROID NATIVE** rail group with its six views, driven by an offline `NativeProfilingController`, reaching a **launchable, testable** app that imports a `.pftrace` and shows the native still-live analysis.

**Architecture:** Mirror the existing `WorkspaceController`/`ListenableBuilder` pattern. A new `NativeProfilingController extends ChangeNotifier` holds imported checkpoints + optional symbol store + ffi log + selection/sort/loading/error state, and imports via an injected seam so screens and the controller are testable without a real `trace_processor` binary. New screens are `android_*_screen.dart`; the controller + value objects live in `src/android/`; the import seam in `src/seams/android/`. `DesktopView`/`desktop_rail`/`desktop_shell` are extended in place. The section is **offline** — NOT behind the `_connected` VM gate.

**Tech Stack:** Flutter desktop (`radar_desktop`), `radar_native` + `radar_native_host` (new deps), `radar_ui`, `file_selector`, `desktop_drop`.

## Global Constraints
- **Reuse, don't reinvent:** module rollups from `summarizeByModule`/`diffModuleSummaries`, status from `NativeDiffStatus`, colors via a new `moduleKindColor` map onto `radar_ui` tokens, widgets from `radar_ui` (`RadarModuleDot`, `RadarBanner`, `RadarExpandableRow`, `RadarStackList`, `RadarMetricTile`, `RadarTag`, `RadarSortHeader`, `RadarSearchField`). No new analysis engine, no new design system.
- **State pattern:** `ChangeNotifier` + `ListenableBuilder`, controller constructed as a field on `_DesktopShellState`, passed to screens by constructor (mirror `WorkspaceController` in `desktop_shell.dart`). Immutable updates in the controller (new lists, `notifyListeners`).
- **Offline:** Android views must render without a VM connection — the `_select` clamp (`if (!_connected && !v.isMemory) return;`) must also allow `v.isAndroid`.
- **Honesty rule (load-bearing):** measured = full-opacity + accent/green; module-only/unsymbolized = amber (`RadarSeverity.warning`); GPU total = literal "not reported · n/a on this device", never 0. Never render "leak" with certainty — use "still-live / growing".
- **Design reference:** `docs/flutter_radar_android_profiling/README.md` (the 6 views + states) and the `.dc.html` prototype (visual reference — the "ANDROID NATIVE" rail group). Scout maps: `scratchpad/scout_desktop.md`, `scout_ui.md`, `scout_dataApi.md`.
- Gate per task: `flutter analyze` clean in `radar_desktop`; unit/widget tests where the task adds testable logic; the app keeps compiling.

---

### Task 1: deps + `moduleKindColor` + `NativeProfilingController`

**Files:**
- Modify `packages/radar_desktop/pubspec.yaml` (add `radar_native`, `radar_native_host`)
- Create `lib/src/android/module_palette.dart`
- Create `lib/src/android/native_profiling_controller.dart`
- Create `test/android/module_palette_test.dart`, `test/android/native_profiling_controller_test.dart`

**Interfaces — Produces:**
```dart
// module_palette.dart (pure)
Color moduleKindColor(NativeModuleKind kind); // app→RadarColors.info, gpuDriver→warning,
//   engine→text50, plugin→accent, system→text25, unknown→text25
String moduleKindLabel(NativeModuleKind kind); // 'App','GPU driver','Engine','Plugin','Runtime','—'

// native_profiling_controller.dart
abstract interface class NativeTraceImporter {
  Future<NativeHeapProfile> importTrace(String path, {String label});
  Future<SymbolStore> importSymbolStore(String path);
  Future<FfiAllocationLog> importFfiLog(String path);
}
enum NativeImportState { idle, loading, error }
final class NativeProfilingController extends ChangeNotifier {
  NativeProfilingController(this._importer);
  // state:
  List<NativeHeapProfile> get checkpoints;
  SymbolStore? get symbolStore;   FfiAllocationLog? get ffiLog;
  int get selectedIndex;          NativeImportState get state;  String? get errorMessage;
  bool get isSymbolized => symbolStore != null && !(symbolStore!.isEmpty);
  // derived:
  NativeHeapProfile? get selected;                 // checkpoints[selectedIndex] or null
  List<NativeModuleSummary> get selectedSummaries; // summarizeByModule(selected), symbol-applied
  int get selectedTotalStillLiveBytes;
  // actions (each notifies):
  Future<void> importTrace(String path, {String label});   // sets loading→adds checkpoint / error
  Future<void> importSymbolStore(String path);             // applies to all checkpoints view
  Future<void> importFfiLog(String path);
  void selectCheckpoint(int index);
  List<NativeModuleDiff> diffCheckpoints(int aIndex, int bIndex); // diffModuleSummaries
}
```
- `importTrace`: set `state=loading`, notify; `await _importer.importTrace`; on success append to `checkpoints` (new list), `selectedIndex = last`, `state=idle`; on throw set `state=error`, `errorMessage`. Symbol application: keep a raw checkpoint list; expose `selectedSummaries` computed from `applySymbolStore(selected, symbolStore)` when `symbolStore != null` else `selected`. Same for detail.
- Tests: fake `NativeTraceImporter` returning a canned `NativeHeapProfile`; assert importTrace appends + selects + notifies; error path sets state/message; `selectedSummaries` reflects `summarizeByModule`; applying a symbol store changes a frame's function in the derived view; `diffCheckpoints` returns `diffModuleSummaries`. `moduleKindColor`/`Label` map each kind.

- [ ] Step 1: failing tests (controller with fake importer; palette). Step 2: run→fail. Step 3: implement (deps first: `dart pub get` at root). Step 4: `flutter test` green, `flutter analyze` clean. Step 5: commit `feat(radar_desktop): NativeProfilingController + module palette`.

---

### Task 2: import seam (`PerfettoTraceImporter`)

**Files:** Create `lib/src/seams/android/perfetto_trace_importer.dart`; Create `test/seams/android/perfetto_trace_importer_test.dart`.

**Interfaces — Produces:**
```dart
final class PerfettoTraceImporter implements NativeTraceImporter {
  const PerfettoTraceImporter({this.traceProcessorPath});
  final String? traceProcessorPath; // else resolveTraceProcessorBinary()
  // importTrace → PerfettoTraceProcessorParser(ProcessTraceProcessorRunner(binaryPath)).parseTrace(path, capturedAt: DateTime.now(), label: label)
  // importSymbolStore → SymbolStore.fromJson(jsonDecode(File(path).readAsStringSync()))
  // importFfiLog → const JsonFfiAllocationLogParser().parse(File(path).readAsStringSync())
}
/// Resolve the trace_processor binary: `traceProcessorPath` arg, else env
/// `RADAR_TP_BIN`, else throw a clear error naming both options.
String resolveTraceProcessorBinary({String? explicit, Map<String,String>? env});
```
- `resolveTraceProcessorBinary` is the pure, testable bit: explicit → env `RADAR_TP_BIN` → throw `StateError` with a message telling the user to set `RADAR_TP_BIN` or pass a path. Unit-test it (explicit wins; env fallback; throw when neither). The `importTrace`/symbol/ffi Process+File paths reuse the gated-tested `radar_native_host`; no unit test drives a real binary here.

- [ ] Steps: test `resolveTraceProcessorBinary` first → implement → `flutter analyze` clean → commit `feat(radar_desktop): PerfettoTraceImporter seam (trace_processor + symbol/ffi import)`.

---

### Task 3: rail group + routing + screen stubs (app stays buildable + navigable)

**Files:** Modify `lib/src/app/desktop_view.dart`, `lib/src/shell/desktop_rail.dart`, `lib/src/shell/desktop_shell.dart`; Create stub screens `lib/src/screens/android_session_screen.dart`, `android_native_screen.dart`, `android_compare_screen.dart`, `android_ffi_screen.dart`, `android_capture_screen.dart` (each a minimal `StatelessWidget` taking `NativeProfilingController` + a title placeholder for now).

**Steps:**
- Add `DesktopView` values: `androidSession`, `androidNative`, `androidCompare`, `androidFfi`, `androidCapture`; add `bool get isAndroid`; add `label` cases (`'Session'`, `'Native still-live'`, `'Compare'`, `'ffi allocations'`, `'Capture / import'`).
- `desktop_rail`: after the STABILITY group, add `_group('ANDROID NATIVE')` + `_item(v, enabled: true)` for the 5 Android views (always enabled — offline).
- `desktop_shell`: add `final NativeProfilingController _android = NativeProfilingController(const PerfettoTraceImporter());` field; dispose it; relax `_select` to allow `v.isAndroid` regardless of `_connected`; add `_content` case arms returning the 5 screens with `controller: _android`.
- Stubs render `Center(child: Text('<name> — coming soon'))` for now (filled in Tasks 4-8), so the app compiles + the section is navigable.
- [ ] Gate: `flutter analyze` clean, app builds. Commit `feat(radar_desktop): ANDROID NATIVE rail group + routing + screen stubs`.

---

### Task 4: Native still-live screen (workhorse table)

**File:** `lib/src/screens/android_native_screen.dart` (replace stub); `test/screens/android_native_screen_test.dart`.
- `ListenableBuilder(listenable: controller)`. Empty state (no checkpoints) → CTA text pointing to Capture/import. Loading → `RadarLinearProgress` + message. Ready → a **checkpoint picker** (dropdown over `controller.checkpoints` labels) + a ranked module table.
- Table: header via `RadarSortHeader` (still-live / allocs / Δ), sortable. Rows = `controller.selectedSummaries`, each a `RadarExpandableRow`: header = `RadarModuleDot(color: moduleKindColor(s.kind))` + module name + `moduleKindLabel` + still-live bytes + alloc count + Δ-vs-previous-checkpoint (red grew / green shrank via `RadarColors.critical`/`accent`); expanded child = the module's callsites (top frame at current fidelity — symbolized function or module-only with an amber `RadarTag`), each with a `›` opening Detail (Task 6) via an `onOpenDetail(callsite)` callback.
- Δ vs previous: if `selectedIndex>0`, compare to `checkpoints[selectedIndex-1]` module summary (reuse `diffModuleSummaries`).
- Widget test: pump with a fake-seeded controller (2 checkpoints) → module rows render with dots + bytes; tapping a row expands to callsites; empty controller shows the CTA.
- [ ] Steps: test → implement → `flutter analyze` + `flutter test` green → commit `feat(radar_desktop): Native still-live screen (module table)`.

---

### Task 5: Compare screen

**File:** `lib/src/screens/android_compare_screen.dart`; test.
- Two dropdown pickers (A, B) over checkpoints (default A=first, B=last). Rows = `controller.diffCheckpoints(aIndex, bIndex)` → per module: `RadarModuleDot` + module + status badge (`RadarTag`: ADDED/GREW red `critical`, SHRANK/GONE green `accent`) + A bytes / B bytes / Δ (Δ colored by sign). Sorted by |Δ| desc (already sorted by `diffModuleSummaries`). Suppress `flat`. Header shows total native Δ. Empty (<2 checkpoints) → a note to import a second checkpoint.
- Widget test: seed 2 checkpoints with a grown + a gone module → both statuses + colors render.
- [ ] commit `feat(radar_desktop): Compare screen (per-module diff)`.

---

### Task 6: Callsite/module Detail (drill-down)

**File:** `lib/src/screens/android_detail_screen.dart` (a panel/route opened from the Native table, taking a target `NativeCallsite` + the controller); test.
- Module + `moduleKindLabel`; `RadarMetricTile` for still-live + live allocations (measured). Module still-live across checkpoints = a small bar trend (reuse `RadarSparkline`/`RadarTrendChart` over each checkpoint's per-module still-live). Native call stack = `RadarStackList` of the callsite frames (function when symbolized else the address/module with an amber module-only `RadarTag`). When unsymbolized: a prominent "Function names unavailable → Add symbols" `RadarBanner`(warning) whose action triggers the symbol-store import.
- Widget test: pump with a callsite → module, tiles, stack render; unsymbolized → the add-symbols banner shows.
- [ ] commit `feat(radar_desktop): Detail drill-down (stack + trend + add-symbols)`.

---

### Task 7: Session overview screen

**File:** `lib/src/screens/android_session_screen.dart`; test.
- States (README 4.1): **empty** (CTA to Capture/import), **loading** (`RadarLinearProgress` + "Analyzing …"), **ready**, **error** (specific message from `controller.errorMessage`). Ready: a **fidelity banner** (`RadarBanner`: Module-only amber ↔ Fully symbolized, with "+ add symbol store"/"+ add ffi log" actions); three total tiles — native still-live (latest, measured), growth first→latest (measured), GPU total (**"not reported · n/a on this device"**, dimmed via `RadarMetricTile(color: RadarColors.text25)`); an imported-artifacts list (checkpoints + symbol-store/ffi presence). Jump-in buttons to Native/Compare.
- Widget test: empty→CTA; ready(1 checkpoint, no symbols)→ amber fidelity banner + the n/a GPU tile literal text present.
- [ ] commit `feat(radar_desktop): Session overview screen`.

---

### Task 8: ffi lane screen + Capture/import screen

**Files:** `lib/src/screens/android_ffi_screen.dart`, `lib/src/screens/android_capture_screen.dart`; tests.
- ffi: if `controller.ffiLog == null` → a note that importing an ffi log unlocks this lane; else master list of `FfiAllocationSite` (site · file · still-live · blocks) + a detail panel showing the Dart stack (`RadarStackList`, all measured). (The ffi rail item may always show but render the "import to unlock" state — keep it simple; conditional visibility is a nicety.)
- Capture/import: file-pick buttons using `file_selector` + `desktop_drop` for **Import Perfetto trace** (`.pftrace` → `controller.importTrace`), **attach symbol store** (`.json` → `controller.importSymbolStore`), **import ffi log** (`.json` → `controller.importFfiLog`). A **Run device capture** button rendered but **disabled with a "Phase 4" tooltip** (adb capture lands in Phase 4). State/prerequisite text: "Android only · iOS not supported", "profile/release build", and the `RADAR_TP_BIN` requirement note.
- Widget tests: ffi empty state; capture screen renders the three import actions + the disabled capture button.
- [ ] commit `feat(radar_desktop): ffi lane + Capture/import screens`.

---

### Task 9: build + on-device-fixture verification

- [ ] `flutter analyze` clean; `flutter test` green (all new screen/controller tests).
- [ ] `flutter build macos --debug` succeeds.
- [ ] Manual smoke (controller does the real work): document the run recipe — `RADAR_TP_BIN=<repo>/.spikes/tools/trace_processor flutter run -d macos`, then import `.spikes/captures/leaklab.pftrace` and confirm the Native still-live table shows `base.apk` with the known ~10 MB. (This step is a documented manual check; the committed automated tests use the fake importer.)
- [ ] commit `chore(radar_desktop): Android Profiling build + smoke recipe`.

---

## Self-review notes
- Coverage: all 6 designer views + the offline controller + import seam + rail/routing. ✓
- Reuse: rollups/diff/status from radar_native; widgets from radar_ui; the state pattern from WorkspaceController. ✓
- Testable-first: Task 3 makes the app buildable + navigable with stubs; Tasks 4-8 fill screens; Task 9 verifies. ✓
- Out of scope: adb/heapprofd device capture (Phase 4 — the capture button is present but disabled); the unstripped-.so symbol extraction (JSON symbol map only).
