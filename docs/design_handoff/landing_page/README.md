# Handoff: Flutter Leak Radar — Marketing Landing Page

## Overview
A single-page marketing/landing site for **Flutter Leak Radar**, an open-source memory-leak toolkit for Flutter. The page positions the product around one idea — *"Catch Flutter leaks twice — before they ship, and while they run"* — and showcases its two halves: a static `custom_lint` plugin (prevention) and an on-device runtime detector (detection).

This is a **website**, not the Flutter library's in-app UI. The "findings screen" and "draggable badge" shown on the page are **marketing mockups** — stylized, web-sized illustrations of what the library renders on a device. They are NOT a screen spec for the library itself. (If the actual Flutter screens need designing — overlay badge, findings list, finding detail with retaining-path tree, export sheet, settings — that is a separate deliverable.)

## About the Design Files
The file in this bundle (`Flutter Leak Radar.dc.html`) is a **design reference created in HTML** — a prototype showing the intended look, copy, and motion of the landing page. It is **not production code to copy directly**.

> Note on format: the `.dc.html` file is authored as a "Design Component" and depends on a runtime (`support.js`) for the template/logic split and the tab interaction. **Do not ship this file or its runtime.** Treat it as a visual + behavioral reference and rebuild the page in the target environment.

The task is to **recreate this design in the target codebase's environment** using its established patterns. If there is no existing site codebase, the recommended stack for a page like this is **Astro** or **Next.js (static export)** with plain CSS / CSS Modules / Tailwind — it is a static marketing page with light interactivity (one tab toggle + scroll reveals), so a heavy SPA framework is unnecessary.

## Fidelity
**High-fidelity (hifi).** Final colors, typography, spacing, copy, and motion are all specified below and present in the HTML. Recreate the UI pixel-closely. Exact hex values, font stacks, and sizing are documented in **Design Tokens**.

---

## Page Structure (top → bottom)

The page is a single column, max content width **1240px**, centered, with section horizontal padding `clamp(18px, 4vw, 40px)`. Two fixed, full-viewport decorative background layers sit behind everything (`z-index:0`): a radial-gradient glow and a faint 64px dotted grid masked toward the top. All content sits at `z-index:1`.

### 1. Nav (sticky)
- **Layout**: sticky top bar, `backdrop-filter: blur(14px)`, background `rgba(7,9,10,0.72)`, bottom border `1px solid rgba(255,255,255,0.07)`. Inner row: space-between, vertical padding 14px.
- **Left**: radar-icon SVG (26px) + wordmark "Leak Radar" (Space Grotesk 600, 16.5px) + a mono pill "FLUTTER" (10px, bordered).
- **Right**: text links *How it works · Features · Install* (`#a7b6bc`, 13.5px, hover → white on `rgba(255,255,255,0.05)`), then a solid green **GitHub** button (mono 12.5px, bg `#2fe39b`, text `#07090a`, radius 9px) with a GitHub glyph.
- There is also a hidden "The problem" link (`display:none`) — optional to include.

### 2. Hero
- **Layout**: two-column flex-wrap, gap `clamp(36px,5vw,72px)`, vertically centered. Left column `flex:1 1 460px`, right column `flex:1 1 420px` min-height `clamp(380px,42vw,520px)`.
- **Left column**:
  - Eyebrow pill: mono 11.5px uppercase, green text `#2fe39b`, border `rgba(47,227,155,0.28)`, bg `rgba(47,227,155,0.06)`, with a glowing 6px green dot. Text: "Open-source memory-leak toolkit".
  - **H1**: Space Grotesk 600, `clamp(40px,6.6vw,76px)`, line-height 0.98, letter-spacing -0.03em. Reads "Catch Flutter leaks **twice**." — "twice" is green `#2fe39b` with a hand-drawn SVG underline squiggle (green, 2.4px stroke).
  - Sub-paragraph: `clamp(16px,1.7vw,19px)`, `#a7b6bc`, max-width 520px. Last sentence emphasized in `#d6e2e5`: "Zero config. No mixins. A complete no-op in release."
  - **Buttons**: primary "Get started →" (green, `#07090a` text, radius 11px, shadow `0 8px 30px rgba(47,227,155,0.22)`, hover lifts 1px) + secondary "See how it works" (bg `rgba(255,255,255,0.04)`, border, radius 11px).
  - **Install chip**: mono 13px, bg `#0c1113`, border, radius 10px — shows `$ flutter pub add dev:leak_radar` (with `flutter` in cyan `#5ad1e6`, `dev:leak_radar` in green `#c3e88d`) · divider · "debug + profile only" in `#5f7178`.
