# Radar Native & GPU — Design Spec

> Status: **approved (design)**, pre-implementation. Date: 2026-07-02.
> Authoritative end-state scope for finding Android memory leaks the Dart-heap
> lane cannot see (native heap + GPU). Android-first; the models and UI are
> platform-abstracted so iOS/desktop capture backends can plug in later.
> Read `AGENTS.md` (golden architecture rules) and the Radar Desktop spec
> (`2026-07-02-radar-desktop-design.md`) before implementing — this extends both.

## Context — the Dart blind spot

The suite's existing lane (`leak_graph` + the `.dartheap` VM snapshot) finds
**Dart-rooted** leaks well: object clusters, retaining paths from GC root, root-kind
classification. But a whole class of real leaks is **invisible** to a Dart heap
snapshot — the snapshot contains only Dart objects, their references, and
external-size annotations. It contains **no native `malloc` allocations and no GPU
memory**. So when an Android app's memory climbs while the Dart heap stays clean,
the current tool has nothing to say.

That is the gap this spec closes. The trigger scenario is concrete: an app whose
**native heap + GPU memory** grows steadily while a `.dartheap` diff over the same
window shows no Dart object growth. The leak lives below the Dart heap — in engine
C++, a plugin, `dart:ffi`, an external video `Texture`, or an undisposed `ui.Image`.

### Environment (decided)

- **Android first.** Other platforms are out of scope for capture, but the models
  and views are platform-neutral.
