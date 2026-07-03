# Radar Desktop — Connected Mode (VM Service) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Add a live **Dart VM Service** connection to the desktop app so the PERFORMANCE (Traces, Frames) and STABILITY (Errors, Stalls) rail groups unlock — the app connects to a running debug/profile Flutter app via a `ws://…/ws` URI (like DevTools) and shows its live perf/stability data. Also unlocks live heap capture + Force GC in MEMORY.

**Architecture:** Mostly **wiring + reuse** (per scout). The 4 live views (`TracesView`/`FramesView`/`ErrorsView`/`StallsView`) already exist in `radar_workbench` and take a `PerfDataController`. Net-new: a `VmServiceUriConnection` (implements the existing `RadarConnection` seam, owns a direct ws client), a ~30-line perf `callExtension` adapter (ports the DevTools one), a connect-URI UI, and shell wiring to flip the gate + route the views.

**Tech Stack:** Flutter desktop (`radar_desktop`), `package:vm_service` (`vmServiceConnectUri`), `radar_workbench` (`RadarConnection`, `PerfDataController`, the 4 views, `ConnectionBar`, `ExtensionNotAvailableException`).

## Global Constraints
- Reuse `radar_workbench`'s `RadarConnection` interface + `PerfDataController` + the 4 views + `ConnectionBar` — do NOT reimplement them. Net-new code is the desktop-owned connection + adapter + connect UI + shell wiring.
- **CI runs Flutter 3.44.4** (local 3.38.1) — avoid APIs deprecated there (no `containsSemantics` in tests; assert semantics via `find.byWidgetPredicate`). Verify the CI JSON conclusion after merge. See [[project_flutter_leak_radar_ci_skew]].
- Honest degradation: a connected app WITHOUT the `flutter_perf_radar` SDK → `PerfDataController.loadState == notAvailable` → the existing "PerfRadar not detected" view. Never fake data. Connection failures (bad URI, refused) surface to the user, never silently.
- `desktop_shell.dart` edits are localized to the field block + `_connected` + `_content()` + the connect-UI placement (Phase 4b already merged its own field-block edit — this branches off updated main, no conflict).
- Testability: inject the connect function into `VmServiceUriConnection` (default `vmServiceConnectUri`) so tests use a fake `VmService`; inject `callExtension` into `PerfDataController` (already supported).

### Exact contracts (reuse — do not modify)
```dart
// radar_workbench: abstract interface class RadarConnection implements Listenable
//   { RadarConnectionState get state; VmService? get vmService; IsolateRef? get isolateRef; }
// RadarConnectionState({required RadarConnectionPhase phase, String? vmName, String? isolateName})
// RadarConnectionPhase { connecting, connected, disconnected }
// PerfDataController({Future<Map<String,Object?>> Function(String method)? callExtension})  // refresh(), loadState, snapshot
// TracesView/FramesView/ErrorsView/StallsView({required PerfDataController controller})
// ExtensionNotAvailableException  (thrown by callExtension when the method is absent)
```

---

### Task 1: `VmServiceUriConnection` seam

**Files:** Create `lib/src/seams/vm_service_uri_connection.dart`; barrel/export as needed; `test/seams/vm_service_uri_connection_test.dart`.

