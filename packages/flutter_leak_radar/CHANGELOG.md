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
