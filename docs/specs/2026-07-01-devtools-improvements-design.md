# DevTools & Overlay Improvements — Design Spec

> Status: **approved**, in implementation. Date: 2026-07-01.
> Authoritative design for a batch of fixes/features across the leak_radar dev tools,
> driven by a user punch-list. Three independent workstreams (A / B / C), each landing
> as its own PR.

## Context

A punch-list from dogfooding the tools surfaced gaps against native DevTools Memory and
several overlay-UX rough edges. This spec captures the agreed design. Read
`AGENTS.md` (golden architecture rules) before implementing any of it.

Workstreams:
- **A — Memory / DevTools** (`flutter_leak_radar_devtools`, `leak_graph`)
- **B — Overlay UX** (`flutter_leak_radar`, `radar_ui`)
- **C — Tracer & Perf** (`radar_trace`, `flutter_perf_radar`)

---

## Section A — Memory / DevTools

### A1 · Session state survives native-tab teardown

**Problem.** Switching to Flutter DevTools' own **Memory** tab and back disposes the
leak_radar extension iframe. The `RadarSession` singleton and every captured
`SnapshotBundle` live only in that ephemeral web context, so they vanish; returning
loads a fresh, empty extension. The singleton is not a durable layer.

**Design.** Durable persist + rehydrate.
- New `SnapshotStore` abstraction: `Future<void> persist(PersistedSession)` /
  `Future<PersistedSession?> restore()` / `Future<void> clear()`.
- `PersistedSession` = serialized `List<SnapshotBundle>` (already `toJson`/`fromJson`)
  plus small metadata: selected ids, current view.
- `MemoryController` debounce-writes (≈500 ms) on every mutation (capture, selection,
  remove, clear). `RadarSession` calls `restore()` during init and rehydrates the
  controller before first paint.
- **Backend** (confirmed by the A1 research spike before coding):
  - Large blobs (snapshot bundles): persisted via the **Dart Tooling Daemon (DTD)
    file service** if available to the extension, else a chunked fallback.
  - Small metadata (selection, view): browser `localStorage` (survives same-origin
    iframe recreation) is sufficient and always available.
  - Chosen backend is wrapped behind `SnapshotStore` so the UI is backend-agnostic.
- **Bounds.** Keep the last N bundles (default 8), evict oldest, to respect storage
  limits. Provide a manual "Clear session" action; show a subtle "restored" indicator
  after rehydration so stale data is never silently presented as live.

**Isolation.** `SnapshotStore` is a pure interface with a concrete
DTD/localStorage implementation and an in-memory test double. `MemoryController`
depends only on the interface.

### A2 · Compare a snapshot against nothing (absolute heap view)

**Problem.** All diffs are gated on `pair != null` (exactly two snapshots). No way to
see "everything in this snapshot" as a diff/table.

**Design.** `computeDiff` already synthesizes a zero baseline for unmatched classes, so
`computeDiff(const [], snapshot.histogram)` already yields absolute values. Wiring only:
- Introduce a baseline mode on `MemoryController`:
  `sealed DiffBaseline { EmptyBaseline | SnapshotBaseline(id) }` (or an enum + optional
  id). Default stays pairwise for backward-compatible auto-diff.
- When one snapshot is selected and baseline is `Empty`, `diff` returns
  `computeDiff(const [], selected.histogram)`.
- `SnapshotsView`: when exactly one snapshot is selected, show a
  "Compare against: [None — show all ▾] / [other snapshot ▾]" control instead of the
  "select two" hint. `DiffTable` header adapts wording (delta vs absolute) via a flag.
- Test: `computeDiff([], histogram)` returns every class with full positive delta.

### A3 · Per-path instance distribution (eager, top classes)

**Problem.** `leak_graph` aggregates instances only by `RootKind` (`byRoot`) and stores
one `representativePath` per class, so it cannot show the native "144 instances → 24 via
path A, 20 via path B…" distribution.

**Design.**
- **Model** (`leak_graph`): `ClassPathDistribution { String className; int
  totalInstances; List<PathBucket> paths; int otherPathCount; }` and
  `PathBucket { GraphRetainingPath path; int instanceCount; int shallowBytes; int
  retainedBytes; }`. JSON-serializable. Bucket key = existing `pathSignature`
  (last-12-hops, `[]`-collapsed) so "distinct path" matches clustering semantics.
- **Analyzer** (`leak_graph`): `buildClassPathDistributions` pass over the
  **top-N classes by instance count ∪ all leak-prone classes** (reuse the existing
  representative-path bound). For each such class, reconstruct each instance's shortest
  path from the BFS parent/edge table, group by signature, aggregate count + sizes,
  keep a representative `GraphRetainingPath` per bucket. Cap at top-20 buckets/class
  with an `otherPathCount` rollup. Attach `Map<String, ClassPathDistribution>` to
  `GraphAnalysisResult`; serialize into `SnapshotBundle` so exports carry it.
