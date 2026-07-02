# Native & GPU spec — review: fit, feasibility, gaps

## 1. Verdict

This is a strong, well-judged complement to the Radar Desktop client — it targets exactly the leak classes the Dart-heap lane structurally cannot see (native malloc growth, GPU/image handles, ffi allocations), and its product instincts (the six-row taxonomy, the "enough to fix" bar, and the honest-degradation discipline) are sound and match how the desktop already thinks. But it is meaningfully harder than the prose implies: it is **net-new surface area** (a new `radar_native` package, five new model types, a `Process`-driven `.pftrace` pipeline, ~4–5 new screens), not a drop-in extension of `SnapshotBundle`, and **two of its four collection lanes rest on mechanisms that do not work as written** — Lane D's heapprofd pointer-JOIN is impossible, and Lane C's `Texture`-origin capture is unverified and likely infeasible for native external textures. The load-bearing v1 (Lane B heapprofd + Lane C image ledger + Lane A `dumpsys` sampler) is real and feasible today; the risk is concentrated in exactly the two places the spec leans on hardest.

---

## 2. How it fits the desktop client

**Home is correct.** `radar_desktop` already owns the right responsibilities: `dart:io`/`Process` orchestration behind a seams layer, a workspace concept for heterogeneous imported artifacts, a rail+screens shell with a locked/unlocked-group precedent, and a `.radarworkspace` persistence envelope the spec itself earmarks `MemorySession` for. Nothing at the shell/persistence level fights this.

**What fights it is total type-level coupling to Dart-heap concepts.** `SnapshotBundle` → `MemoryController` → `WorkspaceController.dumps` is keyed end-to-end to `ClassCount.className/libraryUri`, `RootKind`, and GC-root retaining paths. A native `malloc` site has no class or library; a GPU handle isn't a class instance; a `.pftrace` has no reference graph. The spec's own §4 says this outright ("no object reference graph and no retaining path from a GC root — forcing the costume would lie"). So the integration is **sibling types, not a bundle variant**.

**Minimal integration shape (concrete):**

- **New package `radar_native`** (pure Dart, publishable like `leak_graph`): the five new models + the parse layer + the pointer-join engine. Buildable and testable in isolation with zero `radar_desktop` changes.
- **`MemorySession` as a peer to `SnapshotBundle`, not inside it** — a time-aligned container that references the existing `.dartheap` analyses alongside native/GPU artifacts. `PersistedSession` today (`snapshot_store.dart`) is just `{version:1, bundles[], selectedIds, view}`; `MemorySession` is a genuinely new multi-modal shape.
- **Import paths split by lane, not one seam:**
  - Lane C (`GpuHandleLedger`) and Lane D (`FfiAllocationLog`) are JSON dumps — a cheap `*Analyzer.fromBytes` mirroring `SnapshotAnalyzer`, arguably no isolate needed. Clean fit.
  - Lane B (`.pftrace`) does **not** fit `fromBytes` — it needs a bundled `trace_processor_shell` binary → SQLite → `package:sqlite3` query. This is a `Process` pipeline, materially heavier than today's `File.readAsBytes`. This is the one genuinely heavy new seam.
  - Lane A (`TriageTimeline`) is a live-sampled time series (adb REPL, 1–60s cadence), architecturally closer to *connected mode* than to file import. Import-first means an external script pre-captures and the output JSON series is imported.
- **`SnapshotSource` is the pattern to copy, not the type to reuse.** It's typed to `SnapshotBundle` and is capture-only ("file import is NOT a `SnapshotSource`"). New pure interfaces (`NativeCaptureSource`, `GpuLedgerSource`, `TriageSampler`) belong in `radar_native`; concrete adb/`Process` Android impls belong in `radar_desktop/lib/src/seams/` next to `OfflineSnapshotSource`. Forcing native capture through the existing `SnapshotSource`/`RadarConnection` would be the exact "wearing the costume" mistake §4 rejects.
- **A 4th rail group** in `DesktopRail`/`DesktopView`, gated on **its own availability signal (adb/device present), not the VM-service `connected` bool** — reusing `connected` is semantically wrong here (native capture needs a device over adb, not a `ws://` VM-service URI). Or, truest to import-first: no lock at all, empty state until something is imported. Requires new `DesktopView` enum values excluded from the existing `.isMemory/.isPerf/.isStability` groups, and new `switch` cases in `DesktopShell._content()`.
- **A parallel `DumpMeta`-equivalent.** `DumpMeta` and the `_DumpTable` columns are hard-typed to `classCount`/`retainedBytes` — meaningless for a native profile (no class count) or a triage timeline (no single retained-bytes figure). New metadata shape wired alongside, not inside, `WorkspaceController.dumps`.

