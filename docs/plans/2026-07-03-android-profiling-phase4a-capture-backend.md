# Android Profiling — Phase 4a: device capture backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Add the `radar_native_host` backend that captures a heapprofd `.pftrace` from a connected Android device over `adb` — the engine behind the desktop's (currently disabled) "Run device capture" button. Device-validated against a real KATIM X3M.

**Architecture:** Mirror the proven `TraceProcessorRunner` seam pattern: an injectable `AdbRunner` runs `adb` commands via `Process`; pure functions build the heapprofd config + parse `adb devices`/`getprop`; a `DeviceProbe` lists/inspects devices and a `NativeHeapCapture` orchestrates the capture (config → `perfetto` → `adb pull`). Unit-test the pure logic + orchestration with a fake runner; a gated integration test captures from the real device.

**Tech Stack:** Dart (`dart:io` — host package), `radar_native_host`. The exact commands are those proven in `docs/spikes/2026-07-03-native-gpu-spike-results.md`.

## Global Constraints
- **radar_native stays pure** — all `dart:io` lives in `radar_native_host`.
- Analysis mirrors `leak_graph`; `dart analyze --fatal-infos` + `dart format` clean.
- **Device-proven commands are law** (from the spikes, verbatim shape):
  - heapprofd config (textproto): `android.heapprofd` data source, `sampling_interval_bytes`, `process_cmdline: "<pkg>"`, `shmem_size_bytes: 16777216`, `block_client: true`, `continuous_dump_config { dump_phase_ms dump_interval_ms }`, top-level `duration_ms`.
  - **attach mode** (app already running): push config → `adb shell perfetto --txt -c <cfg> -o <out.pftrace>` → `adb pull`.
  - **startup mode** (catch startup leaks): `adb shell am force-stop <pkg>` → `adb shell perfetto --background --txt -c <cfg> -o <out>` (returns immediately) → `adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1` → wait `duration` → `adb pull`.
  - device list: `adb devices -l` → lines `SERIAL\tdevice ... model:X device:Y`; props via `adb -s SERIAL shell getprop <key>`.
- **Testability:** `AdbRunner` is injected; pure `heapprofdConfig`/`parseAdbDevices` are unit-tested; capture orchestration is tested with a fake runner asserting the command sequence; the REAL `Process` path is covered only by the gated integration test (skips unless `RADAR_ADB_DEVICE` is set).
- **Honest errors:** non-zero adb/perfetto exit → a typed exception carrying stderr; no silent failures.

---

### Task 1: `AdbRunner` + `heapprofdConfig` + `parseAdbDevices`

**Files:**
- Create `lib/src/capture/adb_runner.dart`
- Create `lib/src/capture/heapprofd_config.dart`
- Create `lib/src/capture/adb_devices.dart`
- barrel exports; tests `test/capture/heapprofd_config_test.dart`, `test/capture/adb_devices_test.dart`

**Interfaces — Produces:**
```dart
class AdbResult { const AdbResult(this.exitCode, this.stdout, this.stderr); ... }
abstract interface class AdbRunner {
  /// Runs `adb [-s serial] <args>`; [stdin] is piped if non-null.
  Future<AdbResult> run(List<String> args, {String? serial, String? stdin});
}
final class ProcessAdbRunner implements AdbRunner {
  const ProcessAdbRunner({this.adbPath = 'adb'});
  final String adbPath;
}
class AdbException implements Exception { /* args, exitCode, stderr */ }

/// The device-proven heapprofd textproto config.
String heapprofdConfig({
  required String packageId,
  int samplingIntervalBytes = 4096,
  required int durationMs,
  int dumpIntervalMs = 3000,
  int bufferSizeKb = 131072,
  int shmemSizeBytes = 16777216,
});

class AdbDeviceLine { const AdbDeviceLine(this.serial, this.state, this.model); ... }
/// Parse `adb devices -l` stdout into device lines (state e.g. 'device',
/// 'unauthorized', 'offline'; model from the `model:` token if present).
List<AdbDeviceLine> parseAdbDevices(String stdout);
```

- [ ] **Step 1: failing tests.** `heapprofd_config_test.dart`: `heapprofdConfig(packageId: 'com.x', durationMs: 30000)` contains `process_cmdline: "com.x"`, `duration_ms: 30000`, `name: "android.heapprofd"`, `dump_interval_ms: 3000`, `block_client: true`. `adb_devices_test.dart`: parse a canned `adb devices -l` block with one `device` + one `unauthorized` + the `List of devices attached` header → 2 entries with correct serial/state/model; empty list when only the header.
- [ ] **Step 2: run → fail.**
- [ ] **Step 3: implement.** `heapprofdConfig` returns the textproto (plain ASCII — no control chars). `parseAdbDevices` skips the header line + blank lines, splits on whitespace, extracts serial + state + the `model:` token. `ProcessAdbRunner.run` builds `[if serial ...['-s', serial], ...args]`, `Process.run(adbPath, ...)`, pipes stdin if given, returns `AdbResult`; a convenience `runOrThrow` that throws `AdbException` on non-zero.
- [ ] **Step 4: run → pass; analyze + format clean; barrel exports.**
- [ ] **Step 5: commit** `feat(radar_native_host): AdbRunner + heapprofd config + adb devices parser`.

