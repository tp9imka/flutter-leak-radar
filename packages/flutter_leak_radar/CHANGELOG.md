## 0.1.1

- **Fix: precise `notGced` leaks are now actually detected.** Each scan now
  forces a real GC (`forceGc()`) before reading the precise tracker's
  reachability barrier. Previously the barrier never advanced (a VM-service GC
  does not move `developer.reachabilityBarrier`), so disposed-but-retained
  tracked objects were never reported.
- **Fix: `GraphScan` config is now honoured.** `LeakRadar.init` built the engine
  without forwarding the config, so `graphScan` (and `reportThreshold` /
  `preciseTracking`) silently fell back to defaults — the live graph scan never
  ran.
- `LeakRadar.forceGcAndScan()` + a "Force GC & rescan" action in the inspector
  overflow menu: force a GC and rescan on demand to surface precise leaks
  immediately.
- VM-service connect failures are logged once as a warning (not on every retry).
  The detector degrades cleanly to precise + file-snapshot graph scanning when
  the VM service is unreachable in-process (common on physical devices).
- **Verbose diagnostics:** with `logLevel: LeakLogLevel.verbose`, each scan now
  logs why it produced N findings — engine status, capture result, `forceGc` +
  `collectLeaks` counts, the graph-scan acquire path (live / file-fallback /
  null) and analyzer stats. Makes silent "no findings" observable.
- **Example self-test:** the example's home screen has a "Run leak self-test"
  button (`example/lib/leak_self_test.dart`) that drives the leak scenario in
  the live app and prints a `LEAK-RADAR-SUMMARY` block — no `integration_test`
  dependency, so it runs on any target including a physical device.

## 0.1.0

- **Live retaining-path detector** (`GraphScan`): loads a VM heap snapshot after
  every Nth navigation and walks the retaining path of each tracked object.
  Objects reachable only from non-live roots are reported as
  `LeakKind.retainedByNonLiveRoot` findings.
- `LeakRadar.graphScanNow()`: triggers an on-demand retaining-path scan outside
  the automatic schedule.
- `LeakRadarConfig.standard(graphScan: ...)`: wire `GraphScan(everyNthNavigation: n)`
  to enable the live graph detector in the existing config API.
- `leak_graph` dependency promoted from a path reference to a version constraint
  (`^0.1.0`); `leak_graph` is a pub workspace sibling, so the workspace resolver
  maps it to the local copy — no path dep, publish-ready.

## 0.0.2

- `forceGc({int fullGcCycles, Duration? timeout})` test utility: drives GC by
  allocating until `reachabilityBarrier` advances, ported from `leak_tracker`
  (`lib/src/precise/force_gc.dart`).
- `Finalizer`-based `notDisposed` detection: `LeakObjectRegistry` now attaches
  a `Finalizer<_Entry>` to each tracked object; objects GC'd without
  `markDisposed()` are reported as `LeakKind.notDisposed` findings.
- `LeakFinding.allocationStack` (`StackTrace?`): optionally captures the
  `StackTrace.current` at `track()` call sites when
  `LeakObjectRegistry(captureAllocationStack: true)` is used; surfaced in
  the `FindingDetailScreen` "Allocation Site" card.

## 0.0.1

Initial release.

- `LeakRadar` static facade: `init`, `scan`, `track`, `markDisposed`, `reports`
  stream, `latest`, `status`, `navigatorObserver`, `overlay`, `exportToFile`,
  `dispose`.
- `LeakRadarConfig.standard()` — enables in debug/profile, no-op in release,
  uses curated default suspect set.
- Heap-growth detection via VM service snapshots with configurable rolling
  history (`maxSnapshots`).
- Precise object tracking via `WeakReference` + `Finalizer` with configurable
  GC-cycle threshold and disposal grace period.
- `AutoScan` — optional periodic and/or post-navigation scanning.
- `SuspectSet.defaults()` — covers `*State`, `*Screen`, `*Bloc`, `*Cubit`,
  `*Controller`, `*Notifier`, `*StreamSubscription`, `*StreamController`,
  `Timer`.
- `LeakRule` factories: `growth`, `maxLive`, `ignore` with glob matching.
- `LeakRadarOverlay` — draggable floating badge with severity colour coding.
- `LeakRadarScreen` — findings list, manual scan button, export (JSON/Markdown)
  and share actions.
- `LeakRadarNavigatorObserver` — debounced scan-on-pop.
- All public calls are swallowed on error and never throw into the host app.
