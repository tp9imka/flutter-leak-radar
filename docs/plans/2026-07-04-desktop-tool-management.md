# Radar Desktop — External Tool Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Make Radar Desktop discover, report, install, and persist the external CLI tools it shells out to (`trace_processor`, `adb`, `llvm-symbolizer`, `llvm-readelf`) — so a Finder/Dock-launched app (which can't see the shell env) finds its tools, clearly shows what's missing, and lets the user install or locate the rest.

**Architecture:** A pure discovery/status layer in `radar_native_host` (`ExternalTool` + `ToolProbe` resolving config→env→common-locations→PATH and verifying via `--version`; a `TraceProcessorInstaller`). A `radar_desktop` `ToolsController` (persists user paths via `path_provider`, probes all tools, installs/locates/rechecks) that feeds resolved paths into the existing profiling seams and drives a Tools screen + a chrome health indicator + in-context missing-tool banners.

**Tech Stack:** `radar_native_host` (dart:io — `Process.run`, `HttpClient`), `radar_desktop` (Flutter, `path_provider`, `file_selector`, `radar_ui`).

## Global Constraints
- **The GUI-env problem is the root cause:** a macOS app launched from Finder/Dock gets a minimal `PATH` and none of the user's exported env (`RADAR_TP_BIN`, etc.). Resolution MUST therefore also search **common on-disk locations** and honor a **persisted user config** — not rely on env/PATH alone. Still honor env/PATH (a terminal launch should keep working).
- **Honest status:** a tool is "found" only if a path exists AND `--version` (or equivalent) runs successfully — never claim found on a bare name that isn't really there. Missing tools are surfaced clearly, never silently.
- **No uninvited system changes:** only `trace_processor` gets a true one-click install (a single self-contained binary downloaded to an app-managed dir). `adb`/`llvm-*` are auto-discovered + "Locate…"-able; do NOT run `brew install` automatically — show a copyable hint instead.
- Reuse existing seams: `PerfettoTraceImporter` (takes an explicit trace_processor path), `ProcessAdbRunner(adbPath:)`, `LlvmSymbolizer(binaryPath:)`, `LlvmReadelfBuildIdReader(binaryPath:)`, `SymbolStoreBuilder`. Do not reimplement them.
- Persist config the way the app already persists the workspace (`path_provider` app-support dir + JSON) — follow `WorkspaceController`/`PersistedSession`.
- CI runs Flutter **3.44.4** — no `containsSemantics`/`matchesSemantics` in tests; `flutter analyze`/`dart analyze` clean; **`dart format .` clean** (the repo's format gate). Pure-Dart `radar_native_host` uses `dart test`. Verify the CI JSON conclusion after merge. See [[project_flutter_leak_radar_ci_skew]]. `git checkout -- packages/radar_desktop/macos` before committing.

---

### Task 1: `ExternalTool` + `ToolProbe` discovery (radar_native_host, pure)

**Files:** Create `packages/radar_native_host/lib/src/tools/external_tool.dart`, `.../tools/tool_probe.dart`; export from the barrel; tests `packages/radar_native_host/test/tools/tool_probe_test.dart`.

**Produces:**
```dart
enum ExternalTool { traceProcessor, adb, llvmSymbolizer, llvmReadelf }

extension ExternalToolInfo on ExternalTool {
  String get id;            // 'trace_processor' | 'adb' | 'llvm-symbolizer' | 'llvm-readelf'
  String get label;         // 'Perfetto trace_processor', 'Android adb', ...
  String get purpose;       // one line: what breaks without it
  String get envVar;        // 'RADAR_TP_BIN' | '' (adb has none) | 'RADAR_LLVM_SYMBOLIZER' | 'RADAR_READELF'
  List<String> get versionArgs;   // e.g. ['--version']; trace_processor: ['--version']
  bool get isRequiredForImport;   // trace_processor true; others feature-specific
}

/// Where a resolved path came from — shown in the UI.
enum ToolSource { config, env, homebrew, androidSdk, ndk, path, none }

final class ToolStatus {
  const ToolStatus({required this.tool, this.path, this.version, required this.found, required this.source});
  final ExternalTool tool; final String? path; final String? version; final bool found; final ToolSource source;
}

/// Verifies a tool exists + runs. Inject [exists] (file check) and [run]
/// (process) for tests; the real impls use dart:io.
final class ToolProbe {
  const ToolProbe({FileProbe? exists, ProcessProbe? run, List<String> Function(ExternalTool)? commonLocations, String? homeDir});
  Future<ToolStatus> probe(ExternalTool tool, {String? configuredPath, Map<String, String> env = const {}});
}
typedef FileProbe = bool Function(String path);
typedef ProcessProbe = Future<({int exitCode, String stdout, String stderr})> Function(String exe, List<String> args);
```
- **Resolution order** in `probe`: `configuredPath` (if non-null) → `env[tool.envVar]` (if envVar non-empty & set) → each `commonLocations(tool)` that `exists` → the bare `tool.id` (let PATH resolve). The FIRST candidate whose `exists` is true (or, for the bare-name case, whichever) is verified by running `run(candidate, tool.versionArgs)`; on exit 0, `found=true`, `version=` first non-empty stdout/stderr line trimmed, `source=` the tier it came from. If a candidate exists but `--version` fails, keep trying later candidates; if none verify → `found=false, source=none`.
- **Default common locations** (macOS; `homeDir` defaults to `HOME`): traceProcessor → `[$home/Library/Application Support/radar_desktop/bin/trace_processor, /opt/homebrew/bin/trace_processor, /usr/local/bin/trace_processor]`; adb → `[/opt/homebrew/bin/adb, $home/Library/Android/sdk/platform-tools/adb, /usr/local/bin/adb]`; llvmSymbolizer/llvmReadelf → the newest match of `$home/Library/Android/sdk/ndk/*/toolchains/llvm/prebuilt/*/bin/<id>` plus `/opt/homebrew/opt/llvm/bin/<id>`, `/opt/homebrew/bin/<id>`. (For the NDK glob, list the `ndk` dir and pick the highest version dir; keep it simple and injectable via `commonLocations`.)

- [ ] **Step 1: failing tests** with a fake `exists` + fake `run`: a `configuredPath` that exists + version-runs → found, source config, version parsed; a missing configuredPath but an env path that verifies → source env; nothing configured/env but a homebrew location exists+verifies → source homebrew; a path that exists but `--version` exits 1 → falls through; nothing anywhere → found=false, source none. Test `ExternalTool` metadata (ids/envVars) for each value.
- [ ] **Step 2-4:** run→fail, implement (real `FileProbe`=`File(p).existsSync`, `ProcessProbe`=`Process.run`), run→pass; `dart analyze` clean; `dart format` 0 changed.
- [ ] **Step 5: commit** `feat(radar_native_host): ExternalTool + ToolProbe (discover/verify external tools)`.

---

### Task 2: `TraceProcessorInstaller` (radar_native_host)

**Files:** Create `packages/radar_native_host/lib/src/tools/trace_processor_installer.dart`; export; tests `test/tools/trace_processor_installer_test.dart`.

**Produces:**
```dart
/// Downloads the single trace_processor binary from get.perfetto.dev to
/// [destPath], makes it executable, and returns the path. Injectable
/// [download] (writes bytes to a path) for tests.
final class TraceProcessorInstaller {
  const TraceProcessorInstaller({Downloader? download});
  static const String url = 'https://get.perfetto.dev/trace_processor';
  Future<String> install({required String destPath}); // mkdirs, download url→destPath, chmod 0755, return destPath
}
typedef Downloader = Future<void> Function(String url, String destPath);
```
- Real `download`: `HttpClient` GET with redirect-follow, stream to a temp file then rename to destPath (atomic-ish); throw a clear exception on non-200. After download, `File(destPath).setExecutablePermission?` — Dart lacks chmod, so `Process.run('chmod', ['+x', destPath])`. Create parent dirs.
- [ ] **Step 1: failing tests** with a fake `download` (writes a stub file): `install` creates parent dirs, calls download with the right url+dest, chmods, returns destPath; a download that throws propagates a clear error. (No real network in unit tests.)
- [ ] **Step 2-4:** run→fail, implement, run→pass; analyze + format clean.
- [ ] **Step 5: commit** `feat(radar_native_host): TraceProcessorInstaller (fetch trace_processor from get.perfetto.dev)`.

---

### Task 3: `ToolConfig` persistence + `ToolsController` (radar_desktop)

**Files:** Create `packages/radar_desktop/lib/src/tools/tool_config.dart`, `.../tools/tools_controller.dart`; tests `test/tools/tools_controller_test.dart`.

**Produces:**
```dart
/// User-set tool paths, persisted as JSON. Immutable.
final class ToolConfig {
  const ToolConfig(this.pathByToolId);
  final Map<String, String> pathByToolId;         // 'trace_processor' -> '/path'
  Map<String, Object?> toJson(); factory ToolConfig.fromJson(Map<String, Object?>);
  ToolConfig withPath(String toolId, String path);
}

final class ToolsController extends ChangeNotifier {
  ToolsController({ToolProbe probe = const ToolProbe(), TraceProcessorInstaller installer = const TraceProcessorInstaller(),
    ToolConfigStore? store, Map<String,String>? env, String? installDir});
  List<ToolStatus> get statuses;                  // one per ExternalTool, current probe result
  ToolStatus statusOf(ExternalTool);
  String? resolvedPath(ExternalTool);             // convenience for the seams (null if not found)
  bool get allRequiredPresent;                    // trace_processor (import) at minimum; expose per-feature helpers too
  bool get anyMissing;
  Future<void> load();                            // read config, probe all
  Future<void> recheck();                         // re-probe all
  Future<void> locate(ExternalTool, String path); // save to config + persist + re-probe that tool
  Future<void> installTraceProcessor();           // installer.install(dest=<installDir>/trace_processor) -> locate()
  String? installError;                           // surfaced honestly on failure
}
/// Persists ToolConfig JSON to the app-support dir — mirror WorkspaceController's persistence.
abstract interface class ToolConfigStore { Future<ToolConfig> read(); Future<void> write(ToolConfig); }
final class FileToolConfigStore implements ToolConfigStore { /* path_provider getApplicationSupportDirectory + tools.json */ }
```
- `load`: read config (empty on first run), probe every `ExternalTool` with its configured path + `env` (default `Platform.environment`), store statuses, notify.
- `locate`: `config = config.withPath(tool.id, path)`; `store.write(config)`; re-probe that tool; notify.
- `installTraceProcessor`: `final p = await installer.install(destPath: '$installDir/trace_processor')` (installDir default `<appSupport>/bin`); on success `locate(traceProcessor, p)`; on failure set `installError` + notify (no crash).
- [ ] **Step 1: failing tests** with a fake `ToolProbe` (canned statuses), fake installer, in-memory `ToolConfigStore`: `load` probes all + populates statuses; `locate` writes config + re-probes so `resolvedPath` updates + `statusOf` reflects found; `installTraceProcessor` calls the installer then marks trace_processor found; a throwing installer → `installError` set, no throw; `allRequiredPresent` true only when trace_processor found. Use fakes — no real fs/process.
- [ ] **Step 2-4:** run→fail, implement, `flutter analyze` clean, `flutter test` green, `dart format` 0 changed.
- [ ] **Step 5: commit** `feat(radar_desktop): ToolsController + persisted ToolConfig`.

---

### Task 4: feed resolved tool paths into the profiling seams (radar_desktop)

**Files:** Modify `lib/src/shell/desktop_shell.dart`; Modify `lib/src/seams/android/perfetto_trace_importer.dart` (accept a lazy path) and the controller wiring; Modify `lib/src/android/native_profiling_controller.dart` if needed; tests updated.

**Goal:** the importer/capture/symbolizer use the CURRENT resolved path from `ToolsController` (so Install/Locate takes effect without restart and without losing imported state).
- Give the seams a **lazy path source** rather than a fixed string: e.g. `PerfettoTraceImporter({String? Function()? traceProcessorPath})` that, when set, is used as the `explicit` path (falls back to env when null). Similarly the shell constructs `AdbHeapprofdCapture(ProcessAdbRunner(adbPath: tools.resolvedPath(adb) ?? 'adb'))` — but since adbPath is fixed at construction, instead pass a resolver: add an optional `String Function()? adbPath` to `ProcessAdbRunner` (falls back to `'adb'`), OR reconstruct the adb runner from `ToolsController` on change. Choose the lazy-resolver approach for all three so a config change is picked up live. Keep the default behavior (env/bare-name) intact when the resolver returns null.
- The shell holds the `ToolsController` (calls `load()` in initState), constructs `NativeProfilingController` with importer/capture/builder whose path sources read `tools.resolvedPath(...)`. Listen to `tools` to `setState` (so banners/health update).
- [ ] **Step 1: failing tests** — a `ToolsController` (fake probe) reporting trace_processor at `/x/tp` makes the importer resolve `/x/tp`; reporting none falls back to env/throw as before. A change (locate) is reflected on the next import call (lazy). Keep existing NativeProfiling/import tests green.
- [ ] **Step 2-4:** run→fail, implement, analyze + test + format clean; `git checkout -- macos`.
- [ ] **Step 5: commit** `feat(radar_desktop): resolve tool paths from ToolsController in the profiling seams`.

---

### Task 5: Tools screen + chrome health indicator + in-context banners (radar_desktop)

**Files:** Create `lib/src/screens/tools_screen.dart`; Modify `lib/src/app/desktop_view.dart` (add `tools`), `lib/src/shell/desktop_rail.dart` (a SETUP/TOOLS item, always enabled), `lib/src/shell/desktop_shell.dart` (route + health dot), `lib/src/shell/desktop_window_chrome.dart` (health dot), `lib/src/screens/android_capture_screen.dart` (missing-tool banner); tests.

- **ToolsScreen:** for each `ToolStatus` a card — label + purpose, a status badge (**found · `<path>` · `<version>`** in accent / **missing** in amber with the resolution tiers tried), a **Locate…** button (`file_selector` `openFile`/`getOpenPath` → `tools.locate(tool, path)`), an **Install** button for `traceProcessor` only (→ `tools.installTraceProcessor()`, show progress + `installError`), a **Re-check all** action (`tools.recheck()`), and a copyable install hint for adb/llvm (`brew install …` / NDK path). Tokens-only (`radar_ui`); reuse `RadarBanner`.
- **Rail:** add `DesktopView.tools` (predicate `isTools`) as a bottom "SETUP" group item, always enabled (never gated).
- **Chrome health dot:** in `desktop_window_chrome.dart` a small dot — accent when `!tools.anyMissing`, amber when `tools.anyMissing` — with a tooltip ("N tools missing") that, tapped, selects the Tools view. (Pass the controller/health + an onOpenTools callback down from the shell.)
- **In-context banner:** on `android_capture_screen.dart`, when `traceProcessor` is missing show a `RadarBanner` ("Perfetto trace_processor not found — set it up in Tools") with an action that navigates to Tools, ABOVE the import actions; likewise gate/hint the "Resolve from .so directory" action when llvm is missing. (Navigation: expose an `onOpenTools` callback or route via the shell.)
- Avoid `containsSemantics` in tests. Widget tests: ToolsScreen shows a found tool's path+version and a missing tool's Install/Locate; tapping Install calls the controller (fake); the capture banner shows when trace_processor missing.
- [ ] **Step 1-4:** tests first → implement → `flutter analyze` + `flutter test` green → `dart format` 0 changed → `git checkout -- macos`.
- [ ] **Step 5: commit** `feat(radar_desktop): Tools screen + health indicator + missing-tool banners`.

---

### Task 6: build + machine verification

- [ ] `flutter analyze` + `dart analyze` clean; `flutter test` + `dart test` green; `flutter build macos --debug` succeeds; `dart format --set-exit-if-changed .` clean repo-wide.
- [ ] **Real check (documented):** launch the app from Finder (no shell env); Tools screen shows adb + llvm auto-discovered (Homebrew/NDK) and trace_processor missing; **Install** downloads trace_processor and it flips to found; a `.pftrace` import then works; the chrome dot goes from amber→accent. Record the observed result in the commit body.
- [ ] commit `chore(radar_desktop): tool management verified from a Finder launch`.

---

## Self-review notes
- Coverage: discovery+verify (T1), install (T2), config+controller (T3), seam wiring (T4), UI+surfacing (T5), verify (T6). ✓
- Root cause addressed: resolution searches config→env→common-locations→PATH, so a Finder-launched app finds tools; paths persist. ✓
- Honesty: found only when `--version` runs; missing surfaced via banners + chrome dot; install failure → `installError`, no crash; no uninvited `brew install`. ✓
- Out of scope: Windows/Linux tool locations (macOS-first app); auto-updating tools; installing adb/llvm toolchains (discover + Locate + hint only).