---

### Task 2: `DeviceProbe` + `AndroidDevice`

**Files:** Create `lib/src/capture/device_probe.dart`; barrel; `test/capture/device_probe_test.dart`.

**Interfaces — Produces:**
```dart
class AndroidDevice {
  const AndroidDevice({required this.serial, required this.state,
    this.model, this.androidRelease, this.buildType});
  final String serial; final String state; // 'device'|'unauthorized'|'offline'
  final String? model; final String? androidRelease; final String? buildType;
  bool get isReady => state == 'device';
  String get label => [model ?? serial, if (androidRelease != null) 'android $androidRelease'].join(' · ');
}
abstract interface class DeviceProbe { Future<List<AndroidDevice>> probe(); }
final class AdbDeviceProbe implements DeviceProbe {
  const AdbDeviceProbe(this._runner);
  final AdbRunner _runner;
  // probe(): `adb devices -l` -> parseAdbDevices; for each 'device'-state serial,
  //   `adb -s serial shell getprop ro.product.model` + `ro.build.version.release`
  //   + `ro.build.type` to enrich model/androidRelease/buildType.
}
```

- [ ] Steps: test `AdbDeviceProbe` with a fake `AdbRunner` (canned `adb devices -l` + canned getprop replies keyed by args) → asserts a ready device with model/android/build filled, and that an `unauthorized` device is returned with `isReady == false` and no getprop call for it. Implement → analyze/format clean → commit `feat(radar_native_host): DeviceProbe (adb devices + getprop enrichment)`.

---

### Task 3: `NativeHeapCapture` (attach + startup)

**Files:** Create `lib/src/capture/native_heap_capture.dart`; barrel; `test/capture/native_heap_capture_test.dart`.

**Interfaces — Produces:**
```dart
enum CaptureMode { attach, startup }
class CaptureRequest {
  const CaptureRequest({required this.packageId, this.mode = CaptureMode.attach,
    this.durationMs = 30000, this.samplingIntervalBytes = 4096, this.serial});
  ...
}
abstract interface class NativeHeapCapture {
  /// Captures a heapprofd .pftrace to [outputPath] and returns it.
  Future<String> capture(CaptureRequest request, {required String outputPath});
}
final class AdbHeapprofdCapture implements NativeHeapCapture {
  const AdbHeapprofdCapture(this._runner, {this.sleep = _realSleep});
  final AdbRunner _runner;
  final Future<void> Function(Duration) sleep; // injectable for tests
}
```
Orchestration (device paths under `/data/misc/perfetto-traces/`):
- both modes: write `heapprofdConfig(...)` to the device (`adb ... shell "cat > <cfg>"` via `stdin`).
- **attach:** `adb shell perfetto --txt -c <cfg> -o <trace>` (blocks duration) → `adb pull <trace> <outputPath>`.
- **startup:** `adb shell am force-stop <pkg>` → `adb shell perfetto --background --txt -c <cfg> -o <trace>` → `adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1` → `await sleep(duration + slack)` → `adb pull <trace> <outputPath>`.
- non-zero exit anywhere → `AdbException`; return `outputPath` on success.

- [ ] Steps: test with a fake `AdbRunner` (records the command sequence) + a fake `sleep`: assert **attach** issues config-write → `perfetto ... -c ... -o ...` → `pull`, in order, with the package + duration in the config; assert **startup** issues force-stop → `perfetto --background` → `monkey`/`am start` → pull. Assert a non-zero adb result throws `AdbException`. Implement → analyze/format clean → commit `feat(radar_native_host): AdbHeapprofdCapture (attach + startup modes)`.

---

### Task 4: gated real-device integration test

**Files:** Create `test/integration/real_capture_test.dart`.
- Reads `RADAR_ADB_DEVICE` (a serial or `'any'`) from `Platform.environment`; if unset → `print('[skip] ...'); return;` (passes).
- Else: `AdbDeviceProbe(const ProcessAdbRunner())` → expect at least one ready device. Then `AdbHeapprofdCapture(const ProcessAdbRunner()).capture(CaptureRequest(packageId: 'com.katim.leak_lab', mode: CaptureMode.startup, durationMs: 12000), outputPath: <temp>.pftrace)` → assert the file exists and is > 1 KB. (Controller will additionally parse it in Phase 4b; here we only assert a real trace came back.)

- [ ] Steps: write the gated test; run UNSET → passes (skips); commit `test(radar_native_host): gated real-device capture integration test`. (The controller runs the real capture against the connected KATIM X3M during review.)

---

## Self-review notes
- Coverage: config (T1), device-list parse (T1), probe enrichment (T2), attach+startup orchestration (T3), real-device proof (T4). ✓
- Purity: dart:io only in radar_native_host; radar_native untouched. ✓
- Testability: AdbRunner + sleep injected; pure builders/parsers unit-tested; real Process only in the gated test. ✓
- Out of scope: desktop capture flow/button (Phase 4b), symbol extraction (separate phase), GPU-total/Lane-A.
