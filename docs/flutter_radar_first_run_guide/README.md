# Handoff: Radar Desktop — First-Run Onboarding Guide

A **once-only, skippable, re-openable onboarding tour** for the Radar Desktop app that surfaces the app's full breadth on first launch. This handoff covers **only the guide**; the app it teaches is specified in `../flutter_radar_desktop/` + `../flutter_radar_android_profiling/`.

`Flutter Radar — First-Run Guide.dc.html` is the interactive reference (welcome modal → 5 spotlight coach-marks → finish, with keyboard nav, reduced-motion, once-only persistence, and re-open). `support.js` is **preview-only — do not ship.** Rebuild in Flutter inside `radar_desktop`, reusing `radar_ui` tokens. The prototype's app backdrop is a faithful static mock of the real shell **for context only** — do not rebuild the backdrop; the guide overlays the *real* running shell.

The harness above the window (flag readout / "Reset flag & replay" / reduced-motion toggle) is **prototype scaffolding only** — not part of the app.

---

## 1. Chosen format & rationale
**Hybrid: a welcome modal, then a spotlight/coach-mark tour over the real UI, then a finish modal.**
- The app is dense and its value *is* the rail's breadth — a spotlight tour that dims the app and points at the **real** rail groups, Connect bar, and health dot teaches the actual geography, not an abstraction, and lands the user oriented in the real window.
- A pure carousel would divorce copy from the UI; pure coach-marks with no welcome/finish feel abrupt. The welcome sets expectations ("takes a minute, shown once, skippable"); the finish gives a concrete first action.
- **Locked features handled honestly:** Performance/Stability are locked offline. Step 3 spotlights those two locked rail groups *as locked* and explains that connecting unlocks them — the disabled state becomes the teaching moment rather than a problem. The tour never requires a connection, a device, imported data, or installed tools to run — every step explains its feature in whatever state the app is in.

## 2. Map to the real app (1:1 anchors)
Anchor each spotlight to the existing widget (source paths under `packages/radar_desktop/lib/src/`):

| Step | Anchor widget | Source |
|---|---|---|
| 1 · Connect | the `ConnectBar` strip | `shell/connect_bar.dart` |
| 2 · Memory | the **MEMORY** rail group (Dumps…Trends) | `shell/desktop_rail.dart` |
| 3 · Perf/Stability | the **PERFORMANCE** + **STABILITY** rail groups (locked) | `shell/desktop_rail.dart` |
| 4 · Android | the **ANDROID NATIVE** rail group | `shell/desktop_rail.dart` |
| 5 · Tools | the **SETUP → Tools** rail item (+ callout references the title-bar health dot) | `shell/desktop_rail.dart`, `shell/desktop_window_chrome.dart` |