- **Right column** (the hero visual — see **Interactions** for motion):
  - **Radar instrument** (absolute, centered, `clamp(300px,34vw,440px)` square): 4 concentric rings (`inset` 0/13%/28%/44%, border `rgba(47,227,155,0.10→0.16)`), crosshair lines, a **conic-gradient sweep** rotating, an **expanding ring pulse**, and 3 **blips** (critical `#ff5d6c`, warning `#f5b54a`, info `#5ad1e6`) each with a glow box-shadow and a pulse animation.
  - **Findings device card** (z-index 2, width `clamp(280px,30vw,330px)`): rounded 20px, bg gradient `#0e1417→#0b0f11`, border `rgba(255,255,255,0.1)`, big drop shadow. Header (radar glyph + "Leak findings" + "scan 14:32"). Three finding rows, each with a colored left bar, class name (mono 12px), growth delta (e.g. `+48`), a severity tag pill (CRITICAL/WARNING/INFO), and a small **sparkline SVG** that draws in. Footer: "3 classes · 57 instances" + green "Scan now ↺".
    - Row 1: `ChatRoomController`, +48, CRITICAL (`#ff5d6c`).
    - Row 2: `VideoPlayerController`, +6, WARNING (`#f5b54a`).
    - Row 3: `_PresenceSubscription`, +3, INFO (`#5ad1e6`).
  - **Draggable overlay badge** (z-index 3, absolute top-right, floating animation): mono 12.5px 600, "3 leaks" with a glowing red dot and a `⠿` drag-handle glyph, bg `rgba(255,93,108,0.16)`, border `rgba(255,93,108,0.5)`, blur, pill radius. `cursor:grab`.
- **Duality strip** (below hero, full width): two equal cells separated by a 1px divider, rounded 16px container. Left cell — cyan "BEFORE SHIP" tag + "**Static lint.** 7 rules with auto-fixes…". Right cell — green "WHILE RUNNING" tag + "**Runtime detector.** Inspects the live heap…".

### 3. Problem (`#problem`)
- **Layout**: two-column flex-wrap, gap `clamp(32px,5vw,64px)`, centered.
- **Left**: amber eyebrow "THE PROBLEM" (`#f5b54a`), H2 "Memory growth is invisible — until it isn't." (Space Grotesk 600, `clamp(30px,4.6vw,52px)`), two paragraphs.
- **Right**: a **heap-growth chart card** — bg gradient `#0c1113→#090c0d`, radius 18px. Header "Heap usage · 90 min session" + "↑ 312 MB" in red. An SVG line chart (red `#ff5d6c`, steadily climbing, **draws in on scroll**) with 3 faint gridlines. X-axis labels: "00:00 / app feels fine → / OOM".

### 4. Two Halves (no id)
- **Centered header**: green eyebrow "CATCH LEAKS TWICE", H2 "Two halves of the same fix." (max-width 14ch).
- **Layout**: flex-wrap diptych — two cards `flex:1 1 340px` with a small circular **connector node** (`flex:0 0 auto`, self-center) between them holding a target-style SVG icon.
  - **LINT card** (left): cyan-tinted border `rgba(90,209,230,0.16)`, decorative ring top-right. Icon tile (cyan), label "STATIC · custom_lint", H3 "Stop it before it ships", paragraph, then a `›`-bulleted list of the 7 rules (undisposed controllers; uncancelled `StreamSubscription` & `Timer`; unclosed `StreamController`; discarded `.listen()` & missing `removeListener`; bloc subs not cancelled in `close()`). Footer mono note: "Understands if / try disposal, injected fields & locals."
  - **RUNTIME card** (right): green-tinted border `rgba(47,227,155,0.2)`. Icon tile (green), label "RUNTIME · on-device", H3 "Catch what slips through", paragraph, `›`-bulleted list (one `LeakRadar.init(...)` — no mixins; draggable badge; findings w/ sparklines & retaining paths; scan now/periodic/auto on screen-pop; export JSON/Markdown). Footer note: "Precise opt-in: track(obj) / markDisposed(obj)."