**Interfaces — Produces:**
```dart
final class VmServiceUriConnection extends ChangeNotifier implements RadarConnection {
  VmServiceUriConnection({Future<VmService> Function(String wsUri)? connect})
    : _connectFn = connect ?? vmServiceConnectUri;
  final Future<VmService> Function(String wsUri) _connectFn;
  // RadarConnection:
  @override RadarConnectionState get state;   // default disconnected
  @override VmService? get vmService;
  @override IsolateRef? get isolateRef;
  // desktop-only control (not on the interface — called by desktop UI):
  Future<void> connect(String wsUri);   // connecting -> connect -> getVM -> pick main isolate -> connected; on error -> disconnected + lastError
  Future<void> disconnect();            // svc.dispose(), clear, disconnected
  String? get lastError;
}
```
- `connect`: set `phase=connecting`, notify; `final svc = await _connectFn(wsUri);` `final vm = await svc.getVM();` pick the main isolate (`vm.isolates` — prefer one named `main`, else `.first`); set `_vmService=svc`, `_isolateRef=isolate`, `state=connected(vmName: vm.name, isolateName: isolate.name)`, notify. Wrap in try/catch → on error: `_lastError = e.toString()`, `_applyDisconnected()`. (Mirror `ConnectionStateNotifier._onServiceConnected`/`_applyConnected`/`_applyDisconnected` — but sourced from the owned `svc`, not `serviceManager`.)
- Listen for the socket dropping: `svc.onDone.then((_) => _applyDisconnected())` (VmService exposes `onDone`) so a target-app exit flips the gate back.
- `disconnect`/`dispose`: `await _vmService?.dispose()`, clear handles, `_applyDisconnected()`.

- [ ] **Step 1: failing tests** with a fake `VmService` (a minimal subclass/mock returning a canned `VM` with one isolate from `getVM()`, and a completable `onDone`): assert `connect('ws://x')` → `state.phase == connected`, `vmService`/`isolateRef` non-null, `vmName`/`isolateName` populated, listeners notified; a `_connectFn` that throws → `state.phase == disconnected` + `lastError` set; `disconnect()` → disconnected + handles null; the fake's `onDone` completing → disconnected.
- [ ] **Step 2-4:** run→fail, implement, run→pass; `flutter analyze` clean.
- [ ] **Step 5: commit** `feat(radar_desktop): VmServiceUriConnection (live ws:// VM Service seam)`.

---

### Task 2: desktop perf `callExtension` adapter

**Files:** Create `lib/src/seams/desktop_perf_call.dart`; `test/seams/desktop_perf_call_test.dart`.

**Interfaces — Produces:**
```dart
/// Ports `devtoolsPerfCallExtension` to the desktop's own [RadarConnection]:
/// calls `connection.vmService.callServiceExtension(method, isolateId: connection.isolateRef.id)`,
/// unwraps the `{"result": …}` envelope, maps -32601/"not found" to
/// ExtensionNotAvailableException. Suitable as PerfDataController's callExtension.
Future<Map<String, Object?>> desktopPerfCallExtension(
  RadarConnection connection, String method);
// convenience: a bound closure factory
Future<Map<String, Object?>> Function(String) perfCallFor(RadarConnection c)
  => (m) => desktopPerfCallExtension(c, m);
```
- Body: mirror `devtoolsPerfCallExtension` (read `packages/flutter_leak_radar_devtools/lib/src/adapters/devtools_perf_call.dart`) but source `vmService`/`isolateRef.id` from the passed `connection`; throw `ExtensionNotAvailableException` when either is null or the method is absent (-32601 / "not found" / "unknown method"); unwrap the `{"result": <jsonString>}` envelope with `jsonDecode`.

- [ ] Steps: test with a fake `RadarConnection` whose `vmService.callServiceExtension` (fake) returns a `Response` with `{"result": "{\"ok\":true}"}` → decoded map; a fake that throws an error containing `-32601` → `ExtensionNotAvailableException`; a connection with null vmService/isolate → `ExtensionNotAvailableException`. Implement → analyze clean → commit `feat(radar_desktop): desktop perf callExtension adapter`.

---

### Task 3: connect-URI UI

**Files:** Create `lib/src/shell/connect_bar.dart`; `test/shell/connect_bar_test.dart`.

