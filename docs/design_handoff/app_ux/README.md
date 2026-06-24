# Handoff: Flutter Leak Radar — In-App (On-Device) UX

## Overview
This is the **UI the Flutter library renders on a real device** while profiling a running app — the surface engineers will build in Dart/Flutter. It is distinct from the marketing landing page (in `../landing_page/`). The prototype covers the full on-device flow:

1. **Overlay badge** — a draggable pill floating over the host app (live worst-severity + count). Tap to open findings.
2. **Findings** — the list of leaking classes with severity, growth delta, live count, sparkline, filter chips, scan controls.
3. **Finding detail** — one class: severity, growth chart across captures, retaining-path tree, tracking status, heap-snapshot capture.
4. **Settings** — overlay toggle, report threshold, auto-scan mode, precise opt-in tracking.
5. **Export sheet** — bottom sheet to export findings as JSON or Markdown and share.

## About the Design Files
`Leak Radar — App UX.dc.html` is a **high-fidelity, interactive design reference** authored in HTML (it mounts inside an Android device frame, `android-frame.jsx`, purely for presentation). `support.js` and `android-frame.jsx` are **preview-only scaffolding — do not ship them.** Rebuild these screens as **Flutter widgets** in the package, using Flutter idioms (`OverlayEntry`/`Overlay` for the badge, `Navigator`/routes or a dedicated inspector route for the screens, `showModalBottomSheet` for export, `CustomPaint` for sparklines/charts).

The device frame in the prototype is just a viewport — ignore the Material status bar / gesture pill; they are the harness, not part of the design.

## Fidelity
**High-fidelity (hifi).** Exact colors, type, spacing, copy, and interactions are specified below. Match them. The only thing left open is Flutter-implementation specifics (widget choice, state management) — use the package's own conventions.

---

## Global layout & chrome (every Leak Radar screen)
- **Screen background**: `#0a0d0e` (host-app screen uses `#0f1316`).
- **App bar**: sticky top, background `#0c1012`, bottom border `1px solid rgba(255,255,255,0.07)`, padding ~13–14px. Contains a 34px back/icon button (radius 9px, bg `rgba(255,255,255,0.05)`, border `rgba(255,255,255,0.09)`, glyph color `#cdd6da`), a title, and trailing action icons.
- **Title type**: Space Grotesk 600, 16–17px; on detail the title is the class name in JetBrains Mono 14px 600 (ellipsis-truncated).
- **Scroll**: content area scrolls under the sticky app bar; bottom action bars are sticky with a fade gradient (`linear-gradient(180deg, rgba(10,13,14,0), #0a0d0e 30%)`).
- **Severity token mapping** (used everywhere):
  - critical → text `#ff5d6c`, tag-bg `rgba(255,93,108,0.12)`, tag-border `rgba(255,93,108,0.3)`, row-bg `rgba(255,93,108,0.05)`, row-border `rgba(255,93,108,0.18)`
  - warning → `#f5b54a`, `rgba(245,181,74,0.12)`, `rgba(245,181,74,0.3)`
  - info → `#5ad1e6`, `rgba(90,209,230,0.12)`, `rgba(90,209,230,0.3)`
  - severity labels are uppercased mono (`CRITICAL`/`WARNING`/`INFO`), 9.5–11px, letter-spacing 0.05em, padded pill radius 5–7px.

---

## Screen 1 — Overlay badge (over host app)
- **Purpose**: ambient, always-visible signal that floats over the developer's running app; the entry point to findings.
- **Host app** (the thing being profiled — shown for context, NOT part of Leak Radar): a chat screen — app bar (back chevron, 34px circular avatar gradient `135deg,#2a6df4,#5ad1e6` with initials, title "Support · #general" 600/15px, online count `#5fb98e` 12px, overflow ⋮), message bubbles (incoming `#1b2227` radius `14px 14px 14px 4px`; outgoing `#234b3a` radius `14px 14px 4px 14px`; 13.5px), and a composer bar (rounded input + 38px send circle `#2a6df4`).
- **The badge** (this IS Leak Radar):
  - Pill: `display:inline-flex`, gap 8px, padding `9px 13px`, radius 999px.
  - Background `rgba(255,93,108,0.18)`, border `1px solid rgba(255,93,108,0.55)`, `backdrop-filter: blur(8px)`, shadow `0 10px 26px -8px rgba(255,93,108,0.5)`.
  - **Color reflects worst current severity** (here red/critical). Content: a small radar glyph (white), the count + word ("3 leaks", JetBrains Mono 13px 600 `#fff`), and a `⠿` drag-handle glyph at 55% opacity.
  - A subtle pulse ring animation (`box-shadow` expand/fade, ~2.6s) — disable under reduced-motion.
  - **Draggable** anywhere on screen (`cursor:grab`, `touch-action:none`); a tap that isn't a drag opens Findings. In Flutter: `Draggable`/`GestureDetector` inside an `OverlayEntry`; distinguish tap vs drag with a small movement threshold (~4px).