**Screens — reuse vs new:**

| Reuse **as-is** | New screen |
|---|---|
| `ClassHistogramView`, `DiffTable`, `ClassDetailPanel`, `RetainingPathsView` — but **only** for the one row the spec deliberately keeps in the Dart lane: **Native-held-by-Dart (WebRTC)**, which is Dart-rooted and fixed by the `leak_graph` count-ranking change, not a new view | Native callsite/module table (parent-linked tree, keyed by module+stack) |
| `retaining_path_tile.dart`'s hop-by-hop stack renderer — reusable *inside* the GPU ledger view | GPU/image handle ledger (handle + Dart creation stack + dispose status) |
| `DiffTable`'s sortable-table pattern — a template to **clone**, not reuse, for the ffi pointer table | Triage + timeline-lite (multi-series, gap-aware — needs a multi-series variant of `RadarTrendChart`/`_SparklinePainter`, which is a single-series primitive) |
| `CompareScreen`'s two-picker UX — a template to **clone** for native two-checkpoint diff | ffi pointer-join table (fast-follow) |

Dumps / Histogram / Paths / Compare / Trends stay exactly as they are, continuing to serve the Dart lane only.

---

## 3. Collection paths, ranked by feasibility × value

Judged against the spec's own bar: import-first (pull to a file, re-parse offline) and fix-grade (names a code site or proves accumulation). Verdicts use current Android (10–16 era) tooling.

| Rank | Path | Captures | Requirements | Importable format | Effort / Risk |
|---|---|---|---|---|---|
| **1** | **heapprofd / Perfetto (Lane B)** — *the anchor* | Callstack-attributed native allocs via malloc/free hooks; **alloc−free = still-live = leaked**; per-module/per-callsite bytes; continuous-dump growth series; startup mode catches pre-attach backlog | **No root**; target **profileable or debuggable**; **Android 10+** (Java-heap mode 12+) | `.pftrace` → `traceconv` (pprof) or `trace_processor` SQL over stable tables (`heap_profile_allocation`, `stack_profile_callsite/frame/mapping` w/ build-id) | Med / Low-Med. **Winner.** Design is correct — but **strike the "preserve per-allocation pointer addresses" line** (see below). |
| **2** | **In-app image/Texture ledger + `imageCache` poll (Lane C)** | Open-handle ledger: `StackTrace.current` at creation, dispose status, owning `State`, per-texture `w*h*format` bytes; `imageCache.currentSizeBytes`/`liveImageCount` | VM the plugin controls; **wrap create/dispose in the library** (the debug API `debugGetOpenHandleStackTraces()` is AOT-stripped — spec correct) | Plain JSON, ingested "like a `.dartheap`" | High / **Med** — see the `Texture` caveat in §4. Only origin source for GPU/image leaks. `imageCache` poll is trivial + high value. |
| **3** | **`dumpsys meminfo <pkg>` sampler (Lane A backbone)** | Per-process PSS/RSS breakdown: `Native Heap`, `Heap Alloc/Free`, `Gfx dev`, `GL/EGL mtrack`, `.so/.dex/.art` mmap. Runs inside `system_server`, sidesteps per-app SELinux | **No root, any build, any app** | Column-structured text → deterministic parse → your `TriageTimeline` series | Low / Low. Safest capability in the spec. Trend deterministic columns (`Heap Alloc`, memtrack `Graphics`, `RssAnon`), **never PSS**. |
| **4** | **In-app `dart:ffi` alloc/free wrapper (Lane D, reframed)** | Logging `Allocator`/`Arena` recording `{pointer, size, StackTrace.current, ts}` on alloc, clearing on free → still-live ffi blocks **with a real Dart stack** | VM the plugin controls | JSON | High **standalone** / — . **The heapprofd JOIN half is not feasible** (§4). Wrapper alone is fix-grade; drop or downgrade the JOIN. |
| **5** | **`Debug.getNativeHeapAllocatedSize()` / `malloc_info` (in-app)** | Total native bytes (no stacks); jemalloc/scudo arena XML | In-app, cheap | Numbers / XML | Low / Low. Always-on corroboration of Lane A without adb. |
| **6** | **GPU totals: `gpu_mem_total` eBPF / dumpsys `GL mtrack` / `dmabuf_dump`** | Per-process GPU bytes (amount, not cause) | Android 12+ tracepoint; **`dmabuf_dump -b` per-process needs root**; **vendor must implement the memtrack HAL** | Tracepoint / text | Med / **High on a device fraction** — Mali/PowerVR frequently read **0**. Confirmation-only, honest-degradation **mandatory**, never a gate. Spec correct. |
| **7** | **`libmemunreachable` / `dumpsys meminfo --unreachable` — NOT IN SPEC** | Imprecise mark-and-sweep over native memory → reports **unreachable** blocks (bytes + backtraces) as true leaks, in **one shot, no growth window** | Root or debuggable | Parseable text | Med / Med-High. **Worth reconsidering** — it's the closest native analogue to Dart's GC-root model and distinguishes a *true leak* from a *growing cache*, which heapprofd's alloc−free accounting cannot. |
| **8** | **`am dumpheap -n <pid>` (rooted fallback)** | Retained native allocs grouped by size+backtrace + embedded MAPS | **Root** or `wrap.sh` rebuild + malloc_debug | Text → AOSP `native_heapdump_viewer.py` | Med / High. Keep only as documented rooted fallback (redundant once profileable enables heapprofd). Spec correct. |
| **9** | **`/proc/<pid>/smaps` + `showmap` (target app)** | Per-mapping RSS/PSS, finer than dumpsys | **Root-gated** — cross-process read blocked by ptrace + SELinux on user builds | Text | Low / **High (root)**. **Drop this line from Lane A** or label root-only; use `dumpsys`. `/proc/<pid>/status` (RssAnon) is fine — keep it. |
| **10** | **`dumpsys gfxinfo`** | Frame timing / jank, display-list stats | No root | Text | Low / Low. **Not a memory-leak signal.** Low value here. |

