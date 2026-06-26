# flutter-leak-radar — Companion (DevTools Extension) Design Proposal

> Status: **Proposal / brainstorm** (resumes the parked "Section 1" thread).
> Scope: a host-side **Flutter DevTools extension** that gives reliable VM-service-backed
> heap and leak analysis, complementing — not replacing — the on-device runtime detector.
> This document is a proposal, not an implementation plan. Open questions in §6 should be
> answered before any code is written.

---

## 1. Problem & Motivation

### 1.1 The wall the runtime detector keeps hitting

The runtime package (`flutter_leak_radar`) wants to do real heap work on-device:
`getAllocationProfile` for per-class histograms, `getRetainingPath` for "what holds this
leak alive", `HeapSnapshotGraph` for full object-graph analysis, and allocation tracing for
"where was this allocated". All of these require a **working connection to the target app's
VM service**. The package tries to make that connection *from inside the app itself*
(`vm_heap_probe.dart`), and that self-connection is the project's documented #1 pain point:

- On a **tethered physical device**, the host's DDS (Dart Development Service) claims the
  single VM-service connection first. The app's own `vmServiceConnectUri(...)` is then
  refused. This is not a flutter-leak-radar bug — the shipped `leak_detector` package
  (Jiakuo Liu) independently arrived at the same `Service.getInfo()` → `convertToWebSocketUrl()`
  → `vmServiceConnectUri()` sequence, hit the same DDS-refusal wall, and its README only offers
  *operational* workarounds (`--disable-dds` / `--no-dds`, or detach the device). There is no
  in-app code fix while DDS is attached.
- `Service.getInfo().serverUri` is frequently **null on profile/physical builds** (the URI was
  never published to the isolate), so the probe silently returns nothing.

Because of this, the runtime detector's most powerful modes (allocation profile, retaining
paths, snapshot graph) are unreliable exactly where they matter most — on real hardware — and
it falls back to `NativeRuntime.writeHeapSnapshotToFile` (no VM service needed, but no live
histograms, no on-demand retaining paths, no allocation tracing).

### 1.2 Why a DevTools extension is the right shape

The thing that *does* reliably hold a VM-service connection to the target app is **DevTools
itself**. When a developer runs `flutter run` / attaches DevTools, the tooling is already on the
host side of DDS — it is the consumer DDS was built to serve. A Flutter DevTools **extension**
(`package:devtools_extensions`) inherits that existing, authenticated connection for free via
`serviceManager`. It does not race the app for the socket; it sits on the side that already won.

This inverts the problem instead of fighting it:

