# leak_detector — Borrow Report (critical)

Source: `leak_detector` v1.1.0 (Jiakuo Liu / liujiakuoyx), pure-Dart page-leak detector, ~3k LoC, at `/Users/aiva6306/Projects/+Sandbox/-Projects/+CHECK/leak_detector`. Evaluated specifically for our #1 pain point: a reliable **in-app VM-service self-connect on physical devices**.

---

## 1. Verdict — worth borrowing from?

**Yes as a reference, no as a dependency — and it does NOT solve our connection problem.**

The single most important takeaway is *negative but decisive*: a real shipped package independently converged on the **exact same** in-app self-connect path we already have, hit the **exact same wall** (host DDS owns the single VM-service socket on a tethered device), and offers **zero code fix** — it punts to the user with `--disable-dds` / detach-the-device. This is strong, independent corroboration that chasing a robust in-app self-connect *while DDS is attached* is a dead end, and that effort belongs in the host-side DevTools-extension companion (goal b).

Beyond that, there are 2–3 genuinely worth-stealing implementation details (source-location enrichment, force-GC-before-judging, navigator-observer ergonomics). Everything else is either worse than what we have or actively unsafe to adopt.

---

## 2. The VM-service connection technique — would it work for us?

### What it actually does (verified against source)

`vm_service_utils.dart:39-66`:

```dart
// _observatoryUri = await _channel.invokeMethod('getObservatoryUri');  // ABANDONED
ServiceProtocolInfo info = await Service.getInfo();      // dart:developer
_observatoryUri = info.serverUri;                        // often null on device/profile
...
Uri ws = convertToWebSocketUrl(serviceProtocolUrl: uri); // package:vm_service/utils.dart
_vmService = await vmServiceConnectUri(ws.toString());   // package:vm_service/vm_service_io.dart
// on SocketException → print("run with --disable-dds")
```

Three facts confirmed by reading the file directly:

1. **Line 41 is a commented-out, abandoned native method-channel attempt** (`_channel.invokeMethod('getObservatoryUri')`). They tried getting the URI from native and gave up; the native plugin is now boilerplate. So even the author concluded the method-channel route wasn't worth it.
2. The connect sequence is `Service.getInfo().serverUri` → `convertToWebSocketUrl` → `vmServiceConnectUri`. This is the **canonical minimal self-connect** — and it is byte-for-byte the path `vm_heap_probe.dart` already uses.
3. The failure handling is a `print`, not a fallback. On `SocketException` it tells the user to pass `--disable-dds`. README confirms the root cause in plain English: *"the DDS on the computer will first connect to the vm_service... causing leak_detector to fail to connect to vm_service again."*

### Would it work for us on physical devices? — No, for two independent reasons

- **DDS contention (tethered):** When the device is attached to `flutter run`, host DDS claims the one VM-service connection first. The app's `vmServiceConnectUri` is then *refused* (`SocketException`). leak_detector has no answer to this beyond `--no-dds`/detach. We already hit this.
- **`serverUri` is frequently null (untethered / profile / release-ish):** When the service URI was never published to the isolate — common on profile and physical builds — `Service.getInfo().serverUri` returns null, `getVmService()` silently returns null, and every check no-ops with only a console print. This is the *worse* failure: it's silent.

So the two operating modes cancel out: tethered → DDS refuses you; untethered → no URI to connect to. There is no window where this reliably works on a real device without operator intervention.

### Recommendation: **REJECT as our connection strategy. ADOPT only as confirming evidence + two hardening tweaks.**

There is nothing here that makes our self-connect more reliable than it already is — it *is* our self-connect, minus our `NativeRuntime.writeHeapSnapshotToFile` offline fallback (which is strictly better than what leak_detector ships). Concretely:

- **Reject** the idea that this package unlocks the in-app connection. It does not. Treat its README §"Cannot connect to vm_service on real mobile devices" as a citable, independent confirmation in our own design docs that the host-side DevTools-extension companion (`serviceManager.service`, already-past-DDS) is the correct path — not a stronger self-connect.
- **Adapt** two small robustness improvements into our existing `vm_heap_probe.dart`, *without* changing strategy:
  1. **Typed failure, not silence.** Where leak_detector prints, we should surface a structured `VmConnectUnavailable(reason: ddsRefused | uriNull)` up to the dashboard so the runtime path degrades honestly (per our honest-degradation rule) and auto-falls back to the `NativeRuntime` offline snapshot, rather than no-op'ing quietly.
  2. **Document `--no-dds` as the explicit "I want live in-app mode tethered" escape hatch**, exactly as they do — it's the only thing that makes tethered self-connect work, and it's cheap to document.

Integration sketch (small, in `vm_heap_probe.dart`):

```dart
Future<VmProbe> connect() async {
  final uri = (await developer.Service.getInfo()).serverWebSocketUri;
  if (uri == null) return VmProbe.unavailable(VmConnectReason.uriNull);
  try {
    return VmProbe.live(await vmServiceConnectUri(uri.toString()));
  } on SocketException {
    return VmProbe.unavailable(VmConnectReason.ddsRefused); // → offline snapshot fallback
  }
}
```

That's the entirety of what's worth taking on the connection front: a cleaner failure path and a doc note. **Net new reliability gained: zero.** The value is the validated redirect to the companion.

---

## 3. Other borrowable ideas

