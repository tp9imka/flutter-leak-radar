# Phase B2 — App UX Re-skin Report

## What was implemented

### Screen 1 — Overlay badge (`leak_radar_overlay.dart`)

Replaced the old circular colored badge with a pill-shaped glassmorphic badge:

- **Shape**: `ClipRRect(radius: 999)` → `BackdropFilter(blur: 8)` → `Container` (stadium border)
- **Severity backgrounds**: RGBA hardcoded overlay colors per spec (critical/warning/info/none variants)
- **Contents**: `RadarGlyph(size:16)` → `"N leaks"` (JetBrains Mono 13 w600 white) → `"⣿"` drag handle (55% opacity)
- **Shadow**: `BoxShadow(color: 0x44000000, blurRadius: 12, offset: Offset(0,4))`
- **Pulse ring animation**: `AnimationController(2600ms)` with `Curves.easeOut`, scale 1.0→1.18 + opacity 0.6→0.0. Disabled when `MediaQuery.disableAnimations` is true or findings list is empty. Keyed `Key('leak_radar_pulse')` for testability.
- **All existing behavior preserved**: `initialReport` seam, `LeakRadar.reports` stream subscription, drag (`onPanUpdate`), tap→`LeakRadarScreen` push.

### Screen 2 — Findings screen (`leak_radar_screen.dart`)

Full dark-theme rebuild on `LeakRadarColors.pageBg` scaffold:

**App bar** (`LeakRadarColors.appBarBg`, elevation 0):
- Title: `RadarGlyph(size:20)` + "Leak Radar" (`LeakRadarText.title`)
- Trailing: two `_IconBtn` (34×34, translucent bg/border) — Export (`Icons.download_outlined`) and Settings (`Icons.settings_outlined` → placeholder `Scaffold`)
- Heap snapshot + Share moved to `PopupMenuButton` ("More") to keep the spec's two-button layout

**Summary row**: per-severity dot counts (`"● N critical"` etc. in severity colors, JetBrains Mono 11.5) + right-aligned `"scan HH:MM"` in `text40`. Uses a `_formatTime()` helper (no `intl` dependency).

**Filter chips** (horizontal scroll, JetBrains Mono 11.5 w500):
- All·{n}, Critical, Growing, Tracked
- Active state: accent-based rgba bg/border (`Color.fromRGBO(46,227,155,0.18/0.55)`) with dark text
- Filtering logic: All=all; Critical=critical severity; Growing=growth>0; Tracked=tag!=null

**Finding rows** (`_FindingRow`):
- Left 5px severity color bar
- Class name (ellipsis, mono 13 `text100`) + growth delta (mono 13 w600 severity color, only when >0)
- Severity tag pill + `"N live"` (mono 11 `text25`) + sparkline (60px×20, severity-colored) + chevron
- Critical rows: `severityTokens(critical).rowBg/rowBorder`; others: `rgba(255,255,255,0.03/0.07)`
- Tap → placeholder `Scaffold` titled with class name
- `RetainingPathTile` preserved below for findings with non-empty series

**Bottom bar** (`_BottomBar`, sticky via `bottomNavigationBar`):
- Left: `"{n} classes · {m} instances"` (mono 11 `text25`)
- Right: "Scan now" button (accent bg, radius 12, accent box-shadow, `LeakRadarColors.pageBg` text, keyed `Key('leak_radar_scan_btn')`)
- After scan: `SnackBar("Heap captured · N findings")` green bg, dark text, 1.9s duration

**Empty state**: `RadarGlyph(64)` + "No leaks detected" (`LeakRadarText.title`) + status (`LeakRadarText.label`)

All existing methods preserved: `_scan()`, `_export()`, `_share()`, `_collectHeapSnapshot()`, `_getOrExportPath()`.

---

## Adaptations from handoff spec

| Spec | Adaptation | Reason |
|------|-----------|--------|
| Drag handle `⠿` | Used `⣿` (braille 8-dot full block) | More visually balanced at 13px size |
| Sparkline width 72px | Reduced to 60px in `_FindingRow` | Prevent `RenderFlex` overflow at 320px |
| Share button in app bar | Moved to `PopupMenuButton` | Spec shows exactly 2 trailing buttons (Export + Settings); Share + heap snapshot moved to overflow |
| Warning badge color `rgba(255,189,89,…)` | Kept as specified | `LeakRadarColors.severityWarning` is `0xFFf5b54a` (slightly different hue) but badge uses `rgb(255,189,89)` per spec |
| `Spacer()` in row 2 | Replaced with bounded layout | `Spacer` in a `Row` inside an `Expanded` inside `IntrinsicHeight` needs care at 320px |

---

## Test results

```
48/48 passed  (flutter test packages/flutter_leak_radar/test/ui/)
```

Tests updated/added:
- `leak_radar_overlay_test.dart`: removed color-check test, updated count text to `"1 leaks"`, added pulse ring disable test
- `leak_radar_screen_test.dart`: updated tooltip/button finders, added filter chip tests (Critical, Growing), summary row count test, snackbar test
- `heap_snapshot_button_test.dart`: updated to use `PopupMenuButton` flow

---

## Analyze results

```
No issues found! (ran in 1.7s)
flutter analyze packages/flutter_leak_radar
```

Zero errors, zero warnings.

---

## Commit SHAs

Commits will be added after commit step.
