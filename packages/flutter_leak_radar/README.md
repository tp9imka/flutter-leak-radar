# flutter_leak_radar

[![pub.dev](https://img.shields.io/pub/v/flutter_leak_radar.svg)](https://pub.dev/packages/flutter_leak_radar)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

On-device memory leak detector for Flutter. Tracks per-class heap growth using
VM service snapshots and catches precise object retention through `WeakReference`
and `Finalizer`. Works in debug and profile builds. Complete no-op in release —
`enabled` defaults to `kDebugMode || kProfileMode`, so no guard code or build
flavours are required.

---

## Installation

```yaml
dependencies:
  flutter_leak_radar: ^0.2.0
```

---

## Quick start

### 1. Initialise in `main()`

```dart
import 'package:flutter_leak_radar/flutter_leak_radar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LeakRadar.init(LeakRadarConfig.standard(
    autoScan: AutoScan(onNavigation: true),  // scan after every pop
  ));
  runApp(const MyApp());
}
```

`LeakRadarConfig.standard()` enables the detector in debug and profile, and
watches the default suspect set (`*State`, `*Bloc`, `*Controller`, etc.).

### 2. Wire the navigator observer

```dart
MaterialApp(
  navigatorObservers: [LeakRadar.navigatorObserver],
  home: ...,
)
```

This triggers an automatic scan a short time after each navigation pop.

### 3. Add the overlay badge

```dart
home: LeakRadar.overlay(child: const HomeScreen()),
```

The draggable badge shows the current worst severity and finding count. Tap to
open `LeakRadarScreen`. Long-press to trigger a manual scan immediately.

### 4. Open the results screen from anywhere

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const LeakRadarScreen()),
);
```

---

## Manual tracking

For types not covered by the default suspect set, opt in explicitly:

```dart
class MyService {
  MyService() {
    LeakRadar.track(this, tag: 'MyService');
  }

  void dispose() {
    LeakRadar.markDisposed(this);
  }
}
```

`track` registers the object with a `WeakReference`/`Finalizer` pair.
`markDisposed` tells the engine the object was intentionally released, suppressing
false positives.

---

## Export and share

```dart
// Write a Markdown report to a temp file and get the path
final path = await LeakRadar.exportToFile(format: LeakExportFormat.markdown);

