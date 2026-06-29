# Design brief — Radar: on-device observability suite for Flutter

> Hand this to the designer as the prompt. It describes the product, every surface, and the
> full feature/data inventory to design for. The goal is a complete UX/UI specification
> (wireframes + component specs + states) for the whole umbrella, not just one screen.

---

## 1. What you're designing

**Radar** is a developer tool for Flutter apps — an on-device + IDE observability suite that, during
development (debug/profile builds; fully invisible in release), surfaces three things:

- **Memory** — leak detection (objects retained after they should be freed; per-class heap growth; retaining paths).
- **Performance** — execution tracing (timed spans), frame/jank timing, widget rebuild counts, startup time.
- **Stability** — uncaught errors and main-thread stalls (ANR-like freezes).

It's used by **Flutter engineers while building/profiling an app**. Think of the reference class as
**Chrome DevTools (Performance), Flutter DevTools, Sentry, and Datadog/Firebase APM** — information-dense,
fast to scan, built for people who read numbers all day.

### Two delivery contexts (design both)
1. **In-app** — runs inside the running app on the device/emulator:
   - a small **draggable overlay badge** floating over the app, and
   - a full-screen **Inspector** opened from the badge.
   - Must work from **narrow phone widths up to tablet/desktop**. Respect safe-area insets (notch, status bar, home indicator).
2. **DevTools companion** — a panel embedded in Flutter DevTools on the developer's computer:
   - **wide desktop layout**, mouse + keyboard, more room and richer interactions than in-app.

---

## 2. Visual direction

- **Dense, professional, dark developer-tool aesthetic.** Compact rows, tight spacing, tabular/monospace
  numbers, right-aligned metrics, scannable hierarchy. The current build is **too sparse** — pack more
  signal per row and per screen without clutter.
- Current brand: mint/green accent **`#2fe39b`** on near-black **`#0a0d0e`** (you may refine, but keep the
  dark, restrained, accent-led feel). Decide whether to offer a light theme too.
- **Honest metrics:** every number shown is truthfully measured. Design must gracefully handle
  **"not measured / N/A"** and empty/loading states — never imply a value that doesn't exist.
- All screens are implemented in Flutter — favor patterns that are realistic to build (lists, tables,
  tabs, sparklines, simple charts; no heavy bespoke canvas unless justified).

---

## 3. Surfaces & full feature/data inventory

### A. Overlay badge (in-app, always-on, draggable)
- Tiny floating pill showing **overall health at a glance**: a severity glyph/color + key counts
  (e.g. leak count, jank indicator, error/stall indicator).
- States: clean / warning / critical. Must stay **inside the safe area** and be draggable without going
  under the notch or home indicator.
- Tap → open the Inspector. Consider a long-press quick-menu (force GC, scan now, jump to a tab).

### B. Inspector (in-app, full-screen) — three tabs: **Leaks · Performance · Stability**

**B1. Leaks tab**
- A **top summary row**: counts by severity (e.g. "10 critical · 5 warning"), a **VM-connection status
  chip** (states: connected / no-service-URI / refused-by-DDS / socket-error / disabled — show the reason
  on tap and that it fell back to an on-device snapshot), a **Force-GC** action, and the last scan time.
  This must stay readable as counts grow (wrap gracefully).
