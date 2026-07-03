# Android Profiling — Phase 4b: desktop device-capture UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Light up the desktop's disabled "Run device capture" button — pick a connected device + target package + mode → capture a heapprofd `.pftrace` via the Phase-4a backend → **auto-import** it into the session so the analysis views populate. Device-validated against the live KATIM X3M.

**Architecture:** Extend the existing `NativeProfilingController` with capture, via injected `DeviceProbe` + `NativeHeapCapture` seams (testable with fakes; wired to the real `radar_native_host` adb backend in the shell). The Capture/import screen gains a capture flow. Validate the pulled trace is non-empty (Phase-4a review Minor #1).

**Tech Stack:** Flutter desktop (`radar_desktop`), `radar_native_host` (`DeviceProbe`/`AdbDeviceProbe`, `NativeHeapCapture`/`AdbHeapprofdCapture`, `CaptureRequest`/`CaptureMode`, `ProcessAdbRunner`).

## Global Constraints
- Reuse the Phase-4a backend — no re-implementation of adb/heapprofd. The controller stays the single source of truth (`ChangeNotifier` + `ListenableBuilder`, immutable updates).
- Auto-import reuses the existing `importTrace` path (`PerfettoTraceImporter`) — one import code path.
- **Honest errors:** capture failures (no device, unauthorized, wrong package → empty trace, adb/perfetto error) surface to the user (SnackBar), never silently. Validate the pulled trace is non-empty before importing; an empty/tiny trace → a clear "capture produced no data (is the package running / correct?)" error.
- Offline section unchanged; existing tests green; `flutter analyze` clean. Avoid Flutter APIs deprecated in newer stable (CI runs 3.44.4) — see [[project_flutter_leak_radar_ci_skew]]: no `containsSemantics` etc.
- `git checkout --` any `macos/` build artifacts before committing.

---

### Task 1: capture in `NativeProfilingController` (injected seams)

**Files:** Modify `lib/src/android/native_profiling_controller.dart`; Modify `test/android/native_profiling_controller_test.dart`.

**Interfaces — Produces (additions to the controller):**
```dart
// constructor gains optional capture seams (null → capture unavailable):
NativeProfilingController(this._importer, {DeviceProbe? deviceProbe, NativeHeapCapture? capture});
bool get canCapture => _deviceProbe != null && _capture != null;
enum CaptureState { idle, probing, capturing, error }   // or reuse NativeImportState — your call
List<AndroidDevice> get devices;         // last probe result
CaptureState get captureState; String? get captureError;
Future<void> refreshDevices();           // _deviceProbe.probe() -> devices, notify; catch -> error
Future<void> captureAndImport(CaptureRequest request); // capturing -> _capture.capture to a temp path
//   -> validate File(path).lengthSync() > <MIN_TRACE_BYTES=1024> (else error 'no data')
//   -> await importTrace(path, label: <pkg@time>) -> idle; catch -> error + message
```
- `captureAndImport`: set `captureState = capturing`, notify; `final out = <tempdir>/capture.pftrace`; `await _capture.capture(request, outputPath: out)`; if `File(out).lengthSync() <= 1024` → error "capture produced no data — is `${request.packageId}` installed and correct?"; else `await importTrace(out, label: ...)` (reuses the existing import → appends checkpoint + selects it); `captureState = idle`. On any throw → `captureState = error`, `captureError = e.toString()`.

- [ ] **Step 1: failing tests.** Fakes: `_FakeDeviceProbe` (returns a canned ready `AndroidDevice`), `_FakeCapture implements NativeHeapCapture` (writes a >1KB dummy file to `outputPath` and returns it), and the existing fake importer. Assert: `canCapture` true when seams provided (false when null); `refreshDevices` populates `devices` + notifies; `captureAndImport` → the fake capture is called with the request, the resulting file is imported (a checkpoint appended + selected), `captureState` ends `idle`; a fake capture that writes a 0-byte file → `captureState == error` with a "no data" message and NO checkpoint appended; a fake capture that throws → error state.
- [ ] **Step 2-4:** run→fail, implement, run→pass; `flutter analyze` clean.
- [ ] **Step 5: commit** `feat(radar_desktop): capture+auto-import in NativeProfilingController`.

---

### Task 2: capture flow UI + wire the real seams

**Files:** Modify `lib/src/screens/android_capture_screen.dart` (replace the disabled button with a real flow); Modify `lib/src/shell/desktop_shell.dart` (construct the controller with the real capture seams); Modify `test/screens/android_capture_screen_test.dart`.

**Wire the seams (`desktop_shell.dart`):**
- change `NativeProfilingController(const PerfettoTraceImporter())` to also pass `deviceProbe: const AdbDeviceProbe(ProcessAdbRunner()), capture: AdbHeapprofdCapture(const ProcessAdbRunner())`. (This is the one `desktop_shell.dart` edit — a single construction line, in the field block.)

**Capture flow (`android_capture_screen.dart`):**
- Replace the disabled "Run device capture" row with an **enabled** control (only if `controller.canCapture`) that opens a capture form (inline expansion or a dialog):
  - a **device** dropdown from `controller.devices` (with a refresh button calling `controller.refreshDevices()`; show device `label`; empty → "No device — connect one & enable USB debugging").
  - a **package** text field (default `com.katim.leak_lab` is fine as a hint; user types the target package).
  - a **mode** toggle (Attach / Startup) → `CaptureMode`.
  - a **duration** (a few presets, e.g. 15s/30s/60s → durationMs).
  - a **Capture** button → `controller.captureAndImport(CaptureRequest(packageId, mode, durationMs, serial: selectedDevice.serial))`.
- While `controller.captureState == capturing`: show a `RadarLinearProgress` + "Capturing from &lt;device&gt;… (&lt;duration&gt;s)".
- On error: SnackBar with `controller.captureError` (guard `context.mounted`).
- On success: the Session/Native views already update reactively (the checkpoint was appended + selected) — a brief "Captured & imported" confirmation is enough.
- Call `controller.refreshDevices()` once when the screen first builds (post-frame) so the device list is populated.

**Tests (widget):**
- with a controller whose `canCapture` is true (fake seams) + a seeded device → the capture control renders enabled, the device dropdown shows the device; tapping Capture calls `captureAndImport` (assert via a spy controller or a fake that records the call).
- `canCapture` false (no seams) → the disabled/"connect a device" state.
- (No real adb in widget tests — the real path is the Task 3 on-device check.)

- [ ] Steps: tests first → implement → `flutter analyze` clean + `flutter test` green → `git checkout -- macos` if touched → commit `feat(radar_desktop): device-capture flow in Capture/import (enable the button)`.

---

### Task 3: build + on-device end-to-end verification

- [ ] `flutter analyze` clean; `flutter test` green (all prior + new).
- [ ] `flutter build macos --debug` succeeds.
- [ ] **Controller runs the real end-to-end:** launch the app with the device connected, use the capture flow to capture `com.katim.leak_lab` (startup mode) → confirm a checkpoint appears and the Native still-live table shows `base.apk`. (Documented manual check; automated tests use fakes.) Record the observed result in the commit body.
- [ ] commit `chore(radar_desktop): Phase 4b capture verified on device`.

---

## Self-review notes
- Coverage: controller capture+validate+auto-import (T1), the UI flow + real-seam wiring (T2), on-device proof (T3). ✓
- Reuse: Phase-4a backend + the existing importTrace path; single shell edit (construction line) to minimize the connected-mode conflict surface. ✓
- Honesty: empty-trace guard + surfaced capture errors. ✓
- Out of scope: connected mode (separate branch, sequenced after this), symbol extraction, capture presets beyond a couple.