The `DesktopShell` (`shell/desktop_shell.dart`) is the natural owner: it already builds `DesktopWindowChrome`, `ConnectBar`, and `DesktopRail` in a `Column`, so it can host the overlay above them and hold the guide controller. Implement anchoring with `GlobalKey`s on those four rail groups + the connect bar + the health dot (read each key's render box for the spotlight rect), rather than hard-coded coordinates — the rail scrolls and the window resizes.

## 3. Steps — purpose, exact copy, states
Welcome and finish are centered modals over a dimmed app; steps 1–5 are spotlights (dimmed app with a cut-out highlight ring on the anchor + an adjacent callout).

**Welcome (modal).** Radar sweep motif. Headline **"Welcome to Radar Desktop"**. Body: *"Analyze Flutter memory, performance, stability, and native-heap data — from offline captures or a live app. Here's a quick tour of what's here. Takes about a minute."* Buttons: **"Skip for now"** (secondary) · **"Take the tour →"** (primary). Fine print: *"Esc to skip · ← → to navigate · shown once."*

**Step 1 — Connect (anchor: Connect bar, callout below).** Kicker `CONNECTED MODE`. Title **"Connect to a running app."** Body: *"Paste a Dart VM Service ws:// URI to attach to a live app — or tap Scan device (Android) to read adb logcat, forward the port, and fill this in for you."* Accent note: *"Connecting unlocks Performance & Stability, live heap capture, and Force GC."*

**Step 2 — Memory (anchor: MEMORY group, callout right).** Kicker `MEMORY · OFFLINE`. Title **"Analyze memory with no running app."** Body: *"The default surface. Import a heap dump or Perfetto .pftrace — button or drag-and-drop anywhere. Then browse Dumps, the Class histogram, Retaining paths, Compare two dumps, and Trends across a soak."*

**Step 3 — Performance & Stability (anchor: both locked groups, callout right).** Kicker `PERFORMANCE · STABILITY`. Title **"Locked until you connect."** Body: *"Traces & Frames, Errors & Stalls come alive once you attach to a running app. If the target doesn't embed the perf runtime, these views say 'not detected' rather than faking data."* Warning-toned note: *"Locked now (offline) — connect via the bar above to unlock."* (This is the locked-target step: keep the anchor visibly disabled.)

**Step 4 — Android native (anchor: ANDROID NATIVE group, callout right).** Kicker `ANDROID NATIVE`. Title **"Profile below the Dart heap."** Body: *"Capture native-heap allocations via adb + heapprofd. See per-module still-live memory (which .so holds it), checkpoint Compare, an FFI-allocations lane, and native symbolization to turn module-only frames into function names."*

**Step 5 — Tools (anchor: SETUP → Tools, callout right).** Kicker `SETUP · TOOLS`. Title **"External tools & the health dot."** Body: *"Tools manages the CLIs Radar shells out to — trace_processor, adb, llvm-symbolizer. Each shows Found (path + version) or Missing, with Install, Locate…, and Re-check."* Warning-toned note: *"The health dot in the title bar turns amber when a tool is missing — tap it to jump here."*

**Finish (modal).** Check icon. Title **"You're set."** Body: *"Start by importing a heap dump or a .pftrace — button or drag-and-drop anywhere. Connect to a running app to unlock Performance & Stability."* Tip box: *"every error has a Copy action, and you can reopen this tour any time from the ? in the title bar."* Buttons: **Back** · **Done** (primary). (Covers §2-E quality-of-life + the re-open location.)

Each spotlight callout carries: kicker, a **step counter "N / 5"**, title, body, optional note, progress dots, and **Skip · Back · Next** (Next reads **"Finish"** on step 5). Clicking the dimmed backdrop = Skip.

## 4. Once-only · skip · re-open (spell out)
- **Persistence:** a boolean `hasSeenFirstRunGuide` in the app-support store (e.g. `shared_preferences` / a settings file next to the workspace store). Prototype uses `localStorage['radar_hasSeenFirstRunGuide']`.
- **First launch:** if the flag is absent/false, the guide auto-opens at the welcome step. Set the flag to true the moment the guide is **completed (Done) or skipped** (any Skip/✕/Esc/backdrop) — never show automatically again.
- **Skip is always available:** ✕ on the modals, a "Skip" button on every spotlight, `Esc`, and a backdrop click. All end the guide immediately and mark it seen.
- **Non-blocking:** the guide gates no real work; it's an overlay the user can dismiss at any point. It does not trap focus in a way that prevents Esc.
- **Re-open:** a **`?` button in the title bar right gutter** (next to the health dot) reopens the tour at the welcome step on demand. (Alternative/also acceptable: a "Show guide" affordance in the Tools screen.) Re-opening does **not** clear the seen flag.

## 5. Accessibility
- **Keyboard:** `Esc` = skip/close; `→` / `Enter` = next (advances welcome→1→…→finish→done); `←` = back. Focus should move into the callout/modal on each step; restore focus to a sensible app element on close.
- **Focus order** within a callout: title → body → Skip → Back → Next.
- **Reduced motion:** respect `prefers-reduced-motion` — no ring pulse, no radar sweep, no animated spotlight tween (cut directly to each position). The prototype mirrors this with a `.frg-reduce` class and the media query; wire the Flutter version to `MediaQuery.disableAnimations`/the platform reduced-motion setting.
- **Contrast:** callouts use `bgSurface`/panel with `text100`/`text60` on the dark base (meets AA for body); the accent ring is decorative, not the sole signifier — copy names the anchor too.

## 6. Responsive (~1180×760 → 920×600 min)
- Anchor rects are measured from live render boxes, so the spotlight follows the widgets at any size. **Callout placement** flips to stay on-screen: right-of-anchor by default (rail steps), below for the connect bar; clamp within the window, and fall back to the opposite side if it would overflow (the prototype does this).
- At the 920×600 minimum the rail groups sit closer together — the ring may span a group tightly; keep callout width ≤ ~330 and clamp its top so Skip/Back/Next stay visible. If the anchored group is scrolled out of view, scroll it into view before showing the step.
- Welcome/finish modals are centered and width-capped (`min(460px, 86%)`).

## 7. Design tokens (reuse `radar_ui`, do not invent)
Base `RadarColors.bgPage #0b0e10` · panel `bgPanel #0c1012` · surface `bgSurface #0e1316` · rail `bgRail #0a0e0f`. Accent `accent #2fe39b` (+ `accentSubtle`); warning `#f5b54a` (locked/health-dot notes); dim backdrop `rgba(4,6,7,0.72–0.78)`. Text `text100 #e7eef0` / `text60 #a7b6bc` / `text25 #5f7178`. Space Grotesk for headings, JetBrains Mono for kickers/labels/counters. Ring: 1px accent border + soft accent glow, radius 10, 8px padding around the anchor.

## State model (prototype → Flutter controller)
`seen` (persisted) · `open` · `step` (0 welcome · 1–5 spotlight · 6 finish) · measured anchor `rects` · `reduce`. In Flutter: a small `FirstRunGuideController` (ChangeNotifier) owning step + seen, GlobalKeys for anchors, an `OverlayEntry`/`Stack` layer in `DesktopShell`, and the boolean read on startup in `initState`.

## Files
- `Flutter Radar — First-Run Guide.dc.html` — interactive reference (welcome, 5 spotlights, finish; keyboard, reduced-motion, once-only, re-open).
- `support.js` — preview runtime. **Do not ship.**