- Collapsed→expanded: tapping navigates to the Findings screen.

## Screen 2 — Findings
- **Purpose**: triage every class that's growing. Scan controls live here.
- **App bar**: radar glyph + "Leak Radar" (Space Grotesk 600/17px) + two 34px trailing buttons — Export (upload icon) and Settings (gear icon).
- **Summary row** (under title, JetBrains Mono 11.5px): colored dot counts — "● 2 critical" `#ff5d6c`, "● 2 warning" `#f5b54a`, "● 1 info" `#5ad1e6`, and right-aligned "scan 14:32" `#7d8e94`.
- **Filter chips** (horizontal scroll, 11.5px mono): active "All · 5" (bg `#2fe39b`, text `#0a0d0e`, 600); inactive (text `#c4d0d4`, bg `rgba(255,255,255,0.05)`, border `rgba(255,255,255,0.08)`): "Growing", "Critical", "Tracked". Radius 8px.
- **Finding rows** (list, gap 8px, each a tappable button → detail):
  - Layout: `flex`, gap 12px, padding 13px, radius 14px. Critical rows get the tinted bg+border above; others bg `rgba(255,255,255,0.018)`, border `rgba(255,255,255,0.06)`.
  - 5px rounded color bar (severity color) on the left.
  - Top line: class name (JetBrains Mono 13px `#e7eef0`, ellipsis) + growth delta (mono 13px 600, severity color, e.g. `+48`).
  - Bottom line: severity tag pill + "{n} live" (mono 11px `#5f7178`) + a **sparkline** (76×22 SVG, severity-colored, 1.6px stroke) + a `›` chevron.
  - Data shown (in order): `ChatRoomController` critical +48 / 48 live; `HeartbeatTimer` critical +5 / 7 live; `VideoPlayerController` warning +6 / 12 live; `DashboardBloc` warning +2 / 4 live; `_PresenceSubscription` info +3 / 9 live.
- **Bottom action bar** (sticky): left "5 classes · 80 instances" (mono 11px `#5f7178`); right **Scan now** button (mono 13px 600, bg `#2fe39b`, text `#0a0d0e`, radius 12px, refresh icon, shadow `0 8px 22px -8px rgba(47,227,155,0.5)`). Tapping shows a confirmation toast.

## Screen 3 — Finding detail
- **Purpose**: everything about one leaking class.
- **App bar**: back chevron + class name (mono 14px 600) + Export icon.
- **Severity strip**: severity tag pill + "grew +48 over 8 captures" (mono 12px `#7d8e94`).
- **Three stat cards** (equal flex, bg `#0e1316`, border `rgba(255,255,255,0.07)`, radius 13px): "Live now" (value in severity color), "Net growth", "First seen" — values in Space Grotesk 600/24px, labels mono 11px `#5f7178`.
- **Growth chart card**: title "Live instances / capture" (Space Grotesk 600/13.5px) + "never returns ↑" (mono 11px, severity color). A bar chart — equal-width bars, gap 6px, 96px tall, rising heights; the **last bar uses the severity color**, the rest `rgba(255,255,255,0.12)`; radius `4px 4px 0 0`. X labels mono 9.5px: "14:09 / forced GC between captures / 14:32".
- **Retaining-path card**: header link icon (cyan) + "Retaining path" + "lazily fetched" (mono 10px `#5f7178`). Body is a mono 12px tree (line-height 2) on `#06090a`: `GC root (static field)` → `_ChatService._activeRooms` → `_GrowableList [3]` → **{ClassName} ← leaked** (leaf in severity color, "← leaked" in `#4a5a60`). Tree connectors `└─` in `#4a5a60`, field names `#c3e88d`, types `#5ad1e6`.
- **Bottom row** (two cards): "Heap-inspected · no opt-in needed" status (grey dot) + a **Capture .dartheap** button (bg `rgba(90,209,230,0.06)`, border `rgba(90,209,230,0.25)`, cyan text + file icon). Capture shows a toast with a generated filename.

