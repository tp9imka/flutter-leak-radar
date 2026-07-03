# Android Profiling — Phase 2: net-new `radar_ui` widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Add the four reusable `radar_ui` widgets the Android Profiling views need that don't exist yet: a module color-dot, a severity banner, an expandable row, and a stack-frame list. Every designer color/type/density token already exists — this is widgets only.

**Architecture:** Pure `radar_ui` additions, matching the existing widget conventions: `StatelessWidget`/`StatefulWidget` on `package:flutter/widgets.dart`, styled ONLY from `RadarColors`/`RadarDensity`/`RadarTypography`/`RadarSeverity` tokens (no hardcoded hex), doc comments, barrel-exported, `flutter_test` widget tests.

**Tech Stack:** Flutter (`radar_ui` is a Flutter package — tests run via `flutter test`, NOT `dart test`).

## Global Constraints
- **Tokens only** — no hardcoded colors/sizes; use `RadarColors`, `RadarDensity`, `RadarTypography`, `RadarSeverity`/`SeverityTokens`. (All 10 designer hexes are already exact tokens: accent #2fe39b, info #5ad1e6, warning #f5b54a, critical #ff5d6c, text50 #8fa0a6, text25 #5f7178, text10 #3d4a4f, bgSurface #0e1316, bgTableHeader #0b0f11, bgCode #06090a.)
- **radar_ui stays app-agnostic** — no dependency on `radar_native`/`radar_desktop`; widgets take plain `Color`/`String`/`Widget`, never `NativeModuleKind`. The kind→color mapping lives in the desktop layer (Phase 3).
- **Reduced motion** — any animation must respect it (follow the existing `RadarLivePulseDot`/`RadarLinearProgress` convention in this package — read one to see how it checks `MediaQuery`/reduced-motion before animating).
- **Match conventions** — `import 'package:flutter/widgets.dart';`, token imports, class doc comment, `const` constructor, exported from `lib/radar_ui.dart` barrel. Tests mirror `test/widgets/radar_tag_test.dart` shape.
- Gate per task: `flutter test` green (existing 11 test files + new), `flutter analyze` clean.

---

### Task 1: `RadarModuleDot` + `RadarBanner`

**Files:** Create `lib/src/widgets/radar_module_dot.dart`, `lib/src/widgets/radar_banner.dart`; barrel; Create `test/widgets/radar_module_dot_test.dart`, `test/widgets/radar_banner_test.dart`.

**Interfaces — Produces:**
```dart
/// A small rounded-square color swatch for a category/module, optionally
/// followed by a mono label (the table's module color-tags + the legend).
class RadarModuleDot extends StatelessWidget {
  const RadarModuleDot({super.key, required this.color, this.label, this.size = 8});
  final Color color; final String? label; final double size;
}
/// A full-width, severity-tinted banner (the "fidelity" / notice banner).
/// Tint from SeverityTokens.rowBg/rowBorder; message in mono; optional
/// leading widget and trailing action.
class RadarBanner extends StatelessWidget {
  const RadarBanner({super.key, required this.message,
    this.severity = RadarSeverity.info, this.leading, this.action});
  final String message; final RadarSeverity severity;
  final Widget? leading; final Widget? action;
}
```
- `RadarModuleDot`: an 8×8 (or `size`) rounded-square (radius ~2) filled with `color`; if `label != null`, a `SizedBox(width:4)` + `Text(label, style: RadarTypography.monoTag)` in a `Row(mainAxisSize: min)`.
- `RadarBanner`: a `DecoratedBox` with `color: severity.tokens.rowBg`, `border: rowBorder`, `RadarDensity` radius/padding; a `Row` of `[leading?, message (RadarTypography.monoBody / body), Spacer, action?]`.

- [ ] **Step 1: failing widget tests.** `radar_module_dot_test.dart`: pump `RadarModuleDot(color: RadarColors.info, label: 'App')` inside a minimal `Directionality`/`MediaQuery` wrapper; `expect(find.text('App'), findsOneWidget)`; find the colored box (find a `DecoratedBox`/`Container` with the color) — assert the dot renders and the label shows; a no-label variant shows no `Text`. `radar_banner_test.dart`: pump `RadarBanner(message: 'Module-only', severity: RadarSeverity.warning, action: Text('Add symbols'))`; assert message + action render.
- [ ] **Step 2:** run `flutter test test/widgets/radar_module_dot_test.dart test/widgets/radar_banner_test.dart` → FAIL (undefined).
- [ ] **Step 3:** implement both widgets per spec (tokens only).
- [ ] **Step 4:** run → PASS; `flutter analyze` clean; barrel exports added.
- [ ] **Step 5: commit** `feat(radar_ui): RadarModuleDot + RadarBanner`.

---

### Task 2: `RadarExpandableRow`

**Files:** Create `lib/src/widgets/radar_expandable_row.dart`; barrel; Create `test/widgets/radar_expandable_row_test.dart`.

**Interfaces — Produces:**
```dart
/// A tappable header row that expands to reveal [child]. Chevron rotates on
/// expand (respecting reduced-motion). Used for the still-live table's
/// module rows expanding to their call sites.
class RadarExpandableRow extends StatefulWidget {
  const RadarExpandableRow({super.key, required this.header, required this.child,
    this.initiallyExpanded = false, this.onExpansionChanged});
  final Widget header; final Widget child;
  final bool initiallyExpanded; final ValueChanged<bool>? onExpansionChanged;
}
```
- Header row: a tappable (`GestureDetector`/`InkWell`-free — use `GestureDetector` since widgets-only) `Row` of `[AnimatedRotation chevron (0 → 0.25 turns), Expanded(header)]`, height/padding from `RadarDensity`. Reduced-motion: when disabled, set rotation instantly (duration `Duration.zero`) — check `MediaQuery.of(context).disableAnimations` (mirror the existing reduced-motion widget in this package). When expanded, render `child` below the header.

- [ ] **Step 1: failing test.** Pump a `RadarExpandableRow(header: Text('mod'), child: Text('callsite'))`. Assert `find.text('callsite')` is `findsNothing` initially; `tester.tap(find.text('mod'))` + `pumpAndSettle()` → `find.text('callsite')` `findsOneWidget`; `onExpansionChanged` fires with `true`. Also test `initiallyExpanded: true` shows child immediately.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** implement (StatefulWidget, `_expanded` state, chevron `AnimatedRotation` with reduced-motion-aware duration).
- [ ] **Step 4:** run → PASS; analyze clean; barrel export.
- [ ] **Step 5: commit** `feat(radar_ui): RadarExpandableRow (tap-to-expand, reduced-motion aware)`.

---

### Task 3: `RadarStackList`

**Files:** Create `lib/src/widgets/radar_stack_list.dart`; barrel; Create `test/widgets/radar_stack_list_test.dart`.

**Interfaces — Produces:**
```dart
/// A native/dart call stack rendered as a code block: bgCode background,
/// one monospaced line per frame, each with an optional leading module label
/// and an optional trailing [tag] widget (e.g. a fidelity RadarTag).
class RadarStackFrame {
  const RadarStackFrame({required this.text, this.module, this.tag});
  final String text;      // 'flutter::Foo::bar' or 'malloc'
  final String? module;   // 'libflutter.so' — shown dimmed before/after text
  final Widget? tag;      // e.g. a fidelity RadarTag
}
class RadarStackList extends StatelessWidget {
  const RadarStackList({super.key, required this.frames});
  final List<RadarStackFrame> frames;
}
```
- A `DecoratedBox(color: RadarColors.bgCode, radius/border from tokens)` wrapping a `Column` of frame rows; each row: `Row([Text(text, style: RadarTypography.monoCode), if module!=null Text(module, style: monoLabel dimmed), Spacer, tag?])`. Empty `frames` → a small "no frames" placeholder Text (monoLabel).

- [ ] **Step 1: failing test.** Pump `RadarStackList(frames: [RadarStackFrame(text: 'malloc', module: 'libc.so'), RadarStackFrame(text: 'Foo::bar', module: 'libflutter.so', tag: Text('module-only'))])`. Assert both `text`s render, both `module`s render, and the tag renders. An empty-frames variant shows the placeholder.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** implement per spec.
- [ ] **Step 4:** run → PASS; analyze clean; barrel export.
- [ ] **Step 5: commit** `feat(radar_ui): RadarStackList (code-block call stack with per-frame tags)`.

---

## Self-review notes
- Coverage: module dot (table tags + legend), banner (fidelity notice), expandable row (table module→callsite), stack list (detail call stack). ✓
- app-agnostic: no radar_native/desktop dependency; plain Color/String/Widget props. ✓
- Tokens only; reduced-motion respected on the one animated widget. ✓
- Out of scope: the table composition (Phase 3, in the desktop screen from RadarSortHeader + these), tiles/fidelity-tags (reuse existing RadarMetricTile/RadarTag), the kind→color map (Phase 3).
