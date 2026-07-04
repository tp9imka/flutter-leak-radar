# Connect: scan `adb logcat` for a device VM service — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** An optional, manual **"Scan device"** button next to the Connect bar's ws:// field. On tap it scans `adb logcat` on the selected Android device for the Flutter VM-service line, `adb forward`s the device port to the host, and fills the field with a ready-to-connect `ws://…/ws` URI — so the user doesn't hunt for the token-bearing URI by hand. Keep it SIMPLE: fill the field (the user still taps Connect); newest match wins; no auto-polling.

**Why:** the target apps are Android, and Flutter prints `The Dart VM service is listening on http://127.0.0.1:<devicePort>/<token>=/` to logcat. That device-side URI needs an `adb forward` to be reachable from the host. This is exactly how `flutter attach` discovers Android apps.

**Tech Stack:** `radar_native_host` (`AdbRunner` — already exists), `radar_desktop` (`ConnectBar`, `ToolsController` for the resolved adb path, the capture screen's selected device serial).

## Global Constraints
- Reuse the existing `AdbRunner`/`ProcessAdbRunner` (+ the desktop's resolved adb path via `LazyAdbRunner`/`ToolsController`). Do NOT reimplement adb.
- Match Flutter's OWN regex verbatim: `RegExp(r'The Dart VM service is listening on ((http|//)[a-zA-Z0-9:/=_\-\.\[\]]+)')` (plus tolerate an older `Observatory listening on <url>`). Newest (last in the dump) wins.
- Honest failure: no device → clear message; logcat has no VM-service line → "no running debug/profile app found in logcat"; adb/forward failure → surfaced (never a crash). This is optional — never blocks the manual paste path.
- CI: Flutter 3.44.4, no `containsSemantics`; analyze clean; `dart format --set-exit-if-changed .` clean; pure-Dart `radar_native_host` uses `dart test`. `git checkout -- packages/radar_desktop/macos` before committing.

---

### Task 1: `AndroidVmServiceDiscovery` (radar_native_host)

**Files:** Create `packages/radar_native_host/lib/src/capture/android_vm_service_discovery.dart`; export from the barrel; test `test/capture/android_vm_service_discovery_test.dart`.

**Produces:**
```dart
/// A VM-service endpoint parsed from `adb logcat`.
final class DeviceVmServiceUri {
  const DeviceVmServiceUri({required this.host, required this.port, required this.path});
  final String host;   // usually 127.0.0.1
  final int port;      // DEVICE-side port
  final String path;   // '/<token>=/' (may be empty)
}

/// Pure: extract VM-service URIs from raw logcat text, in first→last order
/// (caller takes .last for the newest).
List<DeviceVmServiceUri> parseLogcatVmServiceUris(String logcat);

/// Scans + forwards, using the injected [AdbRunner].
final class AndroidVmServiceDiscovery {
  const AndroidVmServiceDiscovery(this._adb);
  /// `adb [-s serial] logcat -d` → parse → return all found (first→last).
  Future<List<DeviceVmServiceUri>> scan({String? serial});
  /// `adb [-s serial] forward tcp:0 tcp:<devicePort>` → the assigned host port
  /// (adb prints it on stdout). Returns the host port.
  Future<int> forward(int devicePort, {String? serial});
  /// Convenience: scan → take the newest → forward → build the connect URI
  /// `ws://127.0.0.1:<hostPort>/<token>=/ws`. Null if nothing found.
  Future<String?> discoverWsUri({String? serial});
}
```
- `parseLogcatVmServiceUris`: for each line, apply the Flutter regex (and the Observatory fallback); parse the matched URL with `Uri.parse` → host/port/path. Skip unparseable. Keep order.
- `scan`: `_adb.run(['logcat', '-d'], serial: serial)` → `parseLogcatVmServiceUris(result.stdout)`.
- `forward`: `_adb.run(['forward', 'tcp:0', 'tcp:$devicePort'], serial: serial)` → `int.parse(result.stdout.trim())` (adb prints the chosen local port). Throw a clear error on non-numeric/failed output.
- `discoverWsUri`: `final uris = await scan(serial: serial); if (uris.isEmpty) return null; final u = uris.last; final hostPort = await forward(u.port, serial: serial); final path = u.path.endsWith('/') ? u.path : '${u.path}/'; return 'ws://127.0.0.1:$hostPort${path}ws';` (ensure exactly one `ws` suffix; if path already ends with `/ws` or `/ws/`, normalize to end with `/ws`).

- [ ] **Step 1: failing tests** (pure parse + fake AdbRunner):
  - `parseLogcatVmServiceUris` on a sample containing `... flutter : The Dart VM service is listening on http://127.0.0.1:43219/GJur1BL3JL4=/` → one uri host 127.0.0.1 port 43219 path `/GJur1BL3JL4=/`; a sample with two lines → both, in order; the Observatory variant parsed; noise-only → empty.
  - `scan` with a fake `AdbRunner` returning canned logcat → the parsed uris; passes `serial` through to the runner.
  - `forward` with a fake runner returning `'54321\n'` → 54321; passes `['forward','tcp:0','tcp:43219']`.
  - `discoverWsUri` → `ws://127.0.0.1:54321/GJur1BL3JL4=/ws` (uses newest, forwards, correct ws suffix); empty scan → null.
- [ ] **Step 2-4:** run→fail, implement, run→pass; `dart analyze` clean; `dart format` 0 changed.
- [ ] **Step 5: commit** `feat(radar_native_host): AndroidVmServiceDiscovery (scan adb logcat + forward for a ws:// URI)`.

---

### Task 2: "Scan device" button in the Connect bar (radar_desktop)

**Files:** Modify `lib/src/shell/connect_bar.dart` (add the button + wire a discovery callback); Modify `lib/src/shell/desktop_shell.dart` (construct `AndroidVmServiceDiscovery` with the resolved adb + pass the selected device serial + an `onScan` that fills the field); tests.

- **ConnectBar:** in the disconnected state, next to the ws:// `TextField` + Connect button, add a small **"Scan device"** icon/text button (only when a scan callback is provided). On tap: call the injected `Future<String?> Function()? onScanDevice`; while running show a tiny spinner; on a non-null result, set the URI field's text to it (do NOT auto-connect — the user reviews + taps Connect); on null/error, show an inline note ("No running debug app found on device — is it a debug/profile build?"). Keep it optional: when `onScanDevice` is null, the button is absent (existing tests unaffected).
- **Shell:** build `AndroidVmServiceDiscovery(LazyAdbRunner(() => _tools.resolvedPath(ExternalTool.adb)))` (reuse the resolved-adb seam); pass `onScanDevice: () => discovery.discoverWsUri(serial: <selected serial or null>)`. For the serial: use the capture screen's selected device if available, else null (adb picks the only device); simplest for v1 — pass null (adb uses the single connected device) OR the first ready device from `_android.devices`. Guard: only wire `onScanDevice` when `_tools`/adb is present (`canCapture`-style); otherwise leave it null (button hidden).
- The ConnectBar takes the URI text controller it already owns — set `uriController.text = result` (place the caret at end).

- [ ] **Step 1: failing tests:** ConnectBar with a fake `onScanDevice` returning a URI → tapping "Scan device" fills the field with it (assert the TextField's text); returning null → the "no app found" note; no `onScanDevice` → no button (avoid `containsSemantics`; find by icon/text). Keep existing ConnectBar tests green.
- [ ] **Step 2-4:** tests → implement → `flutter analyze` + `flutter test` green → `dart format` 0 changed → `git checkout -- macos`.
- [ ] **Step 5: commit** `feat(radar_desktop): Scan-device button fills the Connect field from adb logcat`.

---

### Task 3: verify + wire-through
- [ ] `flutter analyze`/`dart analyze` clean; suites green; `flutter build macos --debug` OK; format clean repo-wide.
- [ ] **Manual (documented):** with the device connected, run any Flutter debug/profile app on it (`flutter run -d <device>` or a debug APK), tap **Scan device** in Radar Desktop → the field fills with a `ws://…/ws` URI → Connect unlocks the live tabs. Record the observed result in the commit body.
- [ ] commit `chore(radar_desktop): logcat VM-service scan verified on device`.

## Self-review notes
- Simple + optional: one button, fills the field, manual connect, newest match. ✓
- Reuse: AdbRunner + resolved-adb seam; no new adb code. ✓
- Honest: no-device / no-app / adb-fail all surface a clear note, never crash; never blocks manual paste. ✓
- Out of scope: auto-polling/streaming logcat, multi-endpoint picker, iOS, non-debug builds (no VM service).