## Screen 4 — Settings
- **Purpose**: tune what gets reported and when.
- Sections, each with a mono 10.5px uppercase label `#5f7178`:
  - **Overlay** — a row card (bg `#0e1316`, radius 13px) "Draggable badge / Live worst-severity + count over your app" with a **toggle switch** (track 44×26, on `#2fe39b` / off `rgba(255,255,255,0.14)`, 20px white knob, 0.2s transition).
  - **Report threshold** — a 3-segment control (Info / Warning / Critical) inside a `#0e1316` rounded container. Active segment fills with its severity color (`#5ad1e6` / `#f5b54a` / `#ff5d6c`), text `#0a0d0e` 600; inactive text `#8fa0a6`. Below: a one-line hint that changes per selection:
    - Info → "Report everything, including small or expected growth."
    - Warning (default) → "Report classes growing past the warning band (default)."
    - Critical → "Only surface runaway growth that never returns."
  - **Auto-scan** — three radio rows (bg `#0e1316`, radius 12px; selected row border `rgba(47,227,155,0.5)`, others `rgba(255,255,255,0.07)`): "Manual only / Scan when you tap Scan now", "Periodic · every 30s / Background heap captures on a timer", "On screen-pop / NavigatorObserver scans when a route pops" (this one carries a green `RECOMMENDED` tag; it's the default selection). Radio dot: 16px, 2px ring in green when selected with inner `#0e1316` gap.
  - **Precision** — a row card "Precise opt-in tracking / Honor track() / markDisposed() calls" with a toggle (off by default).
- **Footer note** (mono 10.5px `#3d4a4f`, centered): "Debug & profile only · no-op in release" / "Never throws · never measurably slows the host".

## Screen 5 — Export sheet (modal bottom sheet)
- Triggered by the Export icon on Findings or Detail. Scrim `rgba(0,0,0,0.55)`; tapping outside closes.
- Sheet: bg `#0e1316`, top border `rgba(255,255,255,0.1)`, radius `22px 22px 0 0`. Grab handle (38×4 `rgba(255,255,255,0.18)`).
- Title "Export findings" (Space Grotesk 600/18px) + subtitle "Share straight from the device — into a bug, a PR, a thread." (`#7d8e94` 13px).
- **Format toggle**: 2-segment (JSON / Markdown), active fills `#2fe39b`. Markdown is default.
- **Preview** `<pre>` (mono 11.5px, bg `#06090a`, max-height ~150px) showing the chosen format's output (a JSON object of findings, or a Markdown table).
- **Share button** (full-width, bg `#2fe39b`, `#0a0d0e` text, radius 13px, upload icon): "Share .md" / "Share .json".

---

## Interactions & Behavior
- **Badge**: draggable (clamp within screen), tap (non-drag) → Findings; pulse animation (reduced-motion: none).
- **Navigation**: badge→findings; row→detail; back chevrons→findings; gear→settings; export icon→bottom sheet.
- **Scan now / Capture .dartheap**: show a transient toast (~1.9s) bottom-center (bg `#2fe39b`, `#0a0d0e`, mono 12px). Messages: "Heap captured · 5 findings", "Saved leak_radar_14-32.dartheap".
- **Settings controls**: all live-toggle local state (switches, threshold segments, scan radios, precise toggle).
- **Export**: format toggle swaps the preview and the share-button label.
- **Sparklines & growth bars**: in Flutter use `CustomPaint`. The website draws them in on scroll; on device they can simply render (optionally a short grow-in on transform/opacity).

## State Management
Local UI state (no backend in the prototype):
- `screen`: host | findings | detail | settings
- `sheet`: bool (export open)
- `selIdx`: which finding is in detail
- `badge`: {x, y} drag position; `overlay`: bool
- `precise`: bool; `thresh`: info|warning|critical; `scan`: off|periodic|pop; `fmt`: json|markdown
- transient `toast` string

In the real library, findings come from the runtime detector (per-class live-instance counts across forced-GC captures via the Dart VM service); retaining paths are **lazily fetched** on detail open; export serializes the current findings set.

## Responsive behavior
This surface is phone-first (designed at 412×858 logical). It must adapt to varying device sizes — use Flutter's normal flexible layouts. The badge stays within safe-area bounds; the overlay must never block the host app's critical controls (draggable so the user can move it).

## Design Tokens
Same palette/type as the shared language in `../README.md`. Surface-specific:
- Surfaces: screen `#0a0d0e`; host-app `#0f1316`; cards `#0e1316`; app bar `#0c1012`; code/preview `#06090a`.
- Icon buttons: 34px, radius 9px, bg `rgba(255,255,255,0.05)`, border `rgba(255,255,255,0.09)`.
- Radii: pills 999px; cards 13–15px; sheet top 22px; chips/tags 5–8px; buttons 12–13px.
- Switch: track 44×26 r13, knob 20px; transition 0.2s.

## Assets
- **No raster images.** Radar glyph, icons (Feather/Lucide stroke style, ~2px), sparklines and bar charts are all SVG/`CustomPaint`. Replace icons with the package's chosen icon approach.
- **Fonts**: Space Grotesk, Hanken Grotesk, JetBrains Mono. In Flutter, bundle these (e.g. `google_fonts` or asset fonts). For an actual dev-tool overlay, JetBrains Mono for metrics/code is the important one; system font is acceptable for body if bundling all three is undesirable.
- **One emoji** (`👀`) appears only in the *host app* mock chat — it is not part of Leak Radar's UI.

## Files
- `Leak Radar — App UX.dc.html` — the interactive prototype (all 5 surfaces + navigation). **Reference only.**
- `android-frame.jsx`, `support.js` — preview harness. **Do not ship.**
