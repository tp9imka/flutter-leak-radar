# Handoff: Radar Desktop — Heap & Memory Analysis App

A standalone **macOS-first desktop application** (Flutter desktop → cross-platform capable) for analyzing Dart/Flutter heap dumps. It is **dump-first**: the primary workflow is open → analyze → compare heap snapshots, entirely **offline**. A VM-service connection is **optional and purely additive** — when connected, it adds live heap capture, Force GC, and the "radar" Performance/Stability surfaces. It reuses the existing **radar_ui** design system so it's visibly one family with the on-device overlay and the DevTools extension.

`Flutter Radar — Desktop.dc.html` is the interactive reference (all views, offline + connected, sortable/searchable tables, master–detail drill-down, expandable retaining paths, the trend chart). `support.js` is **preview-only — do not ship.** Rebuild as a **Flutter desktop app** (`MacosWindow`/`macos_ui` or a custom shell), reusing `radar_ui` widgets and the `leak_graph` analysis engine — **no new analysis engine, no new design system** (non-goals).

The window chrome in the prototype (traffic lights, titlebar) approximates the native macOS frame — the real app gets that from the OS / `macos_ui`; treat it as indicative, not literal.

---

## Two additive states (the core concept)
- **Offline (default)** — work purely with dump files. Everything about *memory analysis* works with no connection. Nothing offline should look broken or disabled.
- **Connected (optional)** — attach to a VM-service URI (`ws://…`). Adds live capture, Force GC, and the radar umbrella (Performance, Stability). The transition should feel like **more appears**, not like things switch on.
- A persistent **connection indicator** (Offline / Connected · isolate) with a connect/disconnect affordance sits in the toolbar, mirroring the overlay's VM chip. In the prototype the header toggle (and the toolbar chip) flip between the two states — flip it to see Performance/Stability appear in the rail and the toolbar gain Capture + Force GC.

## Window chrome
- **Title bar**: traffic lights + centered workspace name ("chat-app soak") + "Radar Desktop".
- **Toolbar**: primary **Import dump** (green); when connected, **Capture heap** (cyan) + **Force GC**; right side shows dump/selection count + the **connection chip** (Offline grey / Connected green w/ live pulse, click to toggle).
- **Left rail**, grouped:
  - **MEMORY** (always present): Dumps · Class histogram · Retaining paths · Compare · Trends.
  - **PERFORMANCE** (connected only): Traces · Frames — shown locked (🔒, dimmed, non-clickable) when offline.
  - **STABILITY** (connected only): Errors · Stalls — same locked treatment offline.
  - An "OFFLINE" callout at the rail bottom explains what a connection unlocks (hidden when connected).

---

## Offline core (no connection)

### Dumps — the workspace
- A persistent workspace holding **multiple loaded dumps together**. Each row: an icon (file ▤ / capture ◉), filename, size, source (file/capture), captured timestamp, class count, total retained bytes.
- **Multi-select checkboxes** (drive Compare & Trends). Clicking a dump's name opens it in the histogram.
- A **drag-and-drop zone** ("Drop .dartheap files here, or browse") and a **Recent** files row.
- Save/reopen a workspace (a set of dumps + their analysis) — wire to a `.radarworkspace` file in the real app.
- **Large-data grace** (design for, per brief): dumps can be hundreds of MB / thousands of classes. Show an **"Analyzing…"** progress state while a background isolate parses (the prototype includes an indeterminate-bar keyframe `rdr-indet` and a spinner `rdr-spin` for this; virtualize the class/diff lists).

### Class histogram (single dump)
- Per-class **instance counts + shallow bytes**, plus a share bar. **Sortable** columns (class / instances / bytes), **searchable** (class/library), **filterable** by chips: all · leak-prone · app · collections.
- Rows are color-tagged by **dominant root kind** (leak-prone red / live-tree cyan / other green) — a legend sits by the filters. Row → opens Retaining paths for that class.
- Header shows which dump is active + total class count and retained bytes.