### 5. How it works (`#how`)
- Top border `1px solid rgba(255,255,255,0.06)`.
- Green eyebrow "HOW IT WORKS" + H2 "Drop it in. Get signal."
- **3-card grid**: `repeat(auto-fit, minmax(260px,1fr))`, gap `clamp(16px,2.2vw,24px)`. Each card: bg `#0a0e0f`, border, radius 18px, padding 28px. Big translucent number (Space Grotesk 700, 42px) — 01 green-tint, 02 cyan-tint, 03 amber-tint — H3, paragraph.
  - 01 **Add it** — two dev-deps + one `init` call, nothing to extend.
  - 02 **Run & analyze** — lint flags as you type; detector watches the heap (manual / periodic / screen-pop).
  - 03 **See leaks** — badge shows worst severity + count; tap for findings (severity, sparklines, retaining paths gc-root → object).

### 6. Feature bento (`#features`)
- Amber eyebrow "WHAT'S INSIDE" + H2 "A toolkit, not a checkbox."
- **12-column CSS grid**, gap `clamp(12px,1.6vw,18px)`:
  - **Zero-config detection** — `span 12`, green-tinted gradient. Headline "It tracks instance growth so you don't have to." + paragraph, with a 4-bar mini bar-chart (rising heights 34/52/70/100%, last bar solid green w/ glow, **animate in**).
  - **Retaining paths** — `span 7`. Cyan link icon, H3 "Retaining paths, on demand", paragraph, then a mono code block showing the tree (GC root → _ChatService._active → List<ChatRoomController> → **ChatRoomController ← leaked** in red).
  - **Triggers** — `span 5`. Green refresh icon, "Triggers that fit your flow", `NavigatorObserver` mention, then 3 chips: "Scan now", "Periodic", "On screen-pop" (last one green-highlighted).
  - **Export & share** — `span 4`. Amber upload icon, JSON/Markdown copy.
  - **Full heap snapshot** — `span 4`. Cyan file icon, capture `.dartheap` to file.
  - **Safe by construction** — `span 4`. Green shield-check icon, "Never throws… never slows… tree-shaken out of release builds."
- **Responsive note**: on narrow screens these spans must collapse — see Responsive behavior.

### 7. Real code (no id)
- Top border. Green eyebrow "REAL CODE" + H2 "This is the whole integration."
- **Tab toggle** (the one interactive control): pill container bg `#0a0e0f`, two buttons — "Runtime detector" and "Lint diagnostic". Active tab: bg `#2fe39b`, text `#07090a`. Inactive: transparent, `#8fa0a6`. Mono 13px.
- **Layout**: two columns — code editor pane (`flex:1 1 460px`) + side detail pane (`flex:1 1 280px`).
- **Editor pane**: bg `#06090a`, radius 16px, big shadow. macOS-style title bar (3 traffic-light dots + mono filename that swaps with the tab: `main.dart` / `chat_screen.dart`). Body is a syntax-highlighted `<pre>` (mono 13px, line-height 1.85). Highlight palette below.
  - **Runtime tab** code: import + `void main()` with `LeakRadar.init(autoScan: AutoScan.onScreenPop, overlay: true, threshold: Severity.warning); runApp(...)`, plus the optional `LeakRadar.track(controller); LeakRadar.markDisposed(controller);`.
  - **Lint tab** code: `_ChatScreenState` with `final _controller = TextEditingController();` where `_controller` carries a **red wavy underline** (`text-decoration: underline wavy #ff5d6c`) + a comment "🛑 leak_radar: TextEditingController is never disposed…".
- **Side detail pane** (content also swaps with tab):
  - Runtime: "WHAT YOU SEE ON DEVICE" + an amber "2 leaks" badge replica + explanation.
  - Lint: "QUICK FIX AVAILABLE" + a green diff block showing the added `dispose()` override + explanation that every rule ships an auto-fix.

