# Handoff: Flutter Radar — DevTools companion (wide desktop)

The host-side surface: a panel embedded in **Flutter DevTools** on the developer's computer — mouse + keyboard, wide layout, richer interactions than in-app. Build as a **DevTools extension** (Flutter/web).

`Flutter Radar — DevTools.dc.html` is the interactive reference; `support.js` is **preview-only — do not ship.** Designed at **~1320px** wide (the panel is fluid; the inner shell maxes at 1320).

The capture → act → capture → **diff** flow is the spine of this surface. The wide tables here are the **full** versions that the phone collapses.

---

## Shell
- **DevTools tab strip** (context only): faux DevTools tabs (Inspector, Performance, Memory, **Radar** active w/ green underline + glyph, Network, Logging). In the real extension this is provided by DevTools — match the active-tab treatment.
- **Connection bar**: a **connection chip** (button — toggle to demo `VM connected` ↔ `disconnected`; connected = green with live pulse, disconnected = red), the app/build (`leaky_chat (debug)`), the isolate (`main · isolate#1`), and right-aligned heap size + uptime. This is the "which app/isolate, live or disconnected" header.
- **Body** = left rail (198px) + main pane.

## Left rail (domain nav)
Grouped buttons; active = green text on `rgba(47,227,155,0.1)`:
- **MEMORY**: Snapshot & diff · Class histogram · Retaining paths
- **PERFORMANCE**: Traces · Frames
- **STABILITY**: Errors · Stalls
- Footer: "debug / profile only · no-op in release".

## Memory ▸ Snapshot & diff — the spine
Toolbar: a primary **Capture** button (label changes by step), **Force GC**, a **New diff** reset (when applicable), and a right-aligned **stepper spine**: ① Capture A › ② Exercise app › ③ Capture B › ④ Diff (done steps fill green, current is white-ringed).

Flow states (the Capture button advances them; captures show a **loading spinner** with a label):
1. **empty** → centered call to action: "Capture → act → capture → diff" with explanation. Button: "Capture snapshot".
2. **loadingA** → spinner "Capturing baseline heap snapshot…".
3. **baseline** → a "SNAPSHOT A · BASELINE" card (38.2 MB · 142 classes · time) + "Now exercise the app" guidance. Button: "Capture again & diff".
4. **loadingB** → spinner "Capturing & diffing…".
5. **diffed** → the **diff view** (below). "New diff" resets to empty.

### Diff view (the payoff)
Split: **growth table** (left) + **retaining-paths panel** (right, 360px).
- Table header strip: "A 38.2 MB → B 46.7 MB" + "Δ +8.5 MB" (red) + a search field (filter class / library).
- **Sortable columns** (default sort Δ bytes desc): **class · library · Δ inst · Δ bytes · live**. Growth is red, shrinkage green (note the `String -220 / -180 KB` row — diffs go both ways; show honestly).
- Rows ranked by Δ bytes; selecting a row marks it (green left border + tint) and populates the right panel.
- **Right panel** (per selected class): class name, Δ inst / Δ bytes tiles, and the **retaining path with source locations** (`GC root · static` → `_ChatService._activeRooms` → `chat_service.dart:41:7` → `_GrowableList [+12]` → **{Class}** `chat_room.dart:18:9 · retained`). Empty prompt when nothing selected.
- This satisfies "per-class growth deltas (instances + bytes, ranked) + retaining paths for the grown classes."

## Memory ▸ Class histogram
Full per-class table: **class · instances · bytes · % of heap** (with a proportional bar; bars color-grade by size). Sortable headers (instances/bytes), search field. This is the "full per-class instance/byte table" view, separate from the diff.

## Memory ▸ Retaining paths
A standalone list of retaining-path cards for the grown classes (class + delta + library + the `GC root → chain → class` line + source locations). Picked from the latest diff. (In-app the path is per-finding; here they're collected.)

## Performance ▸ Traces — the FULL wide table (priority redesign)
This is where every column the brief asks for lives (the phone collapses to a subset). Header: title + quick-filter chips (**all · hot / dup · errors**) + search ("filter operation / category").
- **Sortable columns**: **operation · count · avg · p50 · p95 · p99 · max · total · intvl · rate · err**. Active sort = green + ↓/↑.
- **Rows** (dense grid, tight): an **active pulse dot** + operation (mono) + category + **HOT** tag (duplicate-suspect); then right-aligned tabular numerals — count, **avg (bold)**, p50, p95, p99, max, **total (cyan)**, **avg inter-call interval**, **call rate (derived)**, **error count** (red if >0).
- **Duplicate-call detection**: `hot` = high count + tight inter-call interval (e.g. `scroll.layout`, `json.decode`, `db.query`); surfaced by the HOT tag and the "hot / dup" filter.
- Rows are clickable (detail = same content as the in-app trace detail: distribution histogram, slowest exemplars, inter-call timeline, parent/child span tree — see `inspector/README.md`). In the prototype a row tap fires a placeholder toast; build the full detail panel in the extension.
- **Acceptance criteria for this view** (from the brief): more data per row ✓, sorting ✓, search ✓, duplicate detection ✓, avg inter-call distance ✓, count + averages ✓, compact layout ✓.

## Performance ▸ Frames
Stat tiles (Jank frames · Jank % · build p50/95/99 · raster p50/95/99) + a **frame-time bar timeline** (over-budget bars amber/red) + a **worst recent frames** list (id · total · build/raster breakdown · cause).

## Stability ▸ Errors
Full table: **message · type · last seen · count** (×repeats). Headers, sortable in the extension; rows clickable to a stack-trace detail.

## Stability ▸ Stalls
Stall rows: **duration** (color-graded) · cause + proportional bar · time. Over the 250ms watchdog threshold.

## States (present / to build)
- **empty** (no snapshot), **loading** (capturing spinner), **diffed** (data), **disconnected** (connection chip toggle) are all live in the prototype.
- **not-measured**: mirror the in-app Startup pattern if/when a Performance ▸ Startup view is added here.
- Searching any table to zero should show an empty state (phone shows this; replicate in the extension).

## Responsive note (narrow ↔ wide)
- This wide layout is the reference for **tablet** too — at tablet width, drop the lowest-priority Traces columns (p50, p99, rate) first and let the rail collapse to icons; keep avg/p95/total/intvl/count/err.
- The **phone** versions (in `inspector/`) are the fully-collapsed end of the same tables — 2-line rows + drill-down. Implement the same data model behind both; vary only the column projection by width.

## Tokens specific to this surface
- Shell `#0c1012`; rail `#0a0e0f`; table header `#0b0f11`; cards `#0e1316`; code `#06090a`.
- Rows ~34–38px, 8px vertical padding, 1px hairline separators, no per-row cards in tables.
- All numerics tabular mono; sort arrows ↓/↑ in `#2fe39b`; active pulse + connected dot animate (disable under reduced-motion).

## Files
- `Flutter Radar — DevTools.dc.html` — interactive reference (capture→diff flow, histogram, retaining paths, full Traces table, Frames, Errors, Stalls, connection states).
- `support.js` — preview runtime. **Do not ship.**