| Idea | Where | Criticality | Effort | Take? |
|---|---|---|---|---|
| **Retaining-path source-location enrichment** — resolve declaring `Field → Script`, then `getLineNumberFromTokenPos`/`getColumnNumberFromTokenPos` + `script.source.substring(...)` to print `file:line:col` + the actual code line holding the reference; plus closure owner/library/line resolution. | `leak_analyzer.dart:100-180` | **Medium** | Medium | **Yes — port into `leak_graph` / companion.** Genuinely upgrades a bare class-chain into "fix THIS line." Pure object-graph walking, reusable once we have any connection (live or snapshot). Best home is the host-side companion, where the round-trips don't jank a device. |
| **Force Full GC before judging** — `getAllocationProfile(isolateId, gc: true)` so only genuinely-retained objects survive the liveness check. | `vm_service_utils.dart:201-209` | **Medium** | Small | **Yes (host-side only).** Real false-positive reducer. But run it host-side in the companion, never on every route-pop on-device (jank — they acknowledge it). For our PRECISE mode (WeakReference+Finalizer) it's complementary, not required. |
| **NavigatorObserver auto-watch + delayed re-check + serial task queue** — one observer auto-watches each route's Element/Widget/State; `ensureReleaseAsync` waits ~500ms before judging (avoids false positives from deferred disposal); checks run one-at-a-time via a `Queue<DetectorTask>`. | `leak_navigator_observer.dart`, `leak_detector.dart:61-99` | **Medium** | Small | **Yes — mirror the UX patterns.** The delay-before-check and serialized-task ideas are good anti-false-positive / anti-thrash hygiene for our runtime detector. We don't need their observer wholesale, but the "watch on pop → wait → judge, serialized" loop is worth mirroring. |
| **`assert(() {…}())` gating on every entry point** for release no-op + tree-shake. | throughout | Low | Small | **Optional.** Matches our debug/profile-only requirement; we likely already do equivalent gating. Tidy idiom, low value-add for us. |
| **obj → VM ObjectId bridge** via stashing the object in a top-level map and `vmService.invoke('keyToObj',[keyId])` to recover an `InstanceRef.id`. | `vm_service_utils.dart:110-135` | Low | Small | **Niche.** Only useful if we ever need a live VM id for a *specific known* in-app instance (vs. scanning a snapshot). Still needs a working connection, so it inherits the same wall. Park it. |

---

## 4. What to explicitly NOT take — and why

- **Reading the Expando `_data` / WeakProperty / `propertyKey` internal layout for liveness** (`leak_detector_task.dart:96-135). **Reject.** It reads a *private VM/runtime implementation detail* through the VM service — brittle across Dart SDK versions and can break silently on an SDK bump. Our WeakReference + Finalizer + `reachabilityBarrier` PRECISE mode is a public, stable API and does **not** depend on the VM service at all, which is strictly better given our connection is unreliable. Their approach is worse for us on both stability and connectivity.

- **`toString()` / `invoke()` on live leaked instances during analysis** (`vm_service_utils.dart:149). **Reject.** Running arbitrary user code mid-analysis on a leaked object can throw or hang, and they swallow it in empty catch blocks. Unsafe and opaque.

- **Force-GC on every route pop on-device.** **Reject the placement.** `getAllocationProfile(gc:true)` per pop causes dropped frames (they admit it in the README). Take the *idea* (§3) but only host-side in the companion.

- **The whole route/page-scoped detection model as our primary mode.** **Reject as a strategy.** It only catches Widget/Element/State tied to routes — no heap-growth histogram, no snapshot analysis, no leaks outside the navigation lifecycle. Our heap-growth + retaining-path-graph + snapshot model is broader. Their observer is fine as an *ergonomic add-on*, not as the engine.

- **The native plugin.** **Reject.** Pure boilerplate (`getPlatformVersion` only) — no native heap/snapshot support. Nothing there; our `NativeRuntime.writeHeapSnapshotToFile` already does the on-device-without-VM-service job they never solved.

- **`sqflite` SQLite persistence.** **Skip.** Adds a dependency for qualitative per-leak history we don't need in that form; our reporting/export story is different.

---

## Bottom line

leak_detector is **moderately valuable as a reference, low as a dependency, and zero help on the actual in-app connection** — it is our own self-connect with a worse fallback. Its highest-value contribution is decisive negative evidence: an independent shipped package confirms the in-app VM-service self-connect cannot beat an attached DDS and offers no code fix, which **validates redirecting connection effort to the host-side DevTools-extension companion**. Concretely take three things — retaining-path source-location enrichment (medium/medium, into `leak_graph`/companion), force-GC-before-judging (medium/small, host-side only), and the navigator-observer delayed-serial-check ergonomics (medium/small) — and explicitly avoid the private-Expando liveness hack, live `toString`/`invoke` during analysis, per-pop on-device GC, and the route-only detection model as a primary strategy.

Verified source paths: `…/+CHECK/leak_detector/lib/src/vm_service_utils.dart:39-66` (self-connect + abandoned native channel at line 41), `…/leak_detector/README.md` §"Cannot connect to vm_service on real mobile devices" (DDS root-cause), `…/lib/src/leak_analyzer.dart:100-180` (source-location enrichment), `…/lib/src/leak_detector_task.dart:96-135` (private-Expando liveness — do not take).