### 8. Install (`#install`)
- Top border. Green eyebrow "INSTALL" + H2 "Three edits, then you're hunting." + paragraph + green "View on pub.dev →" button.
- **Right**: three stacked code cards (`flex:1 1 440px`, grid gap 14px), each bg `#06090a`, radius 14px, with a header strip (filename + "N / 3"):
  1. `pubspec.yaml` — `dev_dependencies:` with `leak_radar: ^1.0.0` and `custom_lint: ^0.6.0`.
  2. `analysis_options.yaml` — `analyzer: plugins: - custom_lint`.
  3. `main.dart` — `LeakRadar.init(overlay: true); runApp(const MyApp());`.

### 9. Footer
- Top border, bg `#06090a`. Left: radar glyph + "Leak Radar" + mono tagline. Right: two link columns — **Project** (GitHub, pub.dev, Documentation) and **On this page** (How it works, Features, Install). Links hover → green `#2fe39b`. Bottom bar: "MIT licensed · open source" + "Built by someone who's hunted these leaks."

---

## Interactions & Behavior
- **Tab toggle (code section)** — the only stateful control. Clicking "Runtime detector" / "Lint diagnostic" swaps: the editor filename, the code block, and the side detail pane. Default = Runtime. Implement as simple local state.
- **Scroll reveals** — every element marked `data-reveal` starts at `opacity:0; translateY(18px)` and transitions to `opacity:1; translateY(0)` over 0.7s `cubic-bezier(.22,1,.36,1)` when it enters the viewport (IntersectionObserver, threshold ~0.18, rootMargin bottom -8%). Add a safety timeout that force-reveals everything after ~4s so nothing can get stuck hidden.
- **SVG draw-in** — paths marked `data-draw` (the 3 sparklines + the heap chart line) animate `stroke-dashoffset` from full length → 0 over 1.5s `cubic-bezier(.4,0,.2,1)` when scrolled into view. Compute `getTotalLength()` on mount to seed `stroke-dasharray`/`offset`.
- **Radar sweep** — conic-gradient layer rotates 360° every 5s, linear, infinite.
- **Ring pulse** — a ring scales 0.55→1.25 and fades, 4s ease-out infinite.
- **Blips** — opacity/scale pulse, 2.4–3.3s staggered, infinite.
- **Overlay badge float** — translateY 0→-7px→0, 4s ease-in-out infinite.
- **Bar chart (zero-config card)** — bars `scaleY` from 0.25→1 over 1.2s ease-out, staggered 0.08s, on first render.
- **Button hovers** — primary green buttons lighten to `#52f0b0` (hero primary also lifts `translateY(-1px)`); ghost buttons/links lighten background.
- **Animate transform & opacity only.** No layout-animating properties.

### Accessibility & reduced motion
- A `@media (prefers-reduced-motion: reduce)` block **disables every animation**: sweep, blips, ring pulse, float, bar grow, and the draw-in (paths jump to final state); reveals show immediately; smooth-scroll is turned off. **Reproduce this — it is a hard requirement.**
- Decorative SVGs/layers use `aria-hidden="true"`. The heap chart has an `aria-label`.
- All nav links and tab buttons are real focusable elements; maintain visible focus and keyboard operability.
- Color contrast: body text `#a7b6bc`/`#c4d0d4` on near-black backgrounds meets AA for body sizes; keep these ratios.

## State Management
Minimal. One piece of UI state:
- `tab: 'runtime' | 'lint'` — drives the code section's filename, code block, and detail pane. Default `'runtime'`.

Everything else is static content + scroll-driven CSS/observer effects (no app state, no data fetching).

## Responsive behavior
Breakpoints to honor: **320 / 768 / 1024 / 1440**. The design uses fluid `clamp()` typography/spacing plus flex-wrap and grid auto-fit, so it mostly fluidly reflows. Key requirements:
- Hero columns and all two-column flex sections stack vertically below ~font-driven wrap (~900px and under).
- **Feature bento** 12-col spans must collapse on small screens — when rebuilding, make `span 7/5/4` items go full-width (or 2-up) below ~768px so cards don't get crushed. (In the HTML these spans don't yet reflow at the smallest widths — fix this in the rebuild.)
- Nav links may need a hamburger/menu on the smallest widths (currently they remain inline — acceptable but tight at 320px).
- Minimum tap target 44px on touch; minimum body text ~14px, code ~12.5px.

## Design Tokens