### Retaining paths + class detail (master–detail)
- **Master (left)**: classes **grouped by dominant root kind** (Leak-prone / Live-tree / Other), each with a count; click a class to inspect.
- **Detail (right)** — the **per-path instance distribution**, the highlight of memory analysis:
  - Class name + library + live instance count + shallow bytes.
  - **Root-kind breakdown** tiles: how many instances are retained via leak-prone roots vs. the live tree vs. other.
  - **Instance distribution by shortest retaining path** — the "144 → 24 via path A, 20 via path B…" table. Each row shows the count, a proportional bar, and % of instances, and **expands to the full hop-by-hop path** (GC root → field → … → object, with source locations). One row is expanded by default.
- Empty state prompts selecting a class.

### Compare (diff two dumps)
- Two dump pickers (A → B). Per-class **instance & byte deltas**, growth red / shrinkage green, **largest growers first** (sortable). Header shows the two dump names + total byte delta. This is the point-in-time diff; for many dumps use Trends.

### Trends (across N dumps) — the soak-test highlight
- Pick several dumps in the workspace (multi-select) and plot a **single class's instance/byte count as a time series** (line chart + per-point values/timestamps). A class climbing steadily and never returning to baseline is the classic slow leak — this is the primary tool for the week-long soak-test scenario.
- Class picker chips (growing classes). Headline shows first → last + net delta. Needs ≥2 selected dumps (shows a prompt otherwise).

### Output
- Export an analysis report (**JSON / Markdown**), export/share a dump, copy a retaining path. (Wire the toolbar/report actions; the prototype fires confirmation toasts.)

## Connected extras (VM service attached)
- **Live capture** — capture a heap snapshot from the attached app straight into the workspace (identical downstream analysis to an imported dump). **Force GC** before capture.
- **Radar umbrella screens** (from `radarscope`):
  - **Performance** — Traces (dense sortable table: count, avg, p95, p99, total, avg inter-call interval, errors; **HOT** = duplicate-suspect) and Frames (frame-time timeline + build/raster percentiles).
  - **Stability** — Errors (grouped + repeat counts) and Stalls (main-thread, **span-correlated** to the trace that blocked the isolate).
  - Plus live leak-detector findings if the target runs the runtime detector.

---

## Design direction (constraints)
- **Desktop-native macOS feel**: resizable multi-pane layouts, master–detail, keyboard shortcuts, drag-drop, right-click context menus, tabs/multiple windows where they fit. Build the real thing with `macos_ui` semantics.
- **Consistent with radar_ui**: the dark, dense, monospace-forward radar aesthetic (surfaces `#0e1316`, base `#0b0e10`, hairlines `rgba(255,255,255,0.07)`; radar green `#2fe39b`; severity red `#ff5d6c`, amber `#f5b54a`, cyan `#5ad1e6`; Space Grotesk headings, JetBrains Mono for all data/metrics with **tabular figures**). Extend for desktop density; don't diverge.
- **Large-data grace**: progress states, virtualized lists, "analyzing…" affordances; analysis on background isolates.
- **Offline-first clarity**: make obvious what's available offline vs. what a connection unlocks — without making offline feel crippled (locked-but-visible Performance/Stability + the offline callout do this).

## Non-goals (don't build)
- Not a general Dart profiler (CPU, allocation timelines) — that's DevTools.
- No new analysis engine — reuse `leak_graph`. No new design system — reuse `radar_ui`.

## State model (prototype)
`view` (dumps/hist/paths/compare/trends/traces/frames/errors/stalls) · `connected` · `selDump` · `checked[]` (workspace multi-select) · histogram sort/dir/query/filter · `selClass` + `expandedPath` · compare `diffA`/`diffB` + sort · `trendClass` · perf sort · transient `analyzing`/`toast`. In the real app, memory data comes from `leak_graph` over parsed dumps; connected data streams from the VM service.

## Files
- `Flutter Radar — Desktop.dc.html` — interactive reference (all views, offline + connected).
- `support.js` — preview runtime. **Do not ship.**