| | In-app runtime probe | Host-side DevTools extension |
|---|---|---|
| Who owns the VM-service socket | The app, *after* DDS already took it (loses) | DevTools, *which DDS serves* (wins) |
| `serverUri` null on device | Common, silent failure | N/A — connection handed to us |
| Coexists with attached DDS | No | Yes (that's the point) |
| Release builds | Must no-op | N/A (dev-time tool, never ships) |

A DevTools extension is also the **ergonomically correct home** for the heavy, interactive,
chart-driven analysis the in-app dashboard can't reasonably host: it has screen real estate, it
runs on the dev machine (no jank budget on the device), and it ships *with the package* (drop
`flutter_leak_radar` into a project and the extension auto-appears in DevTools — no separate
install). The repo currently has only the **auto-generated** `.dart_tool/extension_discovery/
devtools.json` files (root and `example/`); there is no `extension/devtools/config.yaml` or web
build yet — so the discovery mechanism is understood, but the extension itself is unbuilt.

### 1.3 What this is explicitly NOT

Not a replacement for the on-device detector. The runtime package's value — zero-config,
always-on, works with *no* host attached (NativeRuntime snapshots), precise WeakReference +
Finalizer tracking — is real and stays. The companion is the **deep-dive station** you open
when the on-device detector (or your own suspicion) says "something's leaking; show me why."
See §5.

---

## 2. Architecture

### 2.1 Shape

```
flutter-leak-radar (melos workspace)
├── packages/
│   ├── flutter_leak_radar          (runtime — on-device, unchanged)
│   ├── flutter_leak_radar_lint     (custom_lint — unchanged)
│   ├── leak_graph                  (pure-Dart analyzer — REUSED as-is, see §4)
│   └── flutter_leak_radar_devtools (NEW — the companion extension)
│         ├── lib/                  ← Flutter web app (the extension UI)
│         └── extension/devtools/   ← config.yaml + prebuilt web build
```

`flutter_leak_radar_devtools` is a Flutter package whose UI is a Flutter **web** app built into
`extension/devtools/build/`, declared by `extension/devtools/config.yaml`. The runtime package
references it so DevTools auto-discovers the extension whenever `flutter_leak_radar` is a project
dependency. (Either the runtime package gains an `extension/` pointer, or — cleaner — we add the
extension as a dependency the runtime re-exports for discovery. Decide in §6 Q7.)

### 2.2 Connecting to the target VM service

The extension does **not** connect by URI. `package:devtools_extensions` hands it the live,
DDS-served connection that DevTools already holds:

```dart
// Inside the extension (conceptual):
import 'package:devtools_app_shared/service.dart';
import 'package:devtools_extensions/devtools_extensions.dart';

// serviceManager is wired up by DevToolsExtension at root.
final vmService = serviceManager.service;            // VmService — already connected
final isolateRef = serviceManager.isolateManager.mainIsolate.value;
```

This is the crux: **the connection problem disappears** because we are no longer the one making
it. We get a `VmService` instance that is already past DDS, already authenticated, already
pointed at the right isolate — the precise thing the in-app probe cannot get on a tethered
device.

### 2.3 VM-service APIs this unlocks (that the in-app path cannot reliably get)

With a dependable `VmService` + `isolateId`, the following all become first-class, on-demand,
host-side operations — none of which the in-app probe can be trusted to perform on a physical
device:

- **`getAllocationProfile(isolateId, gc: bool)`** — per-class instance counts and bytes,
  optionally after a forced full GC. Source of the **live class histogram** and the basis for
  heap-growth trends. (Note: force-GC on the *host* side does not jank the device's frame budget
  the way an in-app `gc: true` on every route pop does — a known runtime trade-off.)
- **`getRetainingPath(isolateId, targetId, limit)`** — the real "what is keeping this object
  alive" chain for a *specific, currently-live* instance picked in the UI. The in-app path can
  call this in theory but only with a live connection it rarely has; here it's reliable and
  **interactive** (click a class → pick an instance → fetch its path).
- **`getInstances` / `getInstancesAsList`** — enumerate live instances of a chosen class so the
  user can drill from "200 `MyController`s alive" into individual objects and their retaining
  paths.
- **`HeapSnapshotGraph` (via the snapshot stream / `requestHeapSnapshot`)** — a full
  point-in-time object graph for offline BFS analysis. This is the input `leak_graph` already
  consumes (§4). The extension can capture snapshots on demand from the host, with no device
  storage or share-sheet dance.
- **CPU/allocation tracing** — `setTraceClassAllocation(isolateId, classId, enable: true)` plus
  the allocation-stack data exposed through the profiler, to answer **"where was this object
  allocated"** (the allocation site / stack), which the in-app detector has no practical way to
  surface.
- **`getObject` / `Script` resolution** — for the source-location enrichment pattern proven by
  `leak_detector` (resolve declaring field → `Script` → `getLineNumberFromTokenPos` + source
  substring) to decorate retaining-path nodes with `file:line:col` and the actual line of code.

### 2.4 Threading / where analysis runs

Heavy graph analysis (BFS retaining paths over a full snapshot) runs **in the extension's own
Dart isolate on the host machine** — not on the device, not blocking the DevTools UI thread.
`leak_graph` is pure Dart and already designed to run under `compute()`/isolates, so the
companion offloads analysis off the UI isolate the same way the CLI does. The device is only
ever asked for raw data (profile, snapshot bytes, a retaining path), never to compute.

---

## 3. Feature Set — what the companion shows that the in-app dashboard cannot

The on-device `LeakRadarScreen` is constrained: tiny screen, frame budget, no reliable VM
service, qualitative per-leak view. The companion lifts every one of those constraints.

1. **Live class histogram (heap census).** A sortable, filterable table of every class with live
   instance count + retained/shallow bytes, refreshed on demand via `getAllocationProfile`. Sort
   by count, by bytes, by growth-since-last-refresh. App-owned classes (via `leak_graph`'s
   `app_package_set`) highlighted; framework noise dimmed. The in-app dashboard can show
   heap-growth *for tracked classes only*; this shows the **whole heap**.

2. **On-demand real retaining paths.** Pick a class → list live instances → pick one → fetch its
   *actual* `getRetainingPath`, rendered as the retaining chain with `leak_graph` root
   classification and (via §2.3) `file:line:col` + source-line decoration per node. Interactive
   and live, versus the in-app detector's after-the-fact, snapshot-only paths.

3. **Allocation-site tracing.** Toggle allocation tracing on a suspect class, exercise the app,
   then see **where instances are being allocated** (allocation stacks). Answers "who is creating
   all these?" — a question the in-app detector structurally cannot answer.

4. **Leak diffing across snapshots.** Capture snapshot A (baseline), perform a repeatable user
   action N times, capture snapshot B, and **diff**: which classes grew, by how many, and which
   specific new objects survived that shouldn't have. This "navigate-in-and-back-out, watch the
   delta" workflow is the single most effective manual leak-hunting technique, and it requires
   exactly the reliable host-side capture the companion provides. Output is a ranked
   "grew-and-retained" list, each row drillable into its retaining path.

5. **Snapshot import / inspection.** Load a `.data` heap snapshot captured on-device via
   `NativeRuntime.writeHeapSnapshotToFile` (the runtime's offline fallback) and run the *same*
   `leak_graph` analysis on the host — so even leaks found with no live connection get the full
   retaining-path + clustering treatment in the companion. This is the bridge that makes the
   on-device fallback and the host tool one continuous workflow.

6. **Clustered findings view.** Reuse `leak_graph`'s clustering (`GraphLeakCluster`) so instead
   of 200 near-identical retaining paths, the user sees "these 200 `MyController`s are all
   retained by the same `StreamSubscription` pattern" — one root cause, one fix.

---

## 4. Reuse of `leak_graph`

`leak_graph` was built pure-Dart precisely so it can run **anywhere there's a Dart VM** — CLI,
isolate, and (the payoff) a DevTools extension. Confirmed by its pubspec: dependencies are only
`args`, `meta`, and `vm_service` — **no Flutter, no platform plugins**. The companion is a
Flutter app, but the *analysis core it calls* is platform-agnostic Dart.

Reuse boundaries (what the companion calls, unchanged):

- **`heapGraphFromBytes(Uint8List)`** (`snapshot_loader.dart`) — parse a captured snapshot's raw
  bytes into a `HeapGraphView`. The companion gets bytes either from a host-side
  `requestHeapSnapshot` over the live connection *or* from an imported on-device `.data` file —
  both feed the identical entry point. Note the loader already exposes a bytes-based path
  (`heapGraphFromBytes`) separate from the `dart:io` file path (`loadHeapGraph`), so the
  extension can avoid `dart:io` entirely and consume bytes straight off the VM service.
- **`VmSnapshotGraphView`** (`vm_snapshot_adapter.dart`) — wraps `package:vm_service`'s
  `HeapSnapshotGraph` into `leak_graph`'s `HeapGraphView` abstraction.
- **`GraphLeakAnalyzer.analyze(...)`** + `GraphAnalysisOptions` — BFS shortest retaining paths,
  root classification, app-owner attribution, clustering → `GraphAnalysisResult`. The companion's
  retaining-path, diff, and clustered-findings views all render from this result.
- **`app_package_set` / `root_classifier` / `shortest_retaining_paths` / `clustering`** —
  consumed transitively through the analyzer; also usable directly for the histogram's
  app-vs-framework highlighting.
- **`report_renderer`** (`cli/`) — the text renderer can seed an "export/copy as text" affordance
  in the companion so a finding can be pasted into an issue verbatim.

What is **not** reused: the runtime's `vm_heap_probe.dart` self-connect logic — the companion
deliberately does not self-connect; it uses `serviceManager`. The runtime's probe stays as the
on-device fallback.

Net: `leak_graph` is the shared brain. The runtime, the CLI, and the companion are three
**frontends** to the same analyzer — the companion is just the one with a reliable connection and
a real screen.

---

## 5. Relationship to the in-app detector (complementary, not replacement)

Two surfaces, one engine, deliberately different jobs:

| | In-app runtime (`flutter_leak_radar`) | Companion (DevTools extension) |
|---|---|---|
| When it runs | Always, in every debug/profile session, **no host needed** | When DevTools is open and a dev is investigating |
| Connection | Self-connect (fragile on device) or NativeRuntime snapshot (no connection) | DDS-served `serviceManager` (reliable) |
| Strengths | Zero-config, always-on, precise WeakRef+Finalizer tracking, draggable in-app badge, works offline | Whole-heap histogram, live retaining paths, allocation tracing, snapshot diffing, big screen, no device jank |
| Weaknesses | Can't reliably do live histograms/paths on device; small screen | Needs DevTools attached; not present in CI / unattended runs |
| Analysis core | `leak_graph` | `leak_graph` (same) |

The intended loop: the **in-app detector is the smoke alarm** — it's always on and tells you
*that* something leaked (and, where it can, captures a snapshot). The **companion is the
investigation room** — you open it to find out *why*, with reliable host-side tooling. They share
findings: an on-device snapshot (or a detected-leak's instance) becomes the starting point for a
companion deep-dive. Neither obsoletes the other; removing either leaves a real gap (always-on
coverage vs. deep interactive analysis).

A nice handoff to design (§6 Q5): when both are present, the in-app detector could surface "open
in DevTools companion" affordances, and the companion could read the runtime's posted events via
`postEvent`/the service-extension stream to pre-populate suspects.

---

## 6. Open Design Questions (answer before building)

1. **DevTools extension maturity / API stability.** `package:devtools_extensions` and the
   `serviceManager` surface have evolved fast. Before committing, pin a target DevTools/Flutter
   SDK version and confirm the exact `serviceManager.service` / `isolateManager` API for that
   version. **Q: which Flutter/DevTools version do we target as the floor?**

2. **Snapshot capture over the live connection.** Confirm the supported way to pull a full
   `HeapSnapshotGraph` from the host side in the target SDK (heap-snapshot stream vs. a
   request RPC) and its size/perf behavior on a large app. **Q: is on-demand host-side snapshot
   capture acceptable latency-wise on a real app, or do we lean on imported on-device `.data`
   files first?**

3. **Allocation tracing scope.** `setTraceClassAllocation` is per-class and has overhead. **Q: do
   we want allocation-site tracing in v1, or defer it to a later phase and ship histogram +
   retaining paths + diffing first?**

4. **Diffing is the headline feature — confirm priority.** Snapshot diffing (feature §3.4) is
   arguably the most valuable single capability. **Q: should the whole v1 be organized around the
   capture-A → act → capture-B → diff workflow, with the histogram/paths as supporting views?**

5. **Runtime ↔ companion handshake.** Do we want the in-app detector and the companion to talk
   (shared events via `postEvent`/service extension, "open in companion" links)? **Q: is the
   handshake in scope for v1, or do both ship independently first and integrate later?**

6. **`leak_graph` API surface adequacy.** Does the current analyzer expose everything the
   interactive UI needs (e.g. analyze a *single* picked instance's path vs. a full snapshot;
   incremental/streaming results for a huge graph)? **Q: are any additions to `leak_graph`'s
   public API needed, and do they risk coupling it to the extension (it must stay Flutter-free)?**

7. **Discovery wiring & publishing.** **Q: does the extension live as its own pub package
   referenced by the runtime for auto-discovery, or bundled under the runtime's `extension/`
   directory? How do we ship the prebuilt web build (committed vs. CI-built) given pub size
   limits?**

8. **On-device validation prerequisite.** The followups note the runtime VM-service path is still
   unvalidated on a real `--profile` device. The companion sidesteps *self*-connect, but we still
   need to confirm the host-side `getAllocationProfile`/`getRetainingPath`/snapshot path returns
   real data on a physical device. **Q: do we gate companion work behind a one-session on-device
   spike that proves the host-side APIs return real data?**

9. **Scope boundary with goal (c), the tracer.** This proposal is leak/heap only. The broader
   roadmap wants a performance/stability **tracer** framework. **Q: should the companion be
   architected from day one as a multi-tab "leak-radar + tracer" host, or strictly a leak/heap
   tool we later sit the tracer beside?**

---

## 7. Rough Phase Breakdown (indicative, not a plan)

- **Phase 0 — Spike (1 session).** Stand up a minimal `flutter_leak_radar_devtools` extension that
  loads in DevTools, grabs `serviceManager.service`, and prints a live `getAllocationProfile` from
  a real `--profile` device. Proves the connection premise (answers Q8). Nothing more.
- **Phase 1 — Live histogram.** The class-census table from `getAllocationProfile`, with refresh,
  sort, app-vs-framework highlighting (`app_package_set`). The "is anything obviously growing?"
  view.
- **Phase 2 — Snapshot capture + `leak_graph` wiring.** Capture (or import an on-device `.data`)
  snapshot, run `GraphLeakAnalyzer.analyze` in an isolate, render clustered findings + retaining
  paths. This is where `leak_graph` reuse lands and the companion becomes genuinely useful.
- **Phase 3 — Interactive retaining paths + source enrichment.** Drill class → instance →
  `getRetainingPath`, decorate nodes with `file:line:col` + source line (the `leak_detector`
  enrichment pattern).
- **Phase 4 — Snapshot diffing.** Baseline → action → compare; ranked grew-and-retained list, each
  row drillable. (If Q4 reprioritizes, this moves earlier.)
- **Phase 5 — Allocation-site tracing.** `setTraceClassAllocation` + allocation-stack view for
  "where is this allocated". (Deferrable per Q3.)
- **Phase 6 — Runtime ↔ companion handshake.** Shared events, "open in companion" links. (Per Q5.)

Each phase is independently shippable and leaves the runtime/lint packages untouched.