### Color
| Token | Hex | Use |
|---|---|---|
| Base / page bg | `#07090a` | page background |
| Surface 1 | `#0a0e0f` | cards |
| Surface 2 | `#0c1113` / `#0c1413` / `#0c1214` | gradient card tops, chips |
| Surface deep / code | `#06090a` | code blocks |
| Card gradient | `#0e1417 → #0b0f11` | hero device card |
| Text primary | `#e7eef0` | headings, key text |
| Text bright | `#d6e2e5` / `#cdd6da` | emphasis |
| Text secondary | `#a7b6bc` | body |
| Text muted | `#8fa0a6` / `#7d8e94` | sub-body |
| Text faint | `#5f7178` | captions/labels |
| Text faintest | `#3d4a4f` / `#4a5a60` | footer meta, code punctuation |
| **Accent green (radar)** | `#2fe39b` | primary accent, runtime |
| Accent green hover | `#52f0b0` | button hover |
| **Cyan (lint / info)** | `#5ad1e6` | static/lint, info severity |
| **Amber (warning)** | `#f5b54a` | warning severity |
| **Red (critical)** | `#ff5d6c` | critical severity, leak chart |
| Hairline border | `rgba(255,255,255,0.06–0.12)` | borders/dividers |
| Traffic lights | `#ff5f57` / `#febc2e` / `#28c840` | code title bar dots |

**Syntax-highlight palette** (code blocks): keyword/`import`/`const` `#ff85a1`; type/`void`/`bool` `#5ccfe6`; function name `#82aaff`; string `#c3e88d`; bool literal `#f78c6c`; comment `#5f7178`.

### Typography
- **Headlines / wordmark / numbers**: `Space Grotesk` (400–700). H1 `clamp(40px,6.6vw,76px)`/0.98/-0.03em; section H2 `clamp(28px,4.4vw,52px)`/1.04/-0.025em.
- **Body / UI**: `Hanken Grotesk` (400–700). Body `clamp(15px,1.7vw,19px)`/~1.6.
- **Code / metrics / labels**: `JetBrains Mono` (400–700). Code 12.5–13px/1.75–1.85; labels/eyebrows 11–12px uppercase, letter-spacing 0.05–0.12em.
- Loaded via Google Fonts. Use `text-wrap: balance` on headings, `text-wrap: pretty` on body.

### Spacing / radius / shadow
- Section vertical padding: `clamp(60px,9vw,120px)` (hero a bit more on top); content max-width 1240px; horizontal pad `clamp(18px,4vw,40px)`.
- Radii: pills 999px; large cards 20px; medium cards 16–18px; code cards 14–16px; small chips/tags 4–8px; buttons 9–11px.
- Shadows: hero card `0 40px 90px -30px rgba(0,0,0,0.8)`; code pane `0 30px 70px -30px rgba(0,0,0,0.7)`; primary button `0 8px 30px rgba(47,227,155,0.22)`.
- Ambient backdrop: radial glows in green/cyan + a 64px dotted grid at low opacity, masked to the top.

## Assets
- **No raster images.** All visuals are inline SVG (radar rings, icons, sparklines, charts, GitHub glyph) + CSS. Icons are simple stroke icons in the Feather/Lucide style — replace with the codebase's existing icon set if one exists, matching stroke weight (~2) and the severity colors above.
- **Fonts**: Space Grotesk, Hanken Grotesk, JetBrains Mono (Google Fonts). Self-host in production for performance.
- **Emoji**: a single `🛑` appears in the lint diagnostic comment (intentional — it mimics an editor lint marker). Keep or swap for an icon.

## Files
- `Flutter Leak Radar.dc.html` — the complete landing-page design reference (markup + the tab logic + all motion). Open in a browser to view. **Reference only — do not ship.**

---

## Recommended implementation approach
1. Pick the stack (Astro / Next static / plain HTML+CSS — it's a static page; avoid over-engineering).
2. Self-host the three fonts; set up the color + type tokens above as CSS custom properties or Tailwind theme values.
3. Build the fixed background layers, then each section top-to-bottom as documented.
4. Implement the **one** interactive control (code-section tabs) with local state.
5. Add IntersectionObserver scroll reveals + SVG draw-in; gate ALL motion behind `prefers-reduced-motion`.
6. Verify responsive reflow at 320 / 768 / 1024 / 1440 — especially the feature bento spans (must collapse) and stacked hero.