- A **findings list**, one row per suspected leak, each showing: **class name**, **kind**
  (not-GC'd / not-disposed / retained-by-non-live-root / growth), **severity**, **live count**, **growth**
  (+ a tiny growth sparkline over recent scans), owning **library**, optional **tag**.
- **Sort** (severity, growth, live count, class name) and **search/filter** (by name / kind / library / severity).
- **Drill-down** on a finding → the **retaining-path chain** (what holds the object alive, ideally with
  `file:line:col`), the growth series chart, and the allocation stack if captured.
- **Export / share** the findings (JSON / Markdown).

**B2. Performance tab** — sub-sections: **Traces · Frames · Rebuilds · Startup**

> **Traces is the priority redesign.** Today it shows only `count + p50/p95/p99` in sparse cards, sorted by
> count, with no search and no sort controls. It needs to become a dense, sortable, searchable analytics table.

- **Traces (timed spans):** a **compact, dense, sortable, searchable table**, one row per trace key
  (an operation name + optional category). Per row, surface (much more than today):
  - **count** (# of calls)
  - **avg** execution time (mean) — *prominent*
  - **p50 / p95 / p99 / max**
  - **total** time (sum across all calls — the real cost/impact)
  - **avg inter-call interval** — the average time *between* successive calls of this key (how often it fires)
  - **call rate** (calls/sec, derived)
  - **error count**
  - **last seen** / an "active" pulse
  - Numbers right-aligned, tabular; rows tight; the table scrolls; column headers are sort toggles.
  - **Sort by any column** (count, avg, p95, total, inter-call interval, name, …).
  - **Search / filter** by name or category; quick filters (e.g. errors-only, slowest, hottest).
  - **Duplicate-call detection:** surface operations invoked **suspiciously often / redundantly** — e.g. a
    badge or a dedicated "Hot / duplicate calls" view that ranks keys by call count and by a tight
    inter-call interval (same operation fired many times in quick succession), helping spot redundant work.
  - **Drill-down** on a key → a detail view: the latency **distribution** (histogram), the **slowest
    exemplar calls** (with timing + attributes), the **inter-call timeline**, and — for nested traces — a
    **parent/child span tree or mini flame chart** (spans carry parent/child + a shared monotonic clock).
- **Frames:** frame-timing overview — a frame-time **timeline/sparkline**, **build / raster / total**
  p50/p95/p99, **jank count + jank %** (frames over the budget), and the **worst recent frames**.
- **Rebuilds:** per-label **widget rebuild counts** (from instrumented subtrees) — sortable; flag
  excessively-rebuilding subtrees.
- **Startup:** time from init → first frame (a single headline span/metric).

**B3. Stability tab**
- **Errors:** uncaught-error **count** + a list of captured errors (message, type, time, **how many times
  the same error repeated**), drill-down to the stack trace. Sort/filter/search.
- **Stalls:** main-thread **stall count** + a list of stalls (duration over the threshold, when it
  happened) from the stall watchdog. Sortable by duration/time.

### C. DevTools companion (host-side, wide desktop)
Reuses the same domains but with the richer host connection. Design:
- A **connection/status** header (which app/isolate, live or disconnected).
- **Capture → act → capture → diff** as the spine: a primary action to **capture a heap snapshot**, then
  after the user exercises the app, **capture again and diff** — showing **per-class growth deltas**
  (instances + bytes, ranked) and the **retaining paths** for the grown classes.
- A **class histogram** view (full per-class instance/byte table — sortable, searchable).
- A **retaining-paths** view with source locations.
- Room to later add **allocation-site tracing** and a **Performance/Stability** tab mirroring the in-app one.

---

## 4. Cross-cutting requirements (apply to every list/table)
- **Sorting** and **search/filter** are first-class everywhere (traces, leaks, errors, histogram, rebuilds).
- **Density / compactness** is a primary goal — tight rows, tabular numerals, minimal chrome; the current
  layout wastes vertical space.
- **Empty / loading / "not measured" / error** states for every surface.
- **Drill-down** pattern: every list row opens a focused detail.
- **Export** affordances where data is worth saving (findings, a trace report, a snapshot diff).
- **Responsive**: narrow (phone overlay + inspector) ↔ wide (DevTools). Specify both; show how tables
  collapse/reflow on narrow widths.
- Decide and specify **light + dark** (or dark-only) consistently.

---

## 5. Specific gaps to fix (direct feedback driving this brief)
The Performance **Traces** view specifically must gain: **more data per row**, **sorting**, **search**,
**duplicate-call detection**, **average inter-call distance**, **execution count + averages**, and a
**more compact** layout. Use these as acceptance criteria for that view.

---

## 6. Deliverables
For each surface (overlay badge, the three inspector tabs incl. the four Performance sub-sections, and the
DevTools companion):
- **Wireframes / mockups** at the key breakpoints (narrow phone, tablet, wide desktop/DevTools).
- A **component + layout spec**: what each element shows (mapped to the data above), spacing/density,
  type scale, the table/row anatomy, sort/search/filter controls, and all states (default, empty,
  loading, error, not-measured).
- The **interaction spec**: sorting, filtering, drill-down, export, the capture→diff flow.
- Both themes if applicable, and a small **design-token** set (colors, type, spacing, severity palette).