**Android Studio export is redundant, not required.** Studio's "Native Memory Profiler" *is* heapprofd; its export is the same `.pftrace` protobuf — there is no proprietary Studio-only format to reverse-engineer. Driving `tools/heap_profile` over adb yourself yields the identical artifact and is cleaner for a scriptable import-first tool.

**Winners for an import-first v1: #1 (heapprofd) + #2 (Lane C ledger) + #3 (`dumpsys` sampler).** All three are no-root, produce offline-reparseable artifacts, and cover amount (B/A) + cause (C).

---

## 4. What is missing / underspecified

### Blocking

**B1 — No concrete data model for any of the five new types.** §4 is one prose sentence each; contrast `GraphLeakCluster`/`ClassCount`/`ClassCountDiff`, which already ship with real `toJson`/`fromJson`/equality/hashCode. An implementer cannot start Lane B/C/D without deciding: parent-linked callstack tree representation (nested records vs. flat parent-index array, à la `HeapNode`), and whether `MemorySession` carries a `version` field like `PersistedSession` does. **Needed: Dart class skeletons + JSON schema + version fields for all five before any plan doc.**

**B2 — Lane D's heapprofd pointer-JOIN is impossible as written.** The spec says "preserve heapprofd's per-allocation pointer addresses" and JOIN against the ffi log. **heapprofd Poisson-samples by size and aggregates by callstack — it discards individual malloc-returned pointers.** You cannot recover a leaked block's address from a `.pftrace`. Two independent lenses confirmed this against Perfetto's own design doc. **Reframe: the in-app ffi wrapper alone is fix-grade (it already has the Dart stack); use heapprofd only to corroborate *total ffi bytes by module*, not to attach stacks by pointer.** Strike the "preserve pointers" instruction. (Compounding this: even the byte-total corroboration is weakened by default ~4KB sampling, which under-samples the small ffi structs most likely to leak — pin `sample=1` on the instrumented build or document the miss-rate.)

**B3 — Lane C's `Texture`-origin mechanism is asserted, not specified, and likely infeasible as literally written.** Wrapping create/dispose is plausible for `ui.Image`/`ImageStream` (Dart-side classes — and worth checking whether `leak_tracker`'s `FlutterMemoryAllocations` dispatcher / `kFlutterMemoryAllocationsEnabled` is true in profile builds, a far cheaper path than a bespoke wrapper). But `Texture` is an opaque `textureId` int; the native GPU surface is registered **engine-side via `TextureRegistry`** by a plugin (camera, video_player), with **no plugin-agnostic Dart hook** for "native external texture created/destroyed." Only the `Texture(textureId:)` *widget's* build/dispose is interceptable — a materially weaker signal than native-resource lifecycle. D1 calls Lane C "the only origin source" and "most reliable signal in the system" for exactly this class, so the whole decision rests on an unverified mechanism. **Needed: either (a) a spike proving the hook fires for `Image`/`Picture`/`Texture` in a profileable AOT build, or (b) scope down honestly — "Texture tracking = widget lifecycle only; native resource lifecycle out of reach without plugin cooperation" — as a documented limitation (the spec already does this well elsewhere).**

