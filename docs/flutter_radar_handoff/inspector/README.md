# Handoff: Flutter Radar — In-app Inspector (narrow phone)

The on-device surface, built as **Flutter widgets inside the running app**. Two parts: an always-on **overlay badge** floating over the host app, and a full-screen **Inspector** with three tabs.

`Flutter Radar — Inspector.dc.html` is the interactive reference. `android-frame.jsx` + `support.js` are **preview-only harness — do not ship.** The Android frame is just a viewport; ignore its status bar / gesture pill.

Implementation mapping (Flutter): badge = `OverlayEntry` + `Draggable`/`GestureDetector`; Inspector = a route/`Overlay` with a `TabBar`; bottom sheets = `showModalBottomSheet`; sparklines/charts/bars = `CustomPaint` or thin `Container` bars; tables = `ListView` with `Row`s (tabular-figure mono).

Designed at **412dp** wide. All tables here are already in their **narrow/collapsed** form (2-line rows + drill-down). The full multi-column versions live in the DevTools companion — that IS the responsive story: narrow collapses, wide expands.

---

## A. Overlay badge (always-on, draggable)
- A compact pill floating over the app, color = **worst current severity** across all three domains. Three demo states (switch via the on-canvas control):
  - **clean** — green `rgba(47,227,155,0.16)` bg / `0.5` border, text "All clear", no animation.
  - **warning** — amber, text "3⚠  ▲8%".
  - **critical** — red, text "15⊘  ▲jank  2!", with a `rdr-pulse` ring animation.
- Anatomy: blur-backed pill, radius 13px, padding 8×12, a small radar glyph + mono 12.5px count string. `cursor:grab`, `touch-action:none`.
- **Draggable** anywhere (clamped to safe area — must never slide under a notch/home indicator). Movement threshold ~5px distinguishes drag from tap.
- **Tap** → opens the Inspector (Leaks tab).
- **Long-press (~480ms)** → a quick-action menu: **Force GC**, **Scan now**, **Open Leaks**, **Open Performance**. (Centered popover in the prototype; in-app, anchor near the badge.)
- The host app behind it (a chat screen) is only context — not part of Radar.

## B. Inspector chrome
- **App bar** (`#0c1012`, bottom hairline): radar glyph + "Flutter Radar" (Space Grotesk 600/15.5px), trailing **Export** (upload icon) and **Close** (✕) 31px icon buttons (radius 8, bg `rgba(255,255,255,0.05)`, border `rgba(255,255,255,0.09)`).
- **Tab bar**: three segmented tabs, each a colored severity dot + label (+ a count badge on Leaks/Stability). Active tab: bg `#151c20`, border `rgba(255,255,255,0.14)`, text `#e7eef0`. Inactive: transparent, `#7d8e94`.
- Body scrolls; sticky sub-headers and bottom action bars.

## B1. Leaks tab — PRIMARY surface
- **Summary row**: severity counts ("3 critical · 3 warning · 2 info", each in its color) + a right-aligned **VM-connection chip**. Must wrap gracefully as counts grow.
- **VM-connection chip** is a button that **cycles** through the states (tap to demo): `VM connected` (green, live pulse) → `no service URI` → `refused by DDS` → `socket error` → `disabled`. Any degraded state shows a banner under the row with the **reason** and the **fallback** ("Fell back to an on-device heap snapshot"). This is the honest-metrics requirement — never hide why data is degraded.
- **Toolbar**: a mono search field ("filter class / library / kind") + a **Sort** button that reveals sort chips: **severity / growth / live count / name**.
- **Kind quick-filters** (horizontal scroll chips): all · not disposed · not gc'd · retained · growth. Active chip fills green.
- **Findings list** — dense 2-line rows (radius 11px; critical rows get a faint red bg+border, others `rgba(255,255,255,0.018)`):
  - left 4px severity bar (full row height),
  - line 1: class name (mono 13px, ellipsis) · growth delta (mono 12.5px 600, severity color, e.g. `+48`) · a 52×16 **sparkline** (severity color),
  - line 2: a **kind tag** pill (`NOT DISPOSED` / `NOT GC'D` / `RETAINED` / `GROWTH`) · "{n} live" · owning library (mono, muted) · `›`.
  - Tap → leak detail.
- **Empty state** when search matches nothing: centered glyph + "No findings match …".
- **Bottom action bar** (sticky, fades in): "{n} classes · {n} instances · last scan {time}" + **Force GC** (cyan ghost) + **Scan now** (green, refresh icon). Both fire a confirmation toast.
- The 8 findings, kinds, severities, live counts, growth, libraries are all in the prototype data — use them as the realistic example set.