- **Profileable builds are available.** The target app ships a
  `<profileable android:shell="true"/>` release variant, so **heapprofd works with
  no root**. This is the key unlock and a hard prerequisite (see [§8](#8-reliability--honest-degradation)).

## The success bar — "enough data to work on a fix"

Everything in this spec is judged by one criterion: **does it produce data an
engineer can turn into a code change?** A capability that yields a number nobody can
act on is not worth its cost. For a non-Dart leak, "enough data to fix" is four
items, and **all four must survive on a real device** (data that silently reads 0 on
a large device fraction is not fix-grade):

1. **Router verdict** — which bucket (Java / native+Dart / GPU), plus a same-window
   `.dartheap` delta proving the Dart heap is *not* the holder, plus Dart
   instance-**count**-by-class growth as a *positive* "Dart-caused, native-manifested"
   signal (not only a negative bytes test).
2. **An origin that names a code site** — for a native `.so` leak, the owning
   **module** name; for image / `Texture` / `dart:ffi`, a **Dart allocation stack**
   (function/file/line), because native unwinders dead-end at `libapp.so+0x` and
   Dart AOT is opaque to native symbolization.
3. **Proof of accumulation** — an alloc-minus-free still-live delta across **≥2
   checkpoints**, distinguishing an unbounded leak from a warm cache that plateaus. A
   single dump fails the bar.
4. **Repro correlation** — the growth curve tied to an app-event marker (the
   "+N per navigation / reconnect" staircase), which localizes the repro.

Explicitly **outside** the bar: native *function-level* symbols inside plugin/engine
C++ (module-level + preserved offset/build-id is enough for owned code; the sole
exception is `libflutter.so` for engine bug reports); GPU byte totals as anything
beyond confirmation/sizing; a fully synchronized 4-signal drill-down timeline.

## Goals

1. Catch and localize leaks that a `.dartheap` snapshot cannot see, to the "enough
   to fix" bar above, for six leak classes ([§2](#2-leak-taxonomy--per-class-fix-data)).
2. **Reuse, don't rebuild.** The triage router rides `adb` + `dumpsys` + the existing
   `.dartheap` delta. The native lane rides heapprofd + `trace_processor`. The
   on-device origin capture extends `flutter_leak_radar`. New models are siblings to
   `SnapshotBundle`, ingested by Radar Desktop like a `.dartheap`.
3. **Honest degradation everywhere** — when a signal can't be truthfully measured
   (memtrack returns 0, no symbols, no GPU tracepoint), read "not measured", never a
   plausible-but-wrong number.
4. Deliver two cheap, high-payoff fixes to the **existing** Dart lane that the
   deliberation proved necessary (count-based ranking; image-class flagging).

## Non-goals

- **Not a re-implementation of a native profiler.** heapprofd / Perfetto / Android
  Performance Analyzer do callstack-level native profiling better; we *drive* and
  *ingest* them, we do not replace them.
- **No Dart-level attribution from native tools.** `libapp.so` is Dart AOT — that is
  what the Dart lane and the on-device hooks are for.
- **No GPU per-resource attribution** (AGI-style Vulkan capture) — a GUI tool, not
  scriptable.
- **No general on-device profiler.** The on-device capture is constrained to
  `ui.Image`/`Texture`/`ImageStream` open handles + `imageCache` stats + an opt-in
  `dart:ffi` allocator wrapper. Nothing more.

---

## 1. Architecture — how it slots into the suite

Two new pieces, two extended packages, plus fixes to shipping code. Nothing breaks
`radar_workbench`'s **web-safe** constraint (no `dart:io`): all `Process`/`adb`/
`trace_processor` orchestration lives in `radar_native`'s `bin/`/`tool/` and in
`radar_desktop`; the **models** stay pure.

```
                        ┌──────────────┐
                        │   radar_ui   │  design system (+ RadarFlame, RadarLedger)
                        └──────┬───────┘
        ┌──────────────┬───────┴────────────┬────────────────┐
        │              │                    │                │
┌───────▼──────┐ ┌─────▼───────┐   ┌────────▼────────┐  ┌────▼──────────────┐
│  leak_graph  │ │ radar_native │   │ radar_workbench │  │ flutter_leak_radar │
│  Dart heap   │ │ NEW, pure    │   │ host-agnostic   │  │ on-device (EXTEND) │
│  (+count     │ │ native/GPU   │   │ views (EXTEND)  │  │  image/Texture/    │
│   ranking)   │ │ models+parse │   │  triage · flame │  │  ImageStream hooks │
└──────┬───────┘ └──────┬──────┘   │  · ledger · lite│  │  + ffi allocator   │
       │                │          │    timeline     │  │  wrapper (opt-in)  │
       └────────┬───────┘          └────────┬────────┘  └─────────┬──────────┘
                │                           │                     │ emits dumps
         ┌──────▼───────────────────────────▼─────────────────────▼───────┐
         │                       radar_desktop (EXTEND)                     │
         │  adb/trace_processor orchestration · symbol store · capture UX   │
         │  ingests .dartheap + .pftrace + on-device dumps into one session │
         └──────────────────────────────────────────────────────────────────┘
```

- **`radar_native`** *(new, pure Dart, publishable like `leak_graph`)* — the
  native/GPU brain. Pure models (`NativeHeapProfile`, `GpuHandleLedger`,
  `FfiAllocationLog`, `TriageTimeline`, `MemorySession`), the heapprofd/`trace_processor`
  parse layer, the `dumpsys`/`/proc` parser, the **pointer-address JOIN engine**, and
  diff/growth analysis. `dart:io` is confined to `bin/` (capture CLIs) and `tool/`
  (adb scripts), mirroring `leak_graph`'s `bin/capture.dart` + `tool/heapdump.sh`.
  The `lib/` models are pure so `radar_workbench` can render them on web.
- **`flutter_leak_radar`** *(extend)* — on-device origin capture: profile-mode
  wrapping of `ui.Image`/`Texture`/`ImageStream` create+dispose, an `imageCache`
  stat poll, and an **opt-in `dart:ffi` allocator wrapper**. Emits an ingestible dump
  (JSON) the desktop reads like a `.dartheap`.
- **`radar_workbench`** *(extend, stays web-safe)* — new views over `radar_native`'s
  pure models: triage panel, native flame/table + diff, GPU handle ledger,
  timeline-lite. No `dart:io`.
- **`radar_desktop`** *(extend)* — capture orchestration (`adb`, bundled
  `trace_processor_shell`), the build-id symbol store, and the capture UX; folds all
  dump types into one `MemorySession`.
- **`leak_graph`** *(fix)* — cluster ranking by instance-**count** growth-rate, not
  only retained bytes.

---

## 2. Leak taxonomy & per-class fix data

The scope exists to make each of these six classes reach the "enough to fix" bar.
This table is the acceptance contract — every row must be deliverable.

| Leak class | Minimal data to fix | Delivered by |
|---|---|---|
| **Native plugin C/C++ malloc** | still-live-bytes-by-callstack diffed across ≥2 dumps → owning `.so` + growth rate; offset/build-id preserved for local `addr2line` | Lane B (dominant) + module symbols; routed by Lane A |
| **`dart:ffi` allocation** | the **Dart** allocation stack at the FFI call site, joined to the leaked native block by pointer address | Lane D (ffi hook + pointer JOIN); Lane A confirms Dart-flat. *Unfixable-from-data if Lane D absent* |
| **Engine Skia/Impeller cache** | function-level `libflutter.so` buckets (`SkStrikeCache::*`, `GrResourceCache::*`) diffed across checkpoints, time-aligned with GPU totals + engine/backend metadata | Lane B + engine-symbol tier + GPU detector + timeline-lite |
| **GPU external `Texture`** | per-`textureId` live/disposed ledger with the **Dart creation stack**, owning class + owning-`State`, per-texture size | Lane C on-device (only origin source); GPU detector sizes it; Lane A routes |
| **imageCache / `ui.Image`** | `currentSizeBytes`/`liveImageCount` + `ui.Image` open-handle Dart stacks + existing retaining path & external-size | narrow Lane C (poll + on-demand handles) + existing Dart lane |
| **Native-held-by-Dart (WebRTC)** | Dart instance-**count** delta by class + retaining path through the live collection, correlated on one axis with reconnect markers + the `libwebrtc.so` native ramp | **existing Dart lane** (with count-ranking fix) + Lane B corroboration + timeline-lite |

The last row is the KATIM WebRTC case: it *is* Dart-rooted (listeners accumulate in
`Engine.events._listeners`, pinning native `libwebrtc` buffers), so the fix lives in
the existing lane — **provided** the router treats it as such and cluster ranking
surfaces a byte-tiny, count-growing leak. That is why Lane A and the count-ranking
fix are load-bearing, not polish.

---

## 3. The lanes

### Lane A — Triage router (thin; no root, any build)

Samples `adb shell dumpsys meminfo <pkg>` (App Summary) + `/proc/<pid>/status` on a
timer, trends the **deterministic** columns (jemalloc `HeapAlloc`, memtrack
`Graphics`, `RssAnon` — **never PSS**, which jitters ~20%), and correlates with a
`.dartheap` delta. Output: a bucket verdict (Java / native+Dart / GPU) **and** a fork:

- **Dart-holds-native** (Dart instance-count growing) → route to the **existing
  retaining-path lane**. The router must surface count growth as a *positive* signal.
- **genuinely native / GPU** (Dart flat) → route to Lane B / Lane C.

Guardrails: keep it thin — it must **not** become a second analysis engine. GPU
totals (formerly "P3a") are folded in here as a **confirmation-only detector**, never
a gate. Hardware-codec/GPU-backed native allocations show as `Graphics` growth, not
native heap — the router must route those to Lane C, not Lane B (routing accuracy is
load-bearing).

### Lane B — Native heap (heapprofd; profileable, no root)

heapprofd continuous-dump via `adb` → `.pftrace` → **bundled `trace_processor_shell`**
→ `export` to SQLite → query with `package:sqlite3`. Because heapprofd does
alloc−free accounting, **still-live bytes = leaked**. Outputs: leak suspects ranked by
leaked bytes **and growth rate**, each with the still-live call stack resolved to at
least the owning module; per-module totals; a diff across ≥2 captures; the growth
curve. **Preserve per-allocation pointer addresses** during ingestion (do not discard
them in aggregation) — Lane D's JOIN depends on it.

### Lane C — On-device GPU/image origin (narrow)

The only origin source for GPU/image leaks — kernel GPU totals give amount, never
cause. Extends `flutter_leak_radar` with a **profile-mode** capture (the debug-only
`debugGetOpenHandleStackTraces` is compiled out of AOT, so the library wraps
create+dispose itself):

- Open-handle ledger for `ui.Image` / `Texture` / `ImageStream`: Dart creation stack,
  owning class + owning-`State` lifecycle flag, dispose status, **per-texture byte
  size** (`w*h*format`).
- `imageCache` stat poll (`currentSizeBytes`, `liveImageCount`).
- A `textureId → owner` cross-reference into the existing retaining-path lane, to
  fork "add the missing `dispose()`" vs "a retained widget never ran `State.dispose()`".

Emitted as a JSON dump ingested like a `.dartheap`. It only catches **still-open**
(undisposed) handles — exactly the app-fixable surface. The "handle disposed but GPU
resource lingers" sub-case is an **engine/driver bug, scoped out** (documented, not
papered over with totals).

### Lane D — `dart:ffi` origin (hook + pointer JOIN)

The class the original pillars missed. A logging `Allocator` / `Arena` wrapper in
`flutter_leak_radar` records `{pointer, size, StackTrace.current, timestamp}` per
allocation. The **JOIN engine** in `radar_native` matches heapprofd's preserved
per-allocation pointer addresses against this log to attach a **real Dart stack** to a
leaked native block. Sequenced as a **fast-follow** after Lane C's image slice — but
in scope for the end-state, because without it (and given Dart AOT opacity)
`dart:ffi` leaks have no fix-enabling data. If it slips, `dart:ffi` is **documented as
a known v1 limitation**, never silently gapped.

### Symbolization (tiered)

- **T1 (default, v1):** module-level for all native `.so` — free and ~100% reliable
  (the build-id→module map ships inside the `.pftrace`). Always preserve **raw offset
  + build-id** so first-party engineers self-serve function names via local
  `addr2line` against their own unstripped build.
- **T2 (v1, cheap, required):** function-level **`libflutter.so`** via engine-hash
  fetch — the engine class genuinely needs it (glyph atlas / raster cache / GPU cache
  co-locate in one `.so`). **Must** also support a "point at a local symbol store /
  build-id dir" path — mandatory for KATIM's forked engine (no public symbols).
- **T3 (deferred, best-effort):** Dart-AOT resolution of `libapp.so+0x` via archived
  `--split-debug-info` — a lower-cost complement to the Lane D hook.
- **Cut:** the general plugin/app/ffi symbol-server fetch machinery.

### Timeline (partial)

- **Core (v1): timeline-lite** — event-marked per-signal trends + a minimal 2–3
  series overlay (native-heap trend + Dart per-class instance-count trend + GPU total
  when available), folded into Lane A's surface. Forced into v1 by the WebRTC case,
  whose causal claim needs reconnect markers + native ramp + Dart count-growth on
  **one axis**.
- **Deferred (polish):** the fully synchronized RSS/Native/Graphics/Dart single-axis
  drill-down with click-to-jump. Most classes are fixable from a per-object ledger or
  a two-snapshot Compare diff.
- **Reliability guardrail:** the series have wildly different fidelity/cadence. Render
  gaps and "not measured" markers; **never interpolate** the sparse Dart line into a
  smooth curve; never gate a verdict on `gpu_mem_total` being non-zero.

### Existing Dart-lane fixes (in scope)

- **`leak_graph`:** rank leak clusters by instance-**count** growth-rate in addition
  to retained bytes. Byte-only ranking systematically misses the real, byte-tiny,
  count-growing WebRTC proxy leak.
- **Dart lane:** flag `_Image` / `Codec` / `ImageCache` as leak-prone and surface
  external-size annotations prominently — near-zero cost, covers the common
  imageCache retaining-path + external-size half.

---

## 4. Data model & formats

New models live in `radar_native/lib/` as **pure Dart**, each with `toJson`/`fromJson`,
deliberately **not** wearing `leak_graph`'s `HeapGraphView` costume — native/GPU data
is callstack-aggregated with a `/proc/maps` module index, and has **no object
reference graph and no retaining path from a GC root**. Forcing the costume would lie.

- **`NativeHeapProfile`** — parsed heapprofd: callsites (parent-linked), still-live
  bytes per callsite, per-module totals, **preserved per-allocation pointers**, and a
  per-checkpoint series for diff/growth.
- **`GpuHandleLedger`** — on-device: open `ui.Image`/`Texture`/`ImageStream` handles
  with Dart stacks, sizes, owning `State`, dispose status; + `imageCache` stats.
- **`FfiAllocationLog`** — on-device: `{pointer, size, stack, ts}` records.
- **`TriageTimeline`** — sampled `dumpsys`/`/proc` deterministic columns + GPU totals
  + app-event markers + correlated Dart count-growth.
- **`MemorySession`** — the unifying container: time-aligns the above with the
  existing `SnapshotBundle` (`.dartheap`) analyses. This is what Radar Desktop
  persists (extends the `.radarworkspace` format) and what timeline-lite renders.

Dump formats ingested into one session: `.dartheap` (existing) · `.pftrace`
(heapprofd) · on-device JSON (ledger + ffi log) · sampled triage series.

---

## 5. Capture orchestration

Follows the existing `tool/heapdump.sh` precedent (bash/`adb`), profileable-first, all
in `radar_native/bin` + `radar_desktop`:

- **Triage sampler** — one long-lived `adb shell` driven as a REPL (avoid per-sample
  spawn cost); `dumpsys meminfo` at 15–60 s, `/proc/status` at 1–5 s.
- **heapprofd** — `perfetto`/`tools/heap_profile` config pushed over `adb`,
  **continuous-dump** for the growth series, **startup-mode + restart** to catch the
  pre-attach allocation backlog; pull `.pftrace`.
- **On-device dumps** — triggered via the existing radar overlay / a service
  extension; pulled or shared like today's `.dartheap`.
- **`trace_processor_shell`** — pinned and bundled per platform at a fixed version
  (SQL schema drifts); driven via `Process`, `export` to SQLite, queried with
  `package:sqlite3`.

---

## 6. Decisions resolved (D1/D2/D3)

Settled by a 12-agent fix-backward deliberation (six leak archetypes + scope-cutter +
reliability realist → three biased synthesizers → arbiter). Consensus was strong.

- **D1 — on-device image/texture instrumentation: IN, narrow.** Unanimous. The only
  origin source for the two classes the goal exists to catch, and the **most reliable
  signal in the system** (runs in a VM we control; touches none of the flaky
  substrate). Excluding it yields a tool that detects GPU growth but never says why —
  a direct failure of the bar.
- **D2 — symbolization: TIERED, module-first.** Module attribution is free and
  reliable and already clears the bar for owned code; function-level native symbols
  fail exactly at the `libapp.so` AOT wall where the hard cases live, and the
  symbol-server pipeline is the most fragile subsystem. Engine-hash `libflutter.so`
  fetch (with a local-symbol-store path) is the one cheap function-level tier in v1.
- **D3 — unified timeline: PARTIAL.** Timeline-lite is core (the WebRTC causal claim
  needs one shared axis); the full 4-axis synchronized drill-down is deferred polish.

---

## 7. Sequencing (end-state, not an iteration plan)

Order reflects dependency and reliability, not a commitment to phase boundaries (the
implementation plan splits this):

1. **Lane A router (thin)** + the two **existing-Dart-lane fixes** — cheapest,
   unblocks routing and the WebRTC class immediately.
2. **Lane C narrow on-device capture** — highest-reliability origin data; reuses
   shipping hooks.
3. **Lane B heapprofd + module symbolization + `trace_processor` bundling** — the
   native callstack engine; preserve pointers for Lane D.
4. **timeline-lite** folded into the router surface.
5. **T2 engine-symbol tier** (+ local symbol store).
6. **Lane D ffi hook + pointer JOIN** (fast-follow; without it `dart:ffi` is a
   documented limitation).

Deferred to post-v1 polish: full 4-axis timeline; T3 Dart-AOT split-debug-info tier.

---

## 8. Reliability & honest degradation

These are **v1 scope**, not afterthoughts — each failure mode below can make correct
data look broken or produce confidently-wrong output:

- **Profileable + unstripped build required.** Release builds strip `.so` → module
  attribution silently collapses to raw offsets. Require the instrumented profileable
  variant; if absent, say so loudly.
- **memtrack-0 / no `gpu_mem_total` devices** (Mali/PowerVR common) — Lane A cannot
  even measure GPU bytes; fall back to Lane C's `imageCache`/live-handle counts as the
  amount-and-cause proxy. Never gate a GPU verdict on non-zero totals.
- **Build-id mismatches** fail symbolization silently → surface them **loudly** with
  the mismatched ids, never yield a silently-broken stack.
- **heapprofd attach-mode** misses the pre-attach backlog → startup-mode + restart.
- **`trace_processor` schema drift** → pin + bundle a fixed version.
- **Sparse-series interpolation** → render gaps / "not measured", never a smooth line.

## 9. Risks

- **Coupled `dart:ffi` gap.** D1-narrow + D2-opaque-AOT together leave `dart:ffi`
  unfixable-from-data unless Lane D **or** the T3 AOT tier ships. Treat as coupled; if
  neither lands, document as a known limitation.
- **Lane C profile-mode dependency.** The always-available origin is the library's own
  profile-mode create/dispose wrapping; if the profiled build doesn't run the hook,
  the GPU/image origin data does not exist.
- **Existing-lane regression.** The count-ranking change and image-class flagging
  touch shipping `leak_graph` code — cover with tests so byte-cheap proxy leaks stay
  ranked.
- **Router mis-classification** of GPU-backed native (dma-buf/EGL/Vulkan) plugin
  allocations → must route to Lane C, not Lane B.

## 10. Out of scope / documented limitations

- Dart-level attribution from native tools (AOT opaque).
- GPU per-resource attribution (AGI).
- `am dumpheap -n` (redundant once profileable enables heapprofd; keep only as a
  documented rooted fallback).
- Non-Android capture backends (models/UI stay portable for later).
- "Handle disposed but GPU resource lingers" — engine/driver bug, not app-fixable.