**B4 — `.radarworkspace`/session integration is asserted, not designed.** The current format is flat JSON, Dart-heap-only, with shipped save/open/auto-restore. "Extends" needs a real answer to: (a) a version-bump/migration path for existing saved workspaces, and (b) — much bigger — **how binary, tens-to-hundreds-of-MB artifacts (`.pftrace`, the SQLite export) live inside a JSON file.** The sibling desktop spec explicitly left "single JSON vs. zipped bundle" as a deferred open question for its *much smaller* payloads; this spec's payloads are categorically bigger and binary yet never reopens it. **Needed: embed vs. external-file-reference vs. zip-container decision before Lane B/C dumps have anywhere to live.**

**B5 — No UI/nav integration point into the shipped architecture.** `RadarView` has exactly 7 values, all Dart-heap/perf/stability; `radar_desktop` has 5 concrete screens around `MemoryController`/`WorkspaceController`. The spec never says whether Triage/native-flame/GPU-ledger/timeline-lite are a 4th rail section, sub-tabs of Memory, or a new workspace-row type per dump kind — and never touches `RadarView`/`RadarSession`. **Needed: explicit `RadarView` extension + a `MemorySession`-analog controller paralleling how `MemoryController` wraps `SnapshotSource`+`RadarConnection`.**

### Important

**I1 — The "existing Dart-lane fix" premise is partly stale.** `clusterLeaks` (`clustering.dart:99-103`) **already** sorts by `instanceCount` desc, bytes second; `computeDiff` (`histogram_diff.dart:59`) **already** sorts by `instanceDelta` desc. So the framing "byte-only ranking misses the count-growing WebRTC leak → add count-based ranking" overstates what's missing. The genuinely-absent piece is narrower — likely a per-*cluster* cross-snapshot growth-rate view keyed by leak signature (vs. the current raw per-*class* histogram diff) — plus flagging `_Image`/`Codec`/`ImageCache` as leak-prone (that half *is* genuinely absent, grep-confirmed). Re-scope this precisely; don't sell it as "cheapest, unblocks immediately" on a stale assumption.

**I2 — Lane C's leak criterion is instrumentation, not analysis.** "Still open" ≠ leak — galleries/video/caches legitimately hold many live images. The `Texture` row gets a discriminator (`textureId → owner` cross-ref into the retaining-path lane: missing `dispose()` vs. retained widget), but generic `ui.Image`/`ImageStream`/`imageCache` handles get none. Without one, the ledger reports "N open handles," indistinguishable from steady-state usage.

**I3 — Dart-correlation quality is bimodal but the spec doesn't say so.** Exact object-level: `dart:ffi` (pointer match) and Native-held-by-Dart (already Dart's own retaining path). Direct Dart-stack: Texture/imageCache (Lane C instrumentation). Module-name-only (explicit non-goal): plugin malloc. Time-correlation only, never object: engine Skia/Impeller cache. State this spread plainly so the tool doesn't imply uniform fix-grade specificity across all six rows.

**I4 — `MemorySession` time-alignment glosses over clock-domain skew.** heapprofd timestamps are device-monotonic-boot-relative; `.dartheap` + on-device JSON are Dart wall-clock; `dumpsys`/`/proc` are host/adb wall-clock. The "never interpolate" guardrail is good, but nothing says which clock is authoritative or how skew is normalized before the "one shared axis" that the load-bearing WebRTC causal claim (§7 item 4) depends on.

**I5 — Per-texture `w*h*format` is a computed estimate, not a measured GPU allocation.** It will diverge from real driver size (compression, mipmaps, alignment, pooled engine textures) and is presented flatly in the §2 table as "per-texture size" with no caveat, and nothing reconciles it against Lane A's kernel `Graphics` total. State the expected divergence up front so a mismatch reads as expected, not a bug.

### Minor

- **M1** — Lane A's "trend the deterministic columns" has no concrete threshold (what growth-rate on `RssAnon`/`HeapAlloc`/`Graphics` counts as trending vs. jitter). Fine to defer to device-testing, but budget for it.
- **M2** — T2's "point at a local symbol store / build-id dir" (mandatory for KATIM's forked engine) doesn't specify the lookup convention (directory-keyed-by-build-id? manifest?). Small, but blocks starting that sub-task.
- **M3** — `radar_trace` (already-shipped pure-Dart span/histogram/Zone tracer in this monorepo) is never considered as a substrate for `TriageTimeline`'s sampled series + event markers, despite conceptual overlap and the spec's own "reuse, don't rebuild" goal. May be deliberate — a one-line note would close it.

