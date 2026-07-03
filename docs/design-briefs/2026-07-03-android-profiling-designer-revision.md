# Revision request — Android Native Profiling prototype (v1.1)

Thanks — the **GONE** compare-status and the new **`system`/Runtime** module kind are exactly right, and the Compare colors (added/grew = red, shrank/gone = green) and the GPU-total "not reported · n/a on this device" honesty treatment are correct as-is. Four things to tighten before this is buildable. They're all in the "ANDROID NATIVE" section of `Flutter Radar - Desktop.dc.html`.

## 1. Module-only fidelity tag must be AMBER, not grey (honesty rule — highest priority)
In the **Detail → Native call stack**, when no symbol store is attached (the default), each frame's micro-tag currently renders **grey `#5f7178`** — the same muted grey used for ordinary secondary text everywhere else. The spec makes this the load-bearing rule: **module-only must read as amber `#f5b54a`**, visually distinct from "measured/certain." It's also internally inconsistent right now: the stack **section header** already shows amber for "module-only," while every frame tag beneath it shows grey — same fidelity state, two colors, in one view.
- **Change:** module-only frame tags → amber `#f5b54a`. Keep symbolized = green `#2fe39b`; keep the "vendor frame unresolved even with symbols" sub-case = amber. Net: measured = green, anything-not-fully-symbolized = amber, nothing in this axis uses plain grey.

## 2. Call-site totals must track the selected checkpoint
Module `still-live`/`allocs` are per-checkpoint, but each call-site's numbers are **fixed to the last checkpoint**. So when the checkpoint picker moves off the newest snapshot, a module and its own call-sites disagree:
- Pick `trace_00h`: `base.apk` shows **12.6 MB**, but expanding it lists call-sites summing to **68.2 MB** (~5.5× the parent).
- At early checkpoints, `libtflite.so` shows a **5 MB** module row but **zero** call-sites (its one site is 0-bytes and gets filtered out).
- **Change:** make call-site `still-live`/`allocs` per-checkpoint (arrays, like the module rows), so at every checkpoint a module's call-sites sum to the module's own displayed number, and a module with non-zero bytes always shows the call-sites that make it up.

## 3. Make the status set match the claim (SHRANK vs FLAT)
The seed data only ever increases or drops-to-zero, so **SHRANK never actually appears** — yet the spec says "all four statuses are visible." Meanwhile a **Δ = 0** pair produces an **undocumented grey FLAT** status (reachable via the `00h→06h` picker).
- **Change (preferred):** add seed data where a module **shrinks** between two checkpoints so ADDED / GREW / SHRANK / GONE are all reachable; and decide the no-change case explicitly — either suppress zero-delta rows, or document FLAT as an intentional 5th state with its own treatment. (If you'd rather not touch the data, instead soften the README's "all four visible" claim — but showing a real SHRANK is the stronger demo.)

## 4. Fully wire the new `system`/Runtime module kind
`system` was added to the data (`libc++_shared.so`) but only half-threaded:
- It's **missing from the table's color legend** (which still lists only app/GPU/engine/plugin).
- It uses an **ad-hoc grey `#7d8e94`** that isn't in the declared token set (`#8fa0a6 / #5f7178 / #3d4a4f`).
- The row **mini-bar** colors engine + plugin + system all the same green, so `libflutter.so` (engine, grey dot) and `libc++_shared.so` (system) render green bars that contradict their own row-dot colors and the "engine = grey" legend.
- **Change:** add `system`/Runtime to the legend with a defined token; give the mini-bar a per-kind color for all **five** kinds that matches each row's dot; pick the fifth color from the existing grey tokens rather than a new ad-hoc one.

## Keep as-is
GONE compare status + its green color; ADDED/GREW = red; GPU-total "n/a on device" (never a silent 0); the fidelity banner's amber; the measured tiles' green. Don't regress these.
