# Handoff: Radar Desktop — Android Native Profiling section (v1)

A **new peer section inside the existing Radar Desktop app** (not a separate product) for diagnosing **native** Android memory growth — the leaks that live *below* the Dart heap (Flutter engine, plugins, C/C++, `dart:ffi`, GPU/image handles). Reached from the app's main navigation rail, alongside the existing Dart-heap surfaces (Dumps, Class histogram, Retaining paths, Compare, Trends).

This handoff covers **only the new Android functionality**. The rest of Radar Desktop is specified in `../flutter_radar_desktop/`. Reuse the same `radar_ui` tokens and the existing app shell — this must feel like the same app, one section over.

## Reference file
`Flutter Radar - Desktop.dc.html` (the full desktop app, now including this section — same file as the base handoff, updated). `support.js` is **preview-only — do not ship.** The Android section lives in the rail group **"ANDROID NATIVE"** and its six views. Open it, click into that rail group; the **Session** view has a "demo state" switcher (empty / loading / ready / error) and the fidelity toggles (add symbol store / add ffi log) so you can see every state and both fidelity levels live.

Rebuild as Flutter desktop widgets in the existing app, reusing `radar_ui` and the `leak_graph`/analysis layer. **No new design system, no new analysis engine.**

---

## 1. Why it exists
The Dart-heap lane only sees Dart objects. On Android, a large class of leaks is native `malloc` growth. When a user has ruled out the Dart heap but memory still climbs, this is where they go. **Android only for v1.**

## 2. The honesty rule (load-bearing — the whole point)
Every number must carry its **confidence**. The design encodes three fidelity levels visually and must never render them with equal authority:
- **measured** (certain) — still-live bytes, growth, module attribution. Green dot / "measured" micro-label.
- **conditional** — function names in native stacks. Only resolve when an unstripped-`.so` **symbol store** (matched by build-id) is imported. Until then, frames show **module-only** (amber "module-only" tag). Even *with* symbols, vendor GPU frames may stay unresolved → "· vendor" / "unsymbolized" (amber).
- **unavailable** — GPU **total** bytes frequently read 0 on-device → shown as **"not reported · n/a on this device"**, never a silent 0 that reads as "no problem."

