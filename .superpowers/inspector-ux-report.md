# Inspector UX Report — feat/inspector-clear-and-swipe

## Status: DONE_WITH_CONCERNS

Branch: `feat/inspector-clear-and-swipe`
Head commit: `1f4e5f3`

## Commits
```
1f4e5f3 fix(ui): clear dismissed set on clearLeaks; use secondaryBackground for endToStart Dismissible
c65ac00 fix(ui): restore 3-way empty-state condition; swipe-dismiss shows filter-empty text
3e2d13b feat(ui): swipe-left dismissible finding rows (view-level)
0663db2 feat(engine,ui): clearLeaks API and overflow menu action
9c0be1a feat(ui): capture button ripple, Expanded status card, IntrinsicHeight bottom row
```

## New Public API

### `SampleHistory.clear()` (internal)
`packages/flutter_leak_radar/lib/src/analysis/sample_history.dart`
Empties the snapshot ring buffer.

### `LeakEngine.clearLeaks()` (@internal)
`packages/flutter_leak_radar/lib/src/engine/leak_engine.dart`
Clears `_registry`, calls `_history.clear()`, sets both `_latestFullReport`
and `_latestFiltered` to an empty report, emits on `_reports` stream.
Never throws.

### `LeakRadar.clearLeaks()` (public facade)
`packages/flutter_leak_radar/lib/src/leak_radar.dart`
`static void clearLeaks()` — delegates via `runSafely`, no-op when engine
null (release / disabled). Never throws into host.

## Feature Details

### Feature 1 — Capture button ripple/pin/height
- `Material(color: transparent)` + `ClipRRect` + `InkWell(onTap: _captureHeap)`
  gives ripple clipped to the 10dp rounded rect
- STATUS card changed from `Flexible` → `Expanded` (pins left, fills)
- Outer `Row` wrapped in `IntrinsicHeight` with `crossAxisAlignment: stretch`
  so both items match height
- Inner icon+label row gets `mainAxisAlignment: center`

### Feature 2 — Clear leaks overflow menu
- "Clear leaks" added as third item in `_HeapMenuAction` + `PopupMenuItem`
- On tap: `LeakRadar.clearLeaks()` then `setState(() { _dismissed.clear(); _report = LeakRadar.latest; })`
- Engine emits empty `LeakReport(trigger: 'clear')` so any stream subscribers
  also see the cleared state

### Feature 3 — Swipe-to-dismiss rows
- Each `_FindingRow` wrapped in `Dismissible(direction: endToStart)`
- Key: `ValueKey('${f.className}|${f.kind.name}|${f.tag ?? ''}')`
- `secondaryBackground: _DismissBackground()` (red tint + delete icon)
- `background: SizedBox.shrink()` required by Flutter when secondaryBackground
  is set for a single-direction Dismissible
- `onDismissed`: adds `f.className` to `_dismissed` (view-level Set on state)
- `_filtered` getter gates out `_dismissed` entries
- `_scan()` clears `_dismissed` so a fresh scan re-shows all findings
- Semantics comment: `// View-level dismiss: engine still detects; re-adds on next scan.`
- 3-way empty-state condition preserved: `findings.isEmpty → EmptyState`,
  `filtered.isEmpty → "No findings match this filter"`, else `ListView`

## Test Counts
- Total passing: **121** (up from ~112 on main)
- New tests:
  - 2 in `_buildBottomRow` group (InkWell assertion, overflow check)
  - 3 in `LeakEngine.clearLeaks` group (emit empty report, SampleHistory.clear, facade no-op)
  - 1 in `Clear leaks` widget group (tapping menu empties list)
  - 2 in `swipe-to-dismiss` group (row disappears, re-adds on next scan)

## Analyze Result
`flutter analyze packages/flutter_leak_radar` → **No issues found**

## Concerns / Notes

1. **Branch drift during SDD**: Subagents repeatedly committed to wrong
   branches (`feat/leak-graph-phase1`, `publish/readme-and-pubignore`)
   due to the auto-mode branch-switch restriction. All commits were
   cherry-picked onto `feat/inspector-clear-and-swipe`. The other branches
   carry stray copies of these commits; clean up those branches before
   merging if desired (`git rebase -i` or `git reset --soft HEAD~N`).

2. **Dismissible empty-state text**: After swiping all visible rows, the
   screen shows "No findings match this filter" rather than "No leaks
   detected". This is the correct behavior — the engine still holds the
   findings. "No leaks detected" would be misleading. If product wants a
   distinct dismissed-all state, add it separately.

3. **`_HeapMenuAction.clearLeaks` kEngineEnabled guard**: Not added
   (consistent with `track`/`markDisposed` peers which also use
   `_engine?.method()` null-guard rather than an explicit kEngineEnabled
   check). No behavioral gap — `_engine` is null in release.
