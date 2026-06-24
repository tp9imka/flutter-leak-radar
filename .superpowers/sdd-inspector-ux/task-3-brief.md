# Task 3 Brief — Swipe-to-Dismiss Finding Rows

## Context
Package `packages/flutter_leak_radar` in repo
`/Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar`.
Branch: `feat/inspector-clear-and-swipe` (already checked out). Commit there.

## Files to read BEFORE writing anything
1. `packages/flutter_leak_radar/lib/src/ui/leak_radar_screen.dart`
2. `packages/flutter_leak_radar/test/ui/leak_radar_screen_test.dart`
3. `packages/flutter_leak_radar/lib/src/model/leak_finding.dart` (for LeakFinding fields)
4. `packages/flutter_leak_radar/lib/src/ui/theme/theme.dart` (for color tokens)

## Required changes

### A) Add screen-local dismissed set to `_LeakRadarScreenState`
In `_LeakRadarScreenState`, add:
```dart
// Tracks classes dismissed by swipe in the current view. The engine still
// detects these leaks — a fresh scan re-adds them if still leaking.
final Set<String> _dismissed = {};
```

### B) Gate `_filtered` to exclude dismissed items
Change the existing `_filtered` getter to also exclude dismissed class names:
```dart
List<LeakFinding> get _filtered {
  final findings = _report?.findings ?? const <LeakFinding>[];
  final base = switch (_activeFilter) {
    _Filter.all => findings,
    _Filter.critical =>
      findings.where((f) => f.severity == LeakSeverity.critical).toList(),
    _Filter.growing => findings.where((f) => f.growth > 0).toList(),
    _Filter.tracked => findings.where((f) => f.tag != null).toList(),
  };
  return base.where((f) => !_dismissed.contains(f.className)).toList();
}
```

### C) Clear `_dismissed` whenever a new report arrives
In `_scan()`, after `setState(() { _report = report; _scanning = false; })`,
add `_dismissed.clear()` inside the same `setState` call so a fresh scan
re-shows previously swiped rows.

Also clear `_dismissed` when `_LeakRadarScreenState.initState` gets a new
report (but `initState` only seeds from `LeakRadar.latest` — no change
needed there since `_dismissed` starts empty).

Wait — `_scan()` already sets `_report`. Change:
```dart
setState(() {
  _report = report;
  _scanning = false;
});
```
to:
```dart
setState(() {
  _report = report;
  _scanning = false;
  _dismissed.clear(); // fresh scan re-shows swiped rows
});
```

### D) Wrap `_FindingRow` in a `Dismissible`
In the `ListView.builder` itemBuilder in `build()`, replace:
```dart
itemBuilder: (_, i) => _FindingRow(finding: filtered[i]),
```
with:
```dart
itemBuilder: (_, i) {
  final f = filtered[i];
  return Dismissible(
    key: ValueKey('${f.className}|${f.kind.name}|${f.tag ?? ''}'),
    direction: DismissDirection.endToStart,
    // View-level dismiss: engine still detects; re-adds on next scan.
    onDismissed: (_) =>
        setState(() => _dismissed.add(f.className)),
    background: _DismissBackground(),
    child: _FindingRow(finding: f),
  );
},
```

### E) Add `_DismissBackground` private widget
Add this private widget at the bottom of `leak_radar_screen.dart` (before
or after `_EmptyState`):
```dart
class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(239, 68, 68, 0.18),
          border: Border.all(
            color: const Color.fromRGBO(239, 68, 68, 0.40),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: Color.fromRGBO(239, 68, 68, 0.80),
          size: 20,
        ),
      );
}
```

## Semantics note (required short comment near onDismissed)
Add this ONE-LINE comment before `onDismissed`:
```dart
// View-level dismiss: engine still detects; re-adds on next scan.
```

## Tests to write

File: `packages/flutter_leak_radar/test/ui/leak_radar_screen_test.dart`

Add a `group('swipe-to-dismiss', ...)`:

1. `swiping a finding row removes it from the displayed list` —
   Seed 3 scans with `HomeBloc` growing. Pump `LeakRadarScreen`.
   Assert `HomeBloc` visible. Use `tester.drag(find.text('HomeBloc'), const Offset(-500, 0))` then `pumpAndSettle()`. Assert `find.text('HomeBloc')` is gone. Assert `find.text('No leaks detected')` is visible.

2. `a new scan re-adds a dismissed finding if still leaking` —
   Seed 2 scans with `HomeBloc`. Pump screen. Swipe `HomeBloc` away. Assert gone.
   Then tap the Scan now button (`find.byKey(const Key('leak_radar_scan_btn'))`).
   `pumpAndSettle()`. Assert `HomeBloc` is visible again.
   
   IMPORTANT: The `FakeHeapProbe` queue will have been consumed after 2 scans
   for history, leaving 1 more snapshot in the queue for the 3rd scan triggered
   by the button tap. Seed 3 snapshots total: `snap({'HomeBloc': 1})`,
   `snap({'HomeBloc': 2})`, `snap({'HomeBloc': 3})` — the first two via
   `await LeakRadar.scan()` calls (pre-seed), the 3rd used by the button.
   After 3 scans total (2 pre-seeded + 1 from button), there will be a
   growth finding for `HomeBloc`.

## Global constraints
- Hand-rolled immutable (no freezed); minimal comments (only the one listed above and any non-obvious); lines ≤ 80 chars; no `print`; null safety: no `!`; `const` wherever possible.
- SEMANTICS: swipe-to-dismiss is VIEW-LEVEL only — do NOT attempt to permanently remove from the engine. The comment documents this.

## TDD order
1. Read all files listed above
2. Write tests FIRST (they will fail — `Dismissible` doesn't exist yet)
3. Run tests (RED)
4. Implement A → B → C → D → E
5. Run tests (GREEN)
6. Run `flutter analyze packages/flutter_leak_radar` (must be clean)
7. Commit with message: `feat(ui): swipe-left dismissible finding rows (view-level)`

## Report contract
Write your report to:
`/Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/.superpowers/sdd-inspector-ux/task-3-report.md`

Return status, commit hash, one-line test summary, and any concerns.
