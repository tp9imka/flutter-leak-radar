# Designer brief — "Android Profiling" section (Radar Desktop)

**Type:** functional brief / UX spec request. **From:** engineering. **For:** product designer.
**Date:** 2026-07-03. **Status:** ready for design.

This is a **functional** brief — it describes users, jobs, data, flows, and states. It does **not** prescribe visuals; layout, hierarchy, and motion are yours. Please return a UX specification (screens, states, flows, component behaviour) that we'll reconcile into an engineering spec before building.

---

## 1. Where this lives

Radar Desktop is **one unified, offline-first profiling application** for diagnosing Flutter memory problems from captured artifacts (no live app required). It already has a Dart-heap analysis surface (class histogram, retaining paths, diff, trends across N snapshots). The **Android Profiling section** is a new peer surface inside that same app — reached from the app's main navigation rail — plus a small **"tools"** area for capture/import helpers. It is not a separate product.

**Design system:** reuse the existing `radar_ui` tokens (colour, typography, density, severity) and the app's existing rail/scaffold. This section should feel like the same app, one tab over — not a bolt-on.

---

## 2. The problem it solves

The Dart-heap lane can only see Dart objects. On Android, a large class of leaks lives **below** Dart — native `malloc` growth from the Flutter engine, plugins, C/C++, `dart:ffi`, and GPU/image handles. When a user has ruled out the Dart heap but memory still climbs, this section is where they go. **Primary and only target for v1: Android.**

---

## 3. What is technically REAL (design for this, not more)

We ran the capture/analysis spikes on a real Android device. The honest capability matrix — please design to exactly this, including the degraded/uncertain cases:

| Capability | Reality (proven on-device) | Design implication |
|---|---|---|
| **Native heap "still-live" (the anchor)** | heapprofd → Perfetto trace. We compute **still-live bytes = allocated − freed** per allocation call site, across ≥2 checkpoints. Real and reliable. | This is the centrepiece view. Rank by still-live bytes and by **growth between checkpoints**. |
| **Module attribution** | Every leak resolves to a **module** (`libflutter.so`, the app's `base.apk`, `vulkan.adreno.so` GPU driver, `libc++.so`, …). Proven: a known app leak attributed cleanly to `base.apk`, separate from engine/GPU churn. | "Which component is leaking" is always answerable. Module is the primary grouping. |
| **Function-name attribution** | **Not free.** Call-stack frames come back with the module but **empty function names** unless we match the module's build-id against an **unstripped `.so` symbol store**. Build-ids are present; symbols are a separate input the user may or may not have. | Design for **two fidelity levels**: module-only (always) and fully-symbolized (when a symbol store is provided). Show which state you're in. Make "add symbols" an obvious, optional action. |
| **ffi allocation leaks (opt-in)** | If the app opts into our logging allocator, we get **still-live ffi blocks each with an exact Dart stack** (`file:line`) — fix-grade, works in release-shaped builds. Requires the app to have integrated it. | A distinct, higher-fidelity lane that only appears when this data is imported. Its detail = a real Dart stack, unlike the native lane. |
| **GPU / image leaks** | **No dedicated hook.** The framework's `FlutterMemoryAllocations`/leak_tracker is **debug-only** — it fires for nothing in profile/release, which is what people profile. GPU/image leaks instead surface **inside the native heap lane** as bytes attributed to GPU-driver modules. | Do **not** design a separate "images/textures" tracker for v1. Treat GPU/driver modules as first-class rows in the native lane, clearly labelled. |
| **GPU total bytes** | Vendor-dependent; frequently reads **0** on many devices. | If shown at all, **honest-degradation**: "not reported on this device," never a silent 0 that reads as "no problem." |
| **True-leak vs. growing-cache** | still-live accounting alone **cannot** tell a leak from an unbounded-but-reachable cache. | The UI must not claim "leak" with certainty from bytes alone. Prefer "still-live / growing" language; leave room for a future "unreachable" discriminator. |

**The honesty rule (load-bearing):** every number must carry its confidence. Module-level is certain; function names are conditional; GPU totals are often unavailable. A design that renders all of these with equal visual authority would lie. We need explicit visual treatment for "measured," "estimated," and "not available on this device."

---

## 4. Users & jobs-to-be-done

Primary user: a **Flutter engineer at KATIM** debugging an Android memory problem, working from captured artifacts at their desk (often after a QA/soak run).

Jobs:
1. **"Something native is growing — what and where?"** Import captures, see still-live native memory ranked by module/callsite, find the growth.
2. **"Is it getting worse over time?"** Compare two checkpoints (or a series) and see what grew — the diff is the core insight.
3. **"Give me enough to fix it."** Drill from module → callsite → (if symbols) function, or (if ffi lane present) → exact Dart stack.
4. **"Is this a leak or just a big cache?"** Understand the limits of what's shown; not be misled.

---

## 5. Core workflow (import-first)

1. **Get data in.** Either (a) **import** an existing Perfetto `.pftrace` / captured artifact, or (b) use the **capture tool** (drives `adb`/heapprofd against a connected device — a guided helper in the tools area). Optionally add a **symbol store** and/or an **ffi allocation log**.
2. **Land on the native still-live overview** for the most recent checkpoint.
3. **Compare** two checkpoints → the growth/diff view.
4. **Drill** into a module/callsite → detail, with whatever fidelity the imported inputs allow.
5. (If ffi log present) **switch to the ffi lane** → still-live blocks with Dart stacks.

Everything is offline and re-analysable from files. A "session" can hold multiple checkpoints + optional symbol store + optional ffi log.

---

## 6. Screens / views to design

For each, please design **empty, loading, populated, degraded (partial fidelity), and error** states.

1. **Section entry / session overview** — what's imported (checkpoints, whether symbols/ffi present), quick totals, entry points to the views below. Make the fidelity state obvious here.
2. **Native still-live overview** — ranked list/table of still-live memory. Primary grouping **by module**, expandable to callsites. Columns: still-live bytes, allocation count, module, (function if symbolized). Sortable. This is the workhorse view — its density and scannability matter most.
3. **Checkpoint compare (diff)** — pick two checkpoints; show **growth** per module/callsite (added / grew / shrank / gone). This is where "is it getting worse" is answered. Consider a two-picker like the existing Dart-heap compare.
4. **Callsite / module detail** — the native call stack (module-labelled frames; function names when symbolized), the still-live figure, its trend across available checkpoints, and a clear "add symbols to see function names" affordance when unsymbolized.
5. **ffi allocations lane** (conditional — only when an ffi log is imported) — still-live ffi blocks grouped by Dart allocation site, each with a real `file:line` stack. Higher-fidelity sibling to the native view.
6. **Capture / import tool** (tools area) — guided flow to import a `.pftrace`, attach a symbol store, attach an ffi log, or run a device capture. Communicate prerequisites and the device/build caveats plainly.

Optional (nice-to-have, not v1-blocking): a lightweight **memory-over-time trend** strip (native bytes across checkpoints) echoing the existing Dart-heap trends view.

---

## 7. Constraints & non-goals

- **Desktop, offline, import-first.** No dependency on a live app for analysis.
- **Android only** for v1.
- **Reuse `radar_ui`** and the existing app shell; this is a section, not a new skin.
- **Non-goals for v1:** a live/streaming profiler; a dedicated image/texture tracker (folded into native lane); reliable GPU totals; iOS. Don't design these in.

---

## 8. What we need back

A UX specification covering: the section's information architecture and how it sits in the existing rail; each view above with its states; the fidelity/confidence visual language (measured vs. estimated vs. unavailable); the compare/diff interaction; and the import/capture flow. Once we have it, we'll brainstorm to reconcile it with these engineering realities, write the implementation spec, and build.

_Grounding: `docs/specs/2026-07-02-native-gpu-leak-analysis-design.md`, `docs/specs/2026-07-02-native-gpu-review.md` (§5 recommended path), and the on-device spike results in `docs/spikes/2026-07-03-native-gpu-spike-results.md`._