### The core algorithmic question — "what is a leak with no GC roots?"

The spec answers this correctly for its primary lane and it's worth stating plainly: with no native GC, the substitute is **alloc−free still-live accounting over ≥2 heapprofd checkpoints, ranked by bytes + growth** (Lane B). That is a reasonable and standard substitute. Its one blind spot: a reachable-but-unbounded cache also shows up as "still-live and growing" — hence the spec's plateau-vs-unbounded test, and hence the case (I7 in the feasibility lens) for adding **`libmemunreachable` as a one-shot complement** that separates a true leak (unreachable) from a growing cache (reachable) in a single scan — something heapprofd cannot do.

---

## 5. Recommended path

### Smallest useful v1 — one vertical slice, end-to-end

Ship **Lane B (heapprofd) as the single collection path**, with **one analysis** (per-module/per-callsite still-live bytes, diffed across exactly two imported `.pftrace` captures) and **one new screen** (native callsite/module table + a clone of `CompareScreen`'s two-picker for the diff). This is the highest feasibility × value path, it's no-root on a profileable build, and it produces the fully offline-reparseable `.pftrace` the whole import-first premise depends on. It also exercises every hard integration seam once — the `Process`/`trace_processor_shell` pipeline, a new `radar_native` model with real schema, a `MemorySession` container, `.radarworkspace` large-binary handling, and a 4th rail group — so the plumbing is proven before Lanes A/C/D pile on.

### Prove first — three spikes, in this order, before writing the plan doc

1. **`.pftrace` round-trip (highest leverage, lowest risk):** capture heapprofd on a profileable KATIM build over adb → bundle a version-pinned `trace_processor_shell` → export SQLite → query `heap_profile_allocation` + `stack_profile_mapping` via `package:sqlite3` → resolve a growing callsite to a module using the embedded build-id against a local symbol store. If this works (it should), the anchor lane is de-risked and B4's large-binary question gets forced early.
2. **Lane C `Texture` hook reality-check (research-grade — resolve B3):** in a small profileable AOT app, verify whether *any* Dart-side hook fires for native external-texture create/destroy, and whether `kFlutterMemoryAllocationsEnabled` / `FlutterMemoryAllocations` is live in profile mode. Timebox it. If it only fires for the `Texture` *widget*, scope Lane C down honestly and say so — do not ship D1's "most reliable signal" claim on an unverified mechanism.
3. **Lane D wrapper standalone (cheap — confirms the reframe):** a logging `Arena`/`Allocator` recording `{pointer, size, StackTrace.current}` on a build with a known ffi leak, proving still-live-with-stack works **without** any heapprofd JOIN.

### Defer

- **Lane A `TriageTimeline`** — it's a live-sampled series, not a static import; deferring it keeps v1 honestly import-first. (When it lands, base it on `dumpsys meminfo` + `/proc/status`, **not** `/proc/smaps`.)
- **Lane D pointer-JOIN** — drop entirely, or downgrade to module-level byte corroboration. Keep only the standalone wrapper from spike 3.
- **The ffi pointer-join table screen** and **GPU-totals collection** (vendor-dependent, often 0) — fast-follow, gated on Lane C proving out as the cause-source they degrade back to.
- **`libmemunreachable`** — not in v1, but log it as a candidate Lane B complement for the leak-vs-cache discriminator.

### Where the spec over-reaches vs. undersells

- **Over-ambitious / research-grade:** the Lane D heapprofd pointer-JOIN (impossible — B2), and the Lane C `Texture` native-resource hook (unverified, likely widget-only — B3). These are the two places the spec claims its strongest guarantees and rests on the weakest mechanisms. Flag both as research-grade in the spec itself.
- **Undersells:** the amount of net-new architecture. The spec's "extends `SnapshotBundle`/`.radarworkspace`" / "views land in `radar_workbench`" framing reads as incremental, but every lens independently found the same thing — the data model, the workspace/large-binary story, and the nav wiring are all **absent and blocking**, and are as serious as any algorithm gap because without them there is nowhere to put what Lanes A–D produce. Budget for them as first-class work, not glue.
- **Gets it right (keep as-is):** profileable-first heapprofd, module-first symbolization, GPU honest-degradation (never gate on non-zero totals), Lane C as sole origin source, the debug-API-is-AOT-stripped rationale for wrapping create/dispose, and keeping the WebRTC "native-held-by-Dart" case in the existing Dart lane via count-ranking rather than routing it into the new lane. All corroborated.