# Flutter Leak Radar — Design Handoff

This bundle contains the complete design for **Flutter Leak Radar**, an open-source memory-leak toolkit for Flutter. It is split into two deliverables, each in its own folder with its own detailed README:

| Folder | What it is | Target |
|---|---|---|
| **`landing_page/`** | The marketing/landing **website** | A static web project (Astro / Next static / plain HTML+CSS) |
| **`app_ux/`** | The **in-app UX** the Flutter library renders on-device | The Flutter package itself (Dart / Flutter widgets) |

## How to use this with Claude Code
The HTML files in each folder are **design references** — high-fidelity prototypes of look, copy, and behavior, authored in HTML. They are **not production code to copy**. The `.dc.html` files depend on a small runtime (`support.js`) used only for previewing; **do not ship it**. Recreate each design in its proper target environment using that codebase's existing patterns.

Read each folder's `README.md` first — they are self-sufficient specs (exact colors, type, spacing, layout, interactions, state) that someone who wasn't in the design conversation can build from.

## Shared design language (both surfaces)
- **Base**: near-black graphite — page `#07090a`, surfaces `#0a0e0f`/`#0e1316`, deep `#06090a`.
- **Accent**: radar green `#2fe39b` (hover `#52f0b0`).
- **Severity**: critical `#ff5d6c`, warning `#f5b54a`, info `#5ad1e6`.
- **Type**: Space Grotesk (headlines/numbers), Hanken Grotesk (body), JetBrains Mono (code/metrics/labels).
- **Motif**: a radar/instrument theme (concentric rings, sweep, signal blips) used sparingly as texture.
- **Tone**: precise, confident, a little wry. Short concrete copy, no marketing fluff.
- All motion is `transform`/`opacity` only and must degrade under `prefers-reduced-motion`.

> Note: the app UX uses the *same* dark brand palette as the website intentionally — it is a developer overlay, not a Material-themed end-user screen. Keep the on-brand dark treatment when implementing.
