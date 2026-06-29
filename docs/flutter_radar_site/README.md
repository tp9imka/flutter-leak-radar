# Flutter Radar — Marketing Site (Design Handoff)

A four-page marketing/landing site for **Flutter Radar**, an open-source on-device + DevTools observability suite for Flutter (Memory · Performance · Stability). These are **high-fidelity design references authored in HTML** — recreate them in your real web stack; do not ship them as-is.

## Pages
| File | Purpose | Accent |
|---|---|---|
| `Flutter Radar.dc.html` | Overview / home — hero, the problem, three pillar cards, on-device ↔ DevTools delivery split, how-it-works, safe-by-construction, install | radar green `#2fe39b` |
| `Memory.dc.html` | Pillar page — runtime leak detection, the 7-rule `custom_lint` plugin, on-device UX (retaining paths, triggers, snapshot, export), DevTools capture→diff, code samples | green `#2fe39b` |
| `Performance.dc.html` | Pillar page — dense Traces table (all metrics + HOT/duplicate detection), trace drill-down, frames/jank, rebuilds, startup, tracing API | amber `#f5b54a` |
| `Stability.dc.html` | Pillar page — grouped uncaught errors + repeat counts + stack drill-down, main-thread stall watchdog, zone-wiring code | cyan `#5ad1e6` |

Pages cross-link by relative filename (top nav + pillar-to-pillar cards + footer). The lint plugin is presented **under Memory** (static prevention), since the product is now three pillars.

## How to use with Claude Code
- The `.dc.html` files depend on `support.js` (a preview runtime) only for local viewing — **do not ship `support.js`** or the `.dc.html` wrappers. Rebuild each page in the target stack.
- Recommended stack: a static site (Astro / Next static export / plain HTML+CSS). It's mostly static marketing with light interactivity (a couple of code-tab toggles + scroll reveals) — no SPA framework needed.
- Each page is self-contained; lift layout, copy, and exact tokens directly from the markup.

## Design system (all pages)
- **Base** near-black `#07090a`; surfaces `#0a0e0f`; code blocks `#06090a`; hairlines `rgba(255,255,255,0.06–0.12)`.
- **Accent** radar green `#2fe39b` (hover `#52f0b0`); pillar tints amber `#f5b54a`, cyan `#5ad1e6`; severity red `#ff5d6c`.
- **Type**: Space Grotesk (headlines), Hanken Grotesk (body), JetBrains Mono (code/metrics/labels). Numbers use tabular figures (`font-variant-numeric: tabular-nums`).
- **Motif**: radar/instrument (concentric rings, sweep, signal blips) used sparingly as texture.
- **Motion**: scroll-reveal (fade+rise) + the hero radar sweep/blips, all transform/opacity, fully disabled under `prefers-reduced-motion`. Mirror that fallback.
- **Layout**: 1240px max content width; fluid `clamp()` type/spacing; flex-wrap + grid `auto-fit`; responsive 320→1440. Semantic landmarks (`nav`/`header`/`section`/`footer`), keyboard-focusable nav + code tabs.

## Voice
Precise, confident, a little wry. Short concrete copy, no marketing fluff. Every metric shown is a truthfully-measured example, not a vanity number.

## Files
- The four `.dc.html` pages (reference only).
- `support.js` — preview runtime, **do not ship**.
