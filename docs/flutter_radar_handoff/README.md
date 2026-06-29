# Flutter Radar — Design Handoff (v2: observability suite)

**Flutter Radar** is an on-device + IDE observability suite for Flutter apps. During development (debug/profile builds; fully invisible/no-op in release) it surfaces three domains:

- **Memory** — leak detection (objects retained after they should be freed; per-class heap growth; retaining paths).
- **Performance** — execution traces (timed spans), frame/jank timing, widget rebuild counts, startup time.
- **Stability** — uncaught errors and main-thread stalls (ANR-like freezes).

> This supersedes the earlier "Flutter Leak Radar" leak-only design. The product is now **Flutter Radar** and covers all three domains; leaks are one domain. Build from these files; the diff against the old `design_handoff/` is intentional.

## Two delivery contexts (both designed here)
| Folder | Surface | Target | Width |
|---|---|---|---|
| **`inspector/`** | In-app overlay badge + full-screen Inspector (Leaks · Performance · Stability) | Flutter widgets, inside the running app | narrow phone (412dp) |
| **`devtools/`** | DevTools companion panel (capture→diff spine, histogram, retaining paths, + Performance/Stability) | Flutter DevTools extension (Flutter/web) | wide desktop (~1320px) |

The two share one design language and one data model; they differ in layout density and breakpoint. The narrow phone collapses wide tables to 2-line rows + drill-downs; the wide DevTools shows the full multi-column tables.

## How to use this with Claude Code
The `.dc.html` files are **high-fidelity, fully interactive design references** — they encode layout, copy, density, states, sorting/search/drill-down behavior, and the capture→diff flow. They are **not production code to ship**: they depend on a preview runtime (`support.js`) and, for the phone, a device-frame harness (`android-frame.jsx`). **Do not ship those.** Rebuild each surface in its proper target (Flutter widgets / DevTools extension) using that codebase's patterns.

Read each folder's `README.md` — they are self-sufficient specs (exact tokens, row anatomy, every state, interaction model) written for someone who wasn't in the design conversation.

## Decisions locked in this round
- **Dark-only.** No light theme. The accent-led graphite treatment is intentional (devtool norm, brand).
- **Name:** Flutter Radar.
- **Breakpoints mocked:** narrow phone + wide DevTools (the two that differ most). Tablet sits between them and reuses the wide table patterns at reduced column counts — noted per surface, not separately mocked.
- **Every surface is interactive** (all 3 tabs, all 4 Performance sub-sections, all drill-downs, the DevTools capture→diff). Empty / loading / not-measured / disconnected states are demonstrated live (see per-surface notes).

---

## Shared design language

### Color (dark-only)
| Token | Hex | Use |
|---|---|---|
| bg / canvas | `#090c0d` (phone) · `#0b0e10` (page) | base |
| panel / devtools shell | `#0c1012` | app bars, devtools chrome |
| surface (cards) | `#0e1316` | cards, stat tiles |
| surface raised / input | `#11171a` | inputs, segmented controls |
| table header | `#0b0f11` | sticky column headers |
| code / mono blocks | `#06090a` | retaining paths, stack traces |
| **accent — radar green** | `#2fe39b` | primary actions, "connected", healthy |
| **critical** | `#ff5d6c` | critical sev, growth↑, jank, errors |
| **warning** | `#f5b54a` | warning sev, hot/dup, stalls |
| **info / secondary** | `#5ad1e6` | info sev, totals, links, lint domain |
| text primary | `#e7eef0` | values, names |
| text secondary | `#a7b6bc` / `#cdd6da` | body, sub-metrics |
| text muted | `#8fa0a6` / `#7d8e94` | captions |
| text faint | `#5f7178` | labels, units |
| text faintest | `#3d4a4f` / `#4a5a60` | chrome, tree connectors, zeros |
| hairline | `rgba(255,255,255,0.04–0.12)` | borders, dividers |

Severity → color is the spine of the whole UI: critical `#ff5d6c`, warning `#f5b54a`, info `#5ad1e6`, healthy/accent `#2fe39b`.

### Typography
- **Headlines / big metric values**: Space Grotesk 600.
- **Body / labels**: Hanken Grotesk 400–600.
- **All numbers, code, table data, units, tags**: JetBrains Mono — **with tabular figures** (`font-variant-numeric: tabular-nums`) so columns align. In Flutter: `FontFeature.tabularFigures()`. This is non-negotiable for the dense tables.

### Density (primary goal — the old build was "too sparse")
- Table/list rows are tight: ~34–40px, vertical padding 8–9px.
- Numbers right-aligned, tabular, mono. Labels small (9.5–11px). Minimal chrome between rows (1px hairline, no card-per-row in tables).
- Metric prominence by size + color, not by box. Pack signal per row.

### Honest metrics & states
Every number is truthfully measured. Design must handle, per surface:
- **empty** ("no findings", "capture a snapshot"),
- **loading** (spinner + label, e.g. while capturing/scanning),
- **not measured / N/A** (e.g. Startup not captured — never imply a value),
- **error / degraded** (VM connection lost → on-device fallback).
All five are demonstrated in the prototypes (see per-surface READMEs for how to trigger them).

### Motion
Slow `rdr-live` pulse on "active"/"connected" dots, a spinner on capture, optional bar grow-ins. All `transform`/`opacity`. Everything is disabled under `prefers-reduced-motion` — mirror with a reduced-motion / accessibility flag in Flutter.

### Cross-cutting interaction contract (every list/table)
- **Sortable** — column headers (or a sort control on phone) toggle key + direction; active key shows ↓/↑ in accent green.
- **Search/filter** — a mono text field filters by name/library/category; quick-filter chips for common cuts (errors-only, hot/duplicate, by kind).
- **Drill-down** — every row opens a focused detail (retaining path, latency distribution, stack trace).
- **Export** — JSON / Markdown where data is worth saving (findings, trace report, snapshot diff).
- **Empty result** — searching to zero shows an explicit empty state, not a blank list.

See `inspector/README.md` and `devtools/README.md` for the full per-surface specs.
