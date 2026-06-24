# Task 1 Brief — Capture Button Ripple / Pin / Height

## Context
Package `packages/flutter_leak_radar` in repo `/Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar`.
Branch: `feat/inspector-clear-and-swipe` (already checked out). Commit there.

## File to modify
`packages/flutter_leak_radar/lib/src/ui/finding_detail_screen.dart`

Method `_buildBottomRow()` (around line 384). Currently:
- A `Row` with a `Flexible` "STATUS/Tracked" card on the left and a bare
  `GestureDetector` "Capture .dartheap" button on the right.

## Required changes

1. **Add ripple to Capture button**
   - Replace the outer `GestureDetector` with a `Material(color: Colors.transparent)` wrapping a `ClipRRect(borderRadius: BorderRadius.circular(10))` and then an `InkWell(onTap: _captureHeap, borderRadius: BorderRadius.circular(10))` inside.
   - The existing `Container` with cyan tint (`Color.fromRGBO(90,209,230,0.12)` bg, `Color.fromRGBO(90,209,230,0.30)` border) and `borderRadius: BorderRadius.circular(10)` stays as the visual decoration.
   - Keep the existing icon + label Row inside unchanged.
   - The `Material` must be color-transparent so the Container's own color shows through; the InkWell ripple clips to the border radius.

2. **Pin button to right / expand STATUS card**
   - Change `Flexible(child: Container(...STATUS...))` to `Expanded(child: Container(...STATUS...))`.

3. **Match heights**
   - Wrap the outer `Row` in `IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, ...))`.
   - Add `crossAxisAlignment: CrossAxisAlignment.stretch` to the Row itself so the Capture button stretches.
   - Inside the Capture button's Container, center the inner Row vertically: add `mainAxisAlignment: MainAxisAlignment.center` to the inner Row (icon + label).

## Global constraints
- Never-throw into host; debug/profile only (release no-op) — not relevant for this UI file but keep code consistent.
- Hand-rolled immutable; no freezed.
- Minimal comments (only non-obvious ones).
- Lines ≤ 80 chars.
- No `print` — use `dart:developer` log if logging needed (not needed here).
- Null safety: no `!` unless value guaranteed non-null.
- `const` constructors wherever possible.

## Test to write
File: `packages/flutter_leak_radar/test/ui/finding_detail_screen_test.dart`
Read the existing tests there first.

Add tests in a `group('_buildBottomRow', ...)`:
1. Assert an `InkWell` with non-null `onTap` exists for the capture action:
   ```dart
   expect(find.byWidgetPredicate((w) => w is InkWell && w.onTap != null), findsOneWidget);
   ```
2. Assert the bottom row renders without overflow (pump a full `MaterialApp` with the screen, no `tester.takeException()` errors).

## Report contract
Write your report to:
`/Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/.superpowers/sdd-inspector-ux/task-1-report.md`

Return status, commit hash, one-line test summary, and any concerns.