### Leak detail (drill-down) — the centerpiece
Full-screen overlay (back ‹ + class name + Export). Top→bottom:
1. **Severity strip**: severity tag + kind label + library.
2. **Two stat tiles**: "Live now" (value in severity color) · "Net growth".
3. **Growth series chart**: "Live instances / scan" — a bar chart across recent scans; last bar uses the severity color, rest `rgba(255,255,255,0.12)`; caption "forced GC between scans". This is the "grows and never returns" signal.
4. **Retaining path** card: "lazily fetched" note; a mono tree on `#06090a`: `GC root · static field` → `_ChatService._activeRooms  chat_service.dart:41:7` → `_GrowableList [3]` → **{Class} ← leaked**. Connectors `└─` muted, field names `#c3e88d`, source locations `file:line:col` faint. **Source locations are required.**
5. **Allocation stack** card ("if captured"): mono frames with `file:line` — function names in `#82aaff`.

## B2. Performance tab — sub-tabs: Traces · Frames · Rebuilds · Startup
Sticky sub-tab bar (same active treatment as main tabs).

### Traces (priority redesign)
On phone this is a **dense 6-ish-column collapse** of the full table (the full 11-column table is in DevTools). Header has search ("filter operation / category") + quick-filter chips **all · hot / dup · errors**.
- Sticky **column header** is sortable — columns: **op · count · avg · p95 · total · intvl**. Active sort key is green with ↓/↑.
- **Rows** (grid, tight 8px padding): op name (mono 12px) + a small **HOT** tag for duplicate-suspect keys + category + an "{n} err" marker on line 2; then right-aligned tabular: count, **avg (prominent, bold white)**, p95, **total (cyan)**, interval.
- **Duplicate-call detection**: keys fired suspiciously often / at a tight inter-call interval carry the amber **HOT** tag and surface via the "hot / dup" quick filter.
- Tap row → trace detail.
- (Full column set — count, avg, p50, p95, p99, max, total, avg inter-call interval, call rate, errors, last-seen/active — is specified on the DevTools side; the phone shows the high-value subset and defers the rest to the detail + the wide view.)

#### Trace detail (drill-down)
Category + **HOT/DUPLICATE** tag + "{count} calls · {rate}/s". A 6-tile metric grid (avg, p95, total, p99, max, intvl). Then: **latency distribution** histogram, **slowest exemplar calls** (duration + attributes), and a **span tree / mini flame chart** (nested parent/child bars on a shared clock) for nested traces.

### Frames
Three stat tiles (Jank frames `#ff5d6c` · Jank % `#f5b54a` · Frames). A **frame-time bar timeline** (recent frames; bars over 16ms budget go amber, over a higher bar go red). Build/raster **p50/p95/p99** tiles. A **worst recent frames** list (frame id · total ms · cause).

### Rebuilds
"Rebuilds / instrumented subtree · last 60s". Per-label rows: an **EXCESSIVE** tag on flagged subtrees + label + rebuild count (red if flagged) + delta, with a proportional bar. Sortable by count.

### Startup
- **Measured**: a big "Time to first frame" headline (Space Grotesk 600/38px, green) + a stacked proportional bar of phases + a per-phase list (Engine init / Dart VM + isolate / First frame build / First frame raster, each with a color chip + ms).
- **Not measured** state (toggle in the prototype demonstrates it): a dashed ∅ marker + "Startup not measured" + guidance to initialize Radar before `runApp()`. **Never show a fabricated number.**

## B3. Stability tab — sub-tabs: Errors · Stalls
### Errors
"{distinct} distinct · {total} total" + a sort toggle (repeats ↔ time). Rows (card, red left bar): message (up to 2 lines) · type tag (amber) · last-seen time · **×{repeats}** (how many times the same error repeated) · `›`. Tap → **stack trace** detail (error card + mono stack frames).

### Stalls
"{n} stalls > 250ms threshold · main-thread watchdog". Rows: **duration** (mono 14px, color-graded by severity: >1s red, >600ms amber) · cause · time, with a proportional bar.

## Export sheet (bottom sheet)
Triggered by the Export icon (scope follows the active tab: findings / trace report / errors). Scrim + rounded-top sheet (`#0e1316`), grab handle, title "Export {scope}", **JSON / Markdown** segmented toggle, a mono **preview** `<pre>` of the chosen format, and a full-width green **Share {ext}** button (system share). Fires a toast.

## States summary (all present in the prototype)
- empty → Leaks search-to-zero; (capture flow lives in DevTools)
- loading → "Scan now" / "Force GC" toasts (scan is near-instant on device; DevTools shows the spinner)
- not measured → Startup toggle
- error/degraded → VM-connection chip cycle + banner

## Tokens specific to this surface
- App bars `#0c1012`; cards `#0e1316`; inputs `#11171a`; code `#06090a`.
- Icon buttons 31px, radius 8. Tags 9–10px mono, radius 4–6. Row radius 11. Sheet top radius 20.
- Sparkline 52×16 (list) / bars in detail. All numbers tabular mono.

## Files
- `Flutter Radar — Inspector.dc.html` — interactive reference (badge + 3 tabs + 4 perf sub-sections + all drill-downs + export + states).
- `android-frame.jsx`, `support.js` — preview harness. **Do not ship.**