// Or export JSON
final jsonPath = await LeakRadar.exportToFile(format: LeakExportFormat.json);
```

`LeakRadarScreen` has built-in Export and Share buttons that call these APIs.

---

## Configuration reference

| Field | Type | Default | Description |
|---|---|---|---|
| `enabled` | `bool` | `kDebugMode \|\| kProfileMode` | Master switch. No-op when false. |
| `autoScan` | `AutoScan` | `AutoScan()` | Periodic and/or navigation-triggered scan schedule. |
| `suspects` | `SuspectSet` | `SuspectSet.defaults()` | Which class-name patterns to track. |
| `rules` | `List<LeakRule>` | `[]` | Extra rules layered on top of suspects. |
| `maxSnapshots` | `int` | `20` | Rolling history depth for growth analysis. |
| `gcCyclesForPreciseLeak` | `int` | `3` | GC cycles before a tracked object is flagged as not-GCed. |
| `disposalGrace` | `Duration` | `2s` | Time after `markDisposed` before the object must be GCed. |
| `maxRetainingPathRequests` | `int` | `5` | Max retaining-path fetches per scan (caps VM-service overhead). |
| `logLevel` | `LeakLogLevel` | `warning` | Internal log verbosity. |
| `showOverlay` | `bool` | `true` | Whether `LeakRadar.overlay()` renders the badge. |

### AutoScan

```dart
AutoScan(
  onNavigation: true,                         // scan on every didPop
  period: const Duration(minutes: 2),         // also scan periodically
  navigationDebounce: const Duration(milliseconds: 500),
)
```

### LeakRule glob patterns

```dart
LeakRule.growth('*Bloc')          // flag any class ending in Bloc
LeakRule.maxLive('*Cache', 3)     // flag if more than 3 Cache instances live
LeakRule.ignore('*Mock*')         // never flag classes containing Mock
```

Glob: `*X` = ends with X, `X*` = starts with X, `*X*` = contains X,
`X` = exact match.

---

## Manual heap snapshot

Capture a full binary heap snapshot at any point during a debug or profile run:

```dart
final path = await LeakRadar.captureHeapSnapshotToFile();
if (path != null) {
  print('Heap snapshot written to: $path');
}
```

The file is named `leak_radar_heap_<timestamp>.data` and is written to
`Directory.systemTemp` by default. Pass a `directory` argument to write
elsewhere:

```dart
final dir = Directory('/path/to/output');
final path = await LeakRadar.captureHeapSnapshotToFile(directory: dir);
```

The `.data` file is a `dartheap` binary snapshot that can be loaded into:

- **Flutter DevTools** — open the Memory tab, click *Import*, and select the
  file to inspect the object graph interactively.

No VM-service connection is required — the snapshot is written directly via
`dart:developer`'s `NativeRuntime.writeHeapSnapshotToFile`. The method returns
`null` (never throws) when the platform does not support it (release builds,
web, non-standalone VM).

`LeakRadarScreen` also exposes a **Collect heap snapshot** button (memory chip
icon) in its app bar that writes the snapshot and offers a Share sheet to send
the file directly from the device.

### On-device limitations (heap-growth & graph scans)

Precise tracking (`notGced` / `notDisposed`) is pure Dart — it relies only on
`WeakReference` and `Finalizer`, so it works everywhere on-device, including a
plain `flutter run` on a physical Android or iOS device.

Heap-growth analysis and the retaining-path graph scan need a **heap source**,
which is one of:

- a reachable **in-process VM service** — available on desktop and on
  emulators/simulators; or
- **`NativeRuntime.writeHeapSnapshotToFile`** — *not* supported on a physical
  Android/iOS app's embedded VM.

On a plain `flutter run` on a physical device neither is available, so only
precise findings appear there. To exercise all detectors, run the example on
**macOS or an emulator** (`flutter run -d macos`) and tap **"Run leak
self-test"** on the home screen — it drives the leak scenario in the live app
and prints a `LEAK-RADAR-SUMMARY` block (grouped by `LeakKind`, including empty
kinds) to the console. The self-test is plain app code — no `integration_test`
package and no `androidx.test` native dependency — so it also runs on a
physical device (showing precise findings, with verbose logs explaining why the
graph/growth paths are unavailable there).

For offline analysis, feed an exported `.data` snapshot to the `leak_graph` CLI.

---

## Debug/profile-only guarantee

The engine starts only when `kDebugMode || kProfileMode` is true (via
`LeakRadarConfig.standard`). In release builds every call (`init`, `scan`,
`track`, `markDisposed`, `overlay`, `navigatorObserver`) is a synchronous no-op
that returns a safe default. Nothing is compiled out — no tree-shaking or build
configuration required.

---

## Relation to Flutter DevTools and leak_tracker

`flutter_leak_radar` is complementary to the official tooling:

- **Flutter DevTools memory panel** — great for interactive inspection; requires
  a connected DevTools session. LeakRadar works in the field with no tooling
  attached and can share reports as files.
- **leak_tracker** — precise lifecycle enforcement for unit tests and debug
  widgets. LeakRadar adds heap-growth analysis, a visual overlay, and is
  designed for integration testing and staging dogfooding rather than CI.

---

## Static analysis companion

Add [`flutter_leak_radar_lint`](https://pub.dev/packages/flutter_leak_radar_lint) to catch
undisposed controllers, uncancelled subscriptions, and similar patterns at
edit time before they cause runtime leaks.

---

## License

MIT — see [LICENSE](LICENSE).