**Interfaces — Produces:**
```dart
/// A thin bar/control for entering a ws:// URI and connecting/disconnecting.
/// Shows the connection phase + vm/isolate name (reuse radar_workbench's
/// ConnectionBar for the STATUS display; this adds the input + buttons).
class ConnectBar extends StatefulWidget {
  const ConnectBar({super.key, required this.connection});
  final VmServiceUriConnection connection;
}
```
- `ListenableBuilder(listenable: connection)`: when `disconnected` → a `RadarSearchField`/`TextField` for the ws:// URI + a **Connect** button → `connection.connect(uri)`; if `connection.lastError != null` show it (SnackBar or inline). When `connecting` → a spinner. When `connected` → the `ConnectionBar` status (vm/isolate name) + a **Disconnect** button → `connection.disconnect()`.
- Tokens-only (radar_ui); `mounted`-guard any post-await context use.

- [ ] Steps: widget test — disconnected shows the URI field + Connect; entering a URI + tapping Connect calls `connection.connect(<uri>)` (fake connection records it); connected state (fake connection in connected phase) shows Disconnect. Avoid deprecated test APIs. Implement → analyze + test green → commit `feat(radar_desktop): ConnectBar (ws:// connect/disconnect UI)`.

---

### Task 4: shell wiring — flip the gate + route the 4 views

**Files:** Modify `lib/src/shell/desktop_shell.dart`; Modify `test/shell_test.dart`.

**Steps:**
- Add a `final VmServiceUriConnection _connection = VmServiceUriConnection();` field; a `late final PerfDataController _perf = PerfDataController(callExtension: perfCallFor(_connection));`; listen to `_connection` (`initState`: `_connection.addListener(_onConn)`) to rebuild + `_perf.refresh()` on connect; `dispose()` both.
- Replace `final bool _connected = false;` with `bool get _connected => _connection.state.phase == RadarConnectionPhase.connected;`.
- `_content()`: replace the `traces/frames/errors/stalls` stub arms with `TracesView(controller: _perf)` / `FramesView(...)` / `ErrorsView(...)` / `StallsView(...)`. On navigating to a perf/stability view, trigger `_perf.refresh()` (once per navigation, not per build).
- `build()`: insert the `ConnectBar(connection: _connection)` between the window chrome and the rail+content Row (where `ConnectionBar` would naturally sit).
- Keep the ANDROID NATIVE + MEMORY behavior unchanged; the `_select` clamp already reads `_connected` (now live).

- [ ] Steps: update `shell_test.dart` — perf/stability items become selectable + route to the real views once `_connection` is connected (drive via a test seam: allow injecting a pre-connected `VmServiceUriConnection` with a fake, OR assert the gate reads the connection). At minimum: with a disconnected connection, perf/stability stay locked (existing test); with a connected fake connection, they route to `TracesView`/etc. `flutter analyze` + `flutter test` green. `git checkout -- macos` if touched. Commit `feat(radar_desktop): wire connected mode (flip gate + route perf/stability views)`.

---

### Task 5: build + verify

- [ ] `flutter analyze` clean; `flutter test` green; `flutter build macos --debug` succeeds.
- [ ] **Manual connect check (controller):** run a throwaway Flutter app in debug (`flutter run` → note its `ws://…/ws` VM Service URI), connect from the desktop app via `ConnectBar`, confirm the gate unlocks + the status shows the isolate; the perf/stability views show either real data (if the app embeds `flutter_perf_radar`) or the honest "PerfRadar not detected" state. Document the observed result in the commit.
- [ ] commit `chore(radar_desktop): connected mode build + connect verified`.

---

## Self-review notes
- Coverage: connection seam (T1), perf adapter (T2), connect UI (T3), gate+routing (T4), verify (T5). ✓
- Reuse: RadarConnection interface + PerfDataController + the 4 views + ConnectionBar + ExtensionNotAvailableException — all from radar_workbench, unmodified. ✓
- Honesty: notAvailable → the existing "not detected" view; connection errors surfaced. ✓
- Out of scope: ws:// URI AUTO-DISCOVERY (manual paste only); live memory-capture UI polish (canCapture already flips live via the connection); a service extension inside a target app (target must embed flutter_perf_radar for perf data).
