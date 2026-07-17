# Radar Desktop — First-Run Onboarding Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Build the designer-specified first-run guide in `radar_desktop`: a **once-only, skippable, re-openable** tour — a welcome modal → 5 spotlight coach-marks over the REAL shell (Connect bar, MEMORY / PERFORMANCE+STABILITY / ANDROID NATIVE / SETUP-Tools rail groups) → a finish modal. Spec + reference mock: `docs/flutter_radar_first_run_guide/README.md` (+ `Flutter Radar - First-Run Guide.dc.html`). The `.dc.html`/`support.js` are PREVIEW-ONLY — rebuild in Flutter with `radar_ui` tokens; overlay the real running shell (do NOT rebuild the shell backdrop).

**Architecture:** A `FirstRunGuideController` (ChangeNotifier) owns `step`/`open`/`seen`, backed by a `path_provider`+JSON store (mirrors `FileToolConfigStore` — NOT `shared_preferences`, which the app doesn't use). `DesktopShell` hosts the overlay in a `Stack` above the chrome/ConnectBar/rail/content, holds `GlobalKey`s on the anchor widgets, reads `seen` on startup (auto-opens if unseen), and adds a `?` re-open button to the window chrome. The overlay measures anchor render boxes for the spotlight rects (no hard-coded coordinates — the rail scrolls and the window resizes).

**Tech Stack:** Flutter (`radar_desktop`), `radar_ui` tokens, `path_provider`.

## Global Constraints
- **Reuse `radar_ui` tokens verbatim** (§7 of the spec): `RadarColors.bgPage/bgPanel/bgSurface/bgRail`, `accent #2fe39b`, warning `#f5b54a`, `text100/text60/text25`; Space Grotesk headings, JetBrains-mono kickers/counters; dim backdrop `rgba(4,6,7,0.72–0.78)`; ring = 1px accent border + soft accent glow, radius 10, 8px padding around the anchor. No hardcoded hex — use the tokens (check `radar_ui` for the exact names; if a token is missing use the nearest existing one, don't invent a palette).
- **Copy verbatim** from spec §3 (headlines, body, kickers, notes, button labels) — do not paraphrase.
- **Once-only:** `hasSeenFirstRunGuide` persisted; auto-open at welcome only when absent/false; set true the moment the guide is completed (Done) OR skipped (any ✕ / Skip / Esc / backdrop click). Never auto-shows again.
- **Skip always available**; **non-blocking** (gates no real work; Esc always exits); **re-open** via a `?` button in the title-bar right gutter (next to the health dot) — re-open does NOT clear the seen flag.
- **Accessibility (spec §5):** `Esc`=skip, `→`/`Enter`=next (welcome→1..5→finish→done), `←`=back; move focus into the callout/modal per step; reduced-motion (`MediaQuery.disableAnimations`) → no ring pulse / no sweep / no spotlight tween (cut directly); copy names the anchor (ring isn't the sole signifier).
- **Responsive (spec §6):** measure live render boxes; callout placement flips to stay on-screen (right-of-anchor for rail steps, below for the connect bar; clamp within the window; opposite side on overflow); scroll an anchored rail group into view before showing its step; welcome/finish modals centered, width `min(460, 86%)`, callout width ≤ ~330.
- CI: Flutter 3.44.4 — NO `containsSemantics`/`matchesSemantics` in tests; `flutter analyze` clean; `dart format --set-exit-if-changed .` clean; `git checkout -- packages/radar_desktop/macos` before committing. See [[project_flutter_leak_radar_ci_skew]].

---

### Task 1: `FirstRunGuideController` + persistence store

**Files:** Create `lib/src/onboarding/first_run_store.dart`, `lib/src/onboarding/first_run_guide_controller.dart`; tests `test/onboarding/first_run_guide_controller_test.dart`.

**Produces:**
```dart
abstract interface class FirstRunStore { Future<bool> hasSeen(); Future<void> markSeen(); }
/// path_provider app-support dir + `first_run.json` ({"seen": true}); mirror FileToolConfigStore.
final class FileFirstRunStore implements FirstRunStore { const FileFirstRunStore(); ... }

/// step: 0 welcome · 1..5 spotlights · 6 finish.
final class FirstRunGuideController extends ChangeNotifier {
  FirstRunGuideController({FirstRunStore store = const FileFirstRunStore()});
  int get step; bool get open; bool get seen;
  static const int lastSpotlight = 5;   // steps 1..5
  Future<void> load();     // read seen; if !seen -> open=true, step=0
  void next();             // welcome->1..->5->finish(6)->then complete()
  void back();             // finish->5..->1->welcome(0); no-op below 0
  void skip();             // open=false + persist seen (markSeen) — ✕/Skip/Esc/backdrop
  void complete();         // Done on finish: open=false + persist seen
  void reopen();           // open=true, step=0 — does NOT clear seen
}
```
- `load`: `seen = await store.hasSeen(); if (!seen) { _open = true; _step = 0; } notify`. Never throws (a missing file → not seen).
- `next` from step 6 (finish) calls `complete()`. `skip`/`complete` both `store.markSeen()` (fire-and-forget, guard dispose) + set `_open=false` + `_seen=true` + notify. `reopen` sets `_open=true,_step=0` and notifies without touching `seen`.
- Add a `_disposed` guard (no notify after dispose) like `ToolsController`.

- [ ] **Step 1: failing tests** with an in-memory fake store: `load` with unseen store → open, step 0; with seen store → not open. `next` walks 0→1→…→5→6, then `next` at 6 completes (open false, store marked). `back` walks down, floors at 0. `skip` at any step → open false + store.markSeen called. `reopen` → open, step 0, seen unchanged. No notify after dispose.
- [ ] **Step 2-4:** run→fail, implement, `flutter analyze` clean, `flutter test` green, `dart format` 0 changed.
- [ ] **Step 5: commit** `feat(radar_desktop): FirstRunGuideController + persisted seen flag`.

---

### Task 2: anchor keys on the rail + `?` re-open button in the chrome

**Files:** Modify `lib/src/shell/desktop_rail.dart` (accept + attach group `GlobalKey`s); Modify `lib/src/shell/desktop_window_chrome.dart` (add a `?` button + optional health-dot key); tests updated.

- **DesktopRail:** add optional named `GlobalKey?` params — `memoryGroupKey`, `performanceGroupKey`, `stabilityGroupKey`, `androidGroupKey`, `toolsGroupKey` — and attach each to that group's widget (wrap the `_group(...)`+its items in a `KeyedSubtree(key: ...)`, or key the group header container). Default null (no behavior change → existing rail tests pass). (Step 3 anchors BOTH performance + stability; the overlay unions those two rects — so key them separately.)
- **DesktopWindowChrome:** add an optional `VoidCallback? onReopenGuide`; when non-null, render a small **`?`** `IconButton` (tooltip "Show guide") in the right gutter immediately LEFT of the health dot (match the mock — same size/spacing, tokens-only). Also add an optional `GlobalKey? healthDotKey` attached to the `_ToolHealthDot` (so step 5's callout can reference it; optional). Existing chrome tests unaffected when the new params are null.
- [ ] **Step 1: failing tests:** DesktopRail given the 5 keys renders and each key resolves to a widget in the tree (pump the rail, assert `key.currentContext != null`). DesktopWindowChrome with `onReopenGuide` shows a `?` button that calls it on tap; with null → no `?` button. Avoid `containsSemantics`.
- [ ] **Step 2-4:** tests → implement → analyze + test green → format 0 changed → `git checkout -- macos`.
- [ ] **Step 5: commit** `feat(radar_desktop): rail anchor keys + chrome ? re-open button for the guide`.

---

### Task 3: the guide overlay widget (welcome · spotlights · finish)

**Files:** Create `lib/src/onboarding/first_run_guide.dart` (the overlay) + `lib/src/onboarding/guide_spotlight_painter.dart` (the dim+cut-out+ring painter); tests `test/onboarding/first_run_guide_test.dart`.

**Produces:** `FirstRunGuide({required FirstRunGuideController controller, required Map<GuideStep, GlobalKey> anchors})` — a full-bleed overlay (returns `SizedBox.shrink()` when `!controller.open`). Consumes the anchors (connect bar + the rail group keys + optionally the health dot).

Behavior:
- **Welcome (step 0) & finish (step 6):** a centered card over a dim backdrop (`RadarColors` panel/surface, radius, the radar-sweep motif for welcome, a check for finish), the spec §3 copy verbatim, and the buttons (welcome: "Skip for now" secondary + "Take the tour →" primary; finish: "Back" + "Done" primary; a ✕ on both). Finish includes the tip box (Copy action + "reopen from the ? in the title bar").
- **Spotlights (steps 1..5):** dim the whole window; measure the step's anchor `GlobalKey` render box → a rect in the overlay's coordinate space; draw the cut-out (anchor area undimmed) + a 1px accent ring + soft glow (8px padding, radius 10) via the painter. Step 3's rect = the UNION of the performance + stability group rects. Place an adjacent **callout** card carrying: kicker (mono), a **"N / 5"** counter, title, body, an optional warning-toned note (steps 3 & 5), progress dots (5), and **Skip · Back · Next** (Next label = "Finish" on step 5). Backdrop click or ✕ or Skip = `controller.skip()`; Next = `controller.next()`; Back = `controller.back()`.
- **Callout placement:** right-of-anchor for rail steps, below for the connect bar; clamp within the window bounds; flip to the opposite side if it would overflow; width ≤ 330. If the anchor rect is empty/off-screen (group scrolled away), the shell scrolls it into view first (Task 4) — here, guard against a null/zero rect (skip the ring, still show the callout centered) so it never crashes.
- **Keyboard:** wrap in a `Focus`/`Shortcuts`+`Actions` (or `CallbackShortcuts`): Esc→skip, Arrow Right/Enter→next, Arrow Left→back; autofocus the overlay each step; focus order in the callout title→body→Skip→Back→Next.
- **Reduced motion:** if `MediaQuery.of(context).disableAnimations`, no ring pulse / no motion / cut directly between steps (no animated rect tween).
- Copy + tokens verbatim from the spec. Reuse existing `radar_ui` widgets where they fit (buttons, typography).

- [ ] **Step 1: failing tests (widget):** pump `FirstRunGuide` with a controller (open at step 0) inside a minimal harness that provides the anchor keys on placeholder boxes: welcome shows "Welcome to Radar Desktop" + both buttons + the fine print; tapping "Take the tour →" advances to step 1 (its title "Connect to a running app." shows); the "N / 5" counter shows "1 / 5"; Next through to step 5 shows Next labeled "Finish"; one more Next → finish "You're set."; Done → `controller.open` false + seen persisted (fake store). Skip on a spotlight → open false. A reduced-motion pump (wrap in `MediaQuery(disableAnimations: true)`) still renders each step. Assert via `find.text`/`find.byType`/tap — NO `containsSemantics`. Anchor-rect math: with a placeholder anchor at a known rect, the callout renders on-screen (assert it's found and within bounds).
- [ ] **Step 2-4:** run→fail, implement, analyze clean, test green, format 0 changed.
- [ ] **Step 5: commit** `feat(radar_desktop): first-run guide overlay (welcome, 5 spotlights, finish)`.

---

### Task 4: wire the guide into `DesktopShell`

**Files:** Modify `lib/src/shell/desktop_shell.dart`; Modify `test/shell_test.dart`.

- Hold a `late final FirstRunGuideController _guide = widget.guide ?? FirstRunGuideController();` (add an injectable `FirstRunGuideController? guide` to `DesktopShell` for tests, like `tools`/`connection`); `_guide.load()` in `initState`; listen → `setState`; dispose only if self-created.
- Create the anchor `GlobalKey`s (connect bar + 5 rail groups; optionally health dot). Pass the rail keys into `DesktopRail`; wrap the `ConnectBar` in a `KeyedSubtree(key: connectBarKey)`; pass `onReopenGuide: _guide.reopen` (+ health-dot key) into `DesktopWindowChrome`.
- Restructure the shell body so the guide overlays everything: wrap the existing `Column` (chrome + connect bar + Expanded row) in a `Stack`, with `FirstRunGuide(controller: _guide, anchors: {...})` as the top layer (it self-hides when `!_guide.open`).
- Before showing a spotlight for a rail group, ensure it's visible: on step change to a rail step, `Scrollable.ensureVisible(key.currentContext!)` (guard null) so the anchor is in view (the rail is scrollable). Simplest: have the overlay request it, or the shell listens to `_guide.step` and scrolls. Keep it minimal + guarded.
- [ ] **Step 1: failing tests:** shell with an injected `FirstRunGuideController` backed by an UNSEEN fake store → after `load`, the welcome ("Welcome to Radar Desktop") is shown over the shell; with a SEEN store → no guide. Tapping the chrome `?` (reopen) shows the welcome again. Existing shell tests stay green (guide hidden when seen / not injected-unseen). Avoid `containsSemantics`.
- [ ] **Step 2-4:** tests → implement → `flutter analyze` clean → `flutter test` green → `dart format` 0 changed → `git checkout -- macos`.
- [ ] **Step 5: commit** `feat(radar_desktop): show the first-run guide on first launch + ? re-open`.

---

### Task 5: build + manual verification
- [ ] `flutter analyze` clean; `flutter test` green; `flutter build macos --debug` OK; `dart format --set-exit-if-changed .` clean repo-wide.
- [ ] **Manual (documented):** delete the persisted flag (fresh state) → launch → welcome shows; take the tour → each spotlight highlights the REAL rail group / connect bar (locked PERFORMANCE/STABILITY shown as locked in step 3); Skip / Done persists (relaunch → no guide); the `?` in the title bar re-opens it; Esc/←/→ work; toggle macOS reduce-motion → no spotlight animation. Record the observed result in the commit body.
- [ ] commit `chore(radar_desktop): first-run guide verified on device`.

## Self-review notes
- Coverage: controller+persistence (T1), anchors+`?` (T2), overlay UI (T3), shell wiring+auto-open (T4), verify (T5). ✓
- Reconciled deltas vs spec: persistence via path_provider+JSON (spec allows); rail group `SETUP → Tools` matches; `?`+health-dot already in the chrome right gutter (mock confirms); step-3 anchor = union(perf, stability). ✓
- Honest/robust: guide never blocks work; guards null/empty anchor rects; reduced-motion respected; copy/tokens verbatim. ✓
- Out of scope: rebuilding the shell backdrop (overlay the real one); the prototype harness/`support.js` (preview-only); iOS.
