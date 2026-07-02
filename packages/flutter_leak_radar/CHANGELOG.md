## 0.2.1

In-app overlay UX polish (no public API change) plus a refreshed bundled
DevTools extension.

- The VM-degradation banner is now dismissible per incident and re-appears on a
  status change or reconnect.
- Sort and kind-filter controls collapse behind a compact "filters" disclosure
  by default, giving the leak list more vertical space.
- Material ink ripples and haptics on the Force GC / Scan / Clear actions and
  the sort/filter controls.
- The finding-detail retaining path loads on demand instead of on open,
  removing an open-time freeze on findings without a carried path.
- Bundled DevTools (Leak Radar) extension refreshed: its Memory companion now
  survives DevTools tab switches (session persisted via the Dart Tooling
  Daemon, degrading to in-memory when unavailable), a single snapshot can be
  shown against an empty baseline ("show everything"), and a class's instances
  are broken down across their distinct shortest retaining paths.

## 0.2.0

Redesigned the in-app Leaks inspector on the shared `radar_ui` design system
(new dependency). The public API (`LeakRadar`, `LeakRadarScreen`, and the
`LeakRadarView` embed contract) is unchanged.

- Dense two-line findings rows: severity bar, class name, growth delta, a
  sparkline over recent scans, and a leak-kind tag.
- A live **VM-connection status chip** with an honest degraded-fallback banner —
  it shows the reason and that it fell back to an on-device heap snapshot,
  rather than hiding why data is degraded.
- Search, sort (severity / growth / live count / name), and kind quick-filters.
- Rebuilt leak-detail view: a growth-series chart and the retaining-path tree
  (source locations rendered only where the data provides them — no fabrication).
- Scrollable lists respect the bottom safe-area inset.
- Export/share now uses the portable static `Share.shareXFiles` API and the
  `share_plus` constraint is widened to `>=10.0.0 <14.0.0`, so consumers pinned
  to share_plus 10.x–13.x can use the package. [PR#88]
- Refreshed the bundled DevTools extension build to match the
  `flutter_leak_radar_devtools` Memory-companion redesign. [PR#87]

## 0.1.1

Makes the detector fully functional on a **physical device with no VM-service
connection**, and overhauls retaining-path (graph) analysis to work on
real-world heaps.

### On-device — no VM service required

- **Standalone heap-growth.** Per-class growth is derived from the NativeRuntime
  heap snapshot the graph scan already captures, so growth works on a physical
  device without a `getAllocationProfile` (VM-service) call — which the app
  cannot reliably self-connect to. When the VM service *is* connected, the
  per-scan profile still feeds growth too.
- **Standalone retaining paths.** Growth/precise findings now get a retaining
  path by BFS-walking an on-device snapshot — no `getRetainingPath` VM call.
  Graph findings render the path they already carry.
- **VM-service connection state + manual reconnect** in the dashboard: a chip
  shows whether the per-scan profile is live; tap to reconnect.
  (`LeakRadar.vmServiceConnected`, `LeakRadar.reconnectVmService()`.)

### Retaining-path (graph) analysis — now works on real heaps

- **Correct GC-root seeding.** BFS starts from the real GC root, not the parser
  sentinel (which yielded `reachable=0`, so `retainedByNonLiveRoot` never fired
  on a real snapshot).
- **Off the UI thread.** Parse + BFS + clustering run in a background isolate
  (a ~400k-node heap had been ANR-ing the main isolate); analysis dropped from
  ~127s to ~1s via node/field-map caching and reconstructing paths only for
  leak candidates.
- **Leak attribution.** A leak is reported under the **deepest app-owned object**
  on its retaining path (e.g. `_LeakyScreenState`), not the internal SDK leaf
  (`_ControllerSubscription`/`_Closure`); the SDK chain becomes the path detail.
- **No more OOM.** The graph scan is gated on heap size *before* writing the
  snapshot, with a min-interval cooldown and a file-size backstop, so a bloated
  heap is skipped cleanly instead of getting the app SIGKILLed.
- **Accurate counts.** A GC runs immediately before every snapshot, so per-class
  counts reflect live objects, not transient garbage awaiting collection.

### Noise & UX

- **App-relevance growth filter.** The broad default `*State`/`*Screen` globs
  only flag app-owned classes (drops framework `_FocusState`/`AnimationController`
  churn); resource globs (`*Controller`/`*Timer`/`*Stream*`/`*Notifier`) still
  flag platform-type leaks wherever declared. Fails open on unknown library.
- **Stable overlay badge** — counts only high-confidence findings (precise +
  graph-confirmed + critical), so it no longer oscillates with growth churn.
- **Dashboard summary row reworked:** severity tallies that wrap as the numbers
  grow, a VM chip + a Force-GC pill, and class/instance totals + scan time shown
  once in the bottom bar. `forceGcAndScan` re-runs the graph scan so the GC pill
  refreshes growth; the screen updates live from the report stream.
- Diagnostics route through `debugPrint`, so verbose logs reach `adb logcat`.

### Precise detection & config (also in this line)

- **Fix: precise `notGced` leaks are now actually detected** — each scan forces
  a real GC before reading the reachability barrier (a VM-service GC does not
  move `developer.reachabilityBarrier`).
- **Fix: `GraphScan` config is now honoured** — `LeakRadar.init` was not
  forwarding the config, so `graphScan`/`reportThreshold`/`preciseTracking`
  silently fell back to defaults.
- VM-service connect failures are logged once; the detector degrades cleanly to
  precise + file-snapshot scanning when the service is unreachable in-process.
- **Verbose diagnostics** (`LeakLogLevel.verbose`): each scan logs why it
  produced N findings.
- **Example self-test:** a "Run leak self-test" button drives the leak scenario
  and prints a `LEAK-RADAR-SUMMARY` block (no `integration_test` dependency, so
  it runs on any physical device).

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