- **Guardrails.** Bounded to top-N classes and capped buckets → analysis stays
  O(reachable), snapshot size stays bounded. Truncation is surfaced ("+k more paths"),
  never silently dropped.
- **UI** (`flutter_leak_radar_devtools`): `ClassDetailPanel` renders the image-#12
  table (rows = distinct paths: `instances | shallow | retained`, retained-sorted).
  Tapping a row expands the full hop-by-hop `GraphRetainingPath` (root→object). Keep
  the `byRoot` breakdown as a compact summary above. Classes without a materialized
  distribution show today's coarse root view + a note.

---

## Section B — Overlay UX

### B1 · Dismissible VM banner
`_VmDegradedBanner` gains a trailing ✕. `bannerDismissed` state hides it; it re-shows on
any `VmServiceStatus` transition or an explicit reconnect tap. Dismissal is per-incident,
not permanent.

### B2 · Collapsible filters
Wrap `_SortRow` + `_KindFilterRow` in a compact "▸ Filters (N)" disclosure (`AnimatedSize`),
collapsed by default; N = count of active non-default sort/filter. Drops the pre-list
vertical budget from ~126 px toward summary + search + toggle. Expanded/collapsed state
persists for the session.

### B3 · Ripple + tap feedback
Replace bare `GestureDetector`s with `Material + InkWell` (splash, preserved styling) on:
`_LeakActionBar` (Force GC / Scan / Clear), `LeakRadarScreen._BottomBar` (Scan now), and
shared `radar_ui` widgets `RadarSortHeader` + `RadarFilterChip`. Add
`HapticFeedback.selectionClick()` on the action buttons. Busy/disabled → `onTap: null`
(ripple suppressed). Compositor-cheap; no layout-property animation.

### B4 · Lazy retaining-path in detail
`FindingDetailScreen` stops calling `_fetchPath()` in `initState`. Graph findings still
render their carried path instantly. Non-graph findings show a "Retaining path — tap to
load" affordance that fires `_fetchPath()` only on tap. Removes the open-time freeze.

---

## Section C — Tracer & Perf

### C1 · Tracer duplicate grouping (port of legacy pattern)
Port the legacy `tracer.dart` pattern (`katim-connect-matrix`): optional `dedupKey`
(`List<String>`, comma-joined into a signature) on `Tracer.trace/traceAsync/start`.
`SpanKeyStats` keeps a bounded `Set<String>` (~1024) of seen signatures +
`duplicateCount`; on `record`, a span carrying a signature increments the count if the
signature was already seen, else adds it. Surface "duplicates: X / N calls" in
`TraceDetailScreen`, distinct from the existing statistical "HOT" heuristic.

### C2 · Span-timeline render crash fix
The red "Invalid argument(s): 6.0 / docs.flutter.dev/testing/errors" boxes are an
`ErrorWidget` thrown by `_SpanTimeline`: a degenerate `window` (all spans share a start ⇒
divide-by-zero / NaN width) produces an invalid box dimension. Guard against a zero /
non-finite window, clamp offsets and widths to finite `>= 0`, and never hand a
`SizedBox`/`Container` a NaN or negative dimension. Widget test with degenerate inputs
(identical start, zero duration, single span) that currently throws. Independent of C3.

### C3 · Stalls detail + correlation
`_StallRow` becomes tappable → new `StallDetailScreen` (mirrors the Errors-tab detail).
Enrich `StallRecord` only with cheap, truthful context (session wall-clock, detection
`clockMicros`, and the active span *iff* it genuinely overlaps the stall window). At
render time, correlate the stall window with retained **slow spans** and the nearest
**frame sample(s)** → "this 312 ms stall overlapped `getConversationRecords` (280 ms)
and a 340 ms janked frame."

**Honesty guard.** The watchdog fires *after* the block clears, so an "active span" is
shown only when it truly overlaps; otherwise "no instrumented span active" — never a
guess. Documented limitation: only retained outlier spans are available to correlate;
a culprit span not slow enough to be retained will not appear.

---

## Sequencing & testing

- Three independent workstreams → three PRs (A / B / C). A is heaviest (analyzer +
  persistence spike); B is mostly UI; C is model + UI.
- Every logic change is TDD'd (analyzer aggregation, empty-baseline diff, dedup
  counting, timeline-window guard, stall correlation). UI changes get widget tests where
  they carry behavior (dismiss/re-show, lazy load, collapse).
- Respect `AGENTS.md`: single public library per package, show-list exports, internals
  under `src/`, debug/profile-only, zero mandatory mixins.