Language discipline: never claim "leak" with certainty from bytes alone (still-live accounting can't separate a true leak from an unbounded-but-reachable cache). Use **"still-live / growing"** wording; leave room for a future "unreachable" discriminator.

## 3. Where it sits (IA)
New rail group **ANDROID NATIVE** (offline-capable — it's import-first, so *not* gated on a VM connection, unlike the Performance/Stability groups):
- **Session** — section entry / overview
- **Native still-live** — the workhorse table
- **Compare** — checkpoint diff
- **ffi allocations** — conditional; only appears when an ffi log is imported
- **Capture / import** — the tools helper

Callsite/module **detail** is a drill-down from the Native table (no separate rail item).

## 4. The six views — each with its states

### 4.1 Session overview
What's imported + fidelity state + quick totals + entry points. States (all in the prototype's "demo state" switcher):
- **empty** — no captures; CTA to Capture/import.
- **loading** — spinner + indeterminate bar + "Analyzing trace_24h.pftrace… · 331 MB · resolving still-live call sites" (design for large traces on a background isolate).
- **ready** — a **fidelity banner** (Module-only ↔ Fully symbolized, with "+ add symbol store" / "+ add ffi log" actions); three total tiles: **native still-live (latest)** and **growth 00h→24h** (both *measured*), and **GPU total** (*n/a on device*, visibly de-emphasised); an **imported artifacts** list (checkpoints + symbol-store/ffi presence rows); **jump-in** cards.
- **error** — "Couldn't parse trace": the `.pftrace` had no `heapprofd` stream (a CPU-only trace) — honest, specific, with the fix.

### 4.2 Native still-live overview (workhorse)
Ranked table, **primary grouping by module**, each row **expandable to its call sites**. Density and scannability matter most here.
- Columns: **module ▸ call site · still-live bytes · alloc count · Δ vs previous checkpoint**. **Sortable** (still-live / growth / allocs).
- A **checkpoint picker** (which snapshot to view).
- Modules are color-tagged by kind — **app** (cyan), **GPU driver** (amber, always also text-labelled "GPU driver" so it's never colour-only), **engine** (grey), **plugin** (green). GPU/driver modules are **first-class rows in this lane** — there is deliberately **no separate images/textures tracker** in v1.
- Expanded call-site rows show the top frame at the **current fidelity** (module-only vs function name) with a micro state-tag, still-live, allocs, and a `›` into detail.
- Growth colour: red = grew, green = shrank.

### 4.3 Checkpoint compare (diff)
Two-picker (A → B), mirroring the existing Dart-heap compare. Per module: **status = ADDED / GREW / SHRANK / GONE** (added & grew red; shrank & gone green), plus A bytes, B bytes, Δ bytes. Sorted by |Δ|. Header shows total native Δ. This is where "is it getting worse" is answered. (The seed data includes an *added* module — a new WebRTC leak — and a *gone* one — a freed tflite buffer — so all four statuses are visible.)

### 4.4 Callsite / module detail (drill-down)
- Module + kind; **still-live** and **live allocations** tiles (both *measured*).
- **Module still-live across checkpoints** — a small bar trend (the current checkpoint highlighted).
- **Native call stack** — module-labelled frames; **function names when symbolized**, each frame carrying its own fidelity tag. Header states symbolized vs module-only.
- When unsymbolized: a prominent **"Function names unavailable → Add symbols"** affordance (build-id matching explained). Clicking it flips the whole section to symbolized (demo).

### 4.5 ffi allocations lane (conditional)
Only present when an **ffi allocation log** is imported (rail item appears; toggle in Session/Capture). Higher-fidelity sibling of the native lane: still-live ffi blocks **grouped by Dart allocation site**, each with a real **`file:line` Dart stack** (unlike the native lane's module frames) — fix-grade, works in release-shaped builds. Master list (site · file · still-live · blocks) + detail panel with the Dart stack, all *measured*.

### 4.6 Capture / import tool (tools area)
Guided, plainly-stated prerequisites:
- **Import Perfetto trace** — `.pftrace` with a heapprofd stream (required); drag-drop.
- **Run device capture** — drives `adb` + heapprofd against a connected device; shows device/authorization checks and the **caveat**: profile the **profile/release** build (debug adds allocator noise).
- **Optional inputs** — attach **symbol store** (unlocks function names) and import **ffi log** (adds the ffi lane), each clearly marked optional.
- Everything analysed **offline from files**; **Android only · iOS not supported** stated inline.

Optional / nice-to-have (not v1-blocking, not built here): a lightweight native-bytes-over-checkpoints trend strip echoing the Dart-heap Trends view.

## 5. Constraints & non-goals
- **Desktop, offline, import-first.** No live app required for analysis. (The section is intentionally *not* behind the VM-connection gate.)
- **Android only** for v1.
- **Reuse `radar_ui`** + existing app shell; a section, not a new skin.
- **Non-goals (don't design/build):** live/streaming profiler; a dedicated image/texture tracker (folded into the native lane); reliable GPU totals; iOS.

## 6. Confidence visual language — quick reference
- **measured**: full-opacity value + green micro-dot/label. (still-live, growth, module, ffi Dart stacks)
- **module-only / unsymbolized**: amber micro-tag on the frame; the "add symbols" path always visible.
- **n/a on device**: de-emphasised tile (reduced opacity, grey), literal "not reported · n/a on this device" — never 0.
Reuse existing `radar_ui` severity/family colours: green `#2fe39b`, cyan `#5ad1e6`, amber `#f5b54a`, red `#ff5d6c`, greys `#8fa0a6/#5f7178/#3d4a4f`; surfaces `#0e1316`, table headers `#0b0f11`, code `#06090a`. JetBrains Mono + tabular figures for every number; Space Grotesk for headings.

## State model (prototype)
`aView` (session/native/compare/detail/ffi/capture) · `aData` (empty/loading/ready/error) · `aSymbols` (symbol store present → function names) · `aFfi` (ffi log present → lane visible) · `aCp` (active checkpoint) · `aExpand` (expanded module) · `aCallsite` (detail target) · `aDiffA`/`aDiffB` (compare) · `aNSort`. In the real app, still-live/module/callsite data comes from parsing heapprofd/Perfetto via the analysis layer; function names from the symbol store; the ffi lane from the imported allocation log.

## Files
- `Flutter Radar - Desktop.dc.html` — interactive reference (full app; the Android section is the "ANDROID NATIVE" rail group + its 6 views).
- `support.js` — preview runtime. **Do not ship.**
