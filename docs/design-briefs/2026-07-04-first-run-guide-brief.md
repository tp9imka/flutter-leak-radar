# Designer Brief — Radar Desktop first-run guide

**What we need from you:** a UX spec for a **first-time onboarding guide** in the Radar Desktop app that (a) is shown **once** on first launch, (b) can be **skipped** at any point, and (c) **highlights the full set of features and capabilities** so a new user immediately understands the app's breadth. We'll implement it in Flutter afterward, so the spec should be concrete about layout, copy, interactions, states, and the persistence/skip behavior.

---

## 1. What Radar Desktop is (context you're designing for)

**Radar Desktop** is a **macOS-first desktop analyzer** in the "Radar" observability suite for Flutter. It's a dense, professional developer tool (think DevTools / a profiler), not a consumer app. A developer opens it to analyze memory, performance, stability, and native-heap data — either from **offline captures** or from a **live connection** to a running app.

**Design language (match it — do not invent a new look):**
- Dark, low-chrome, information-dense. Existing design system: `radar_ui` tokens — a near-black surface palette, an accent **green `#2fe39b`**, plus **amber** (warnings) and **cyan** accents used semantically. Monospace for data/paths, a display face for headings. Radar/instrument motif (concentric rings, a sweep, blips) is the brand.
- The window has a **custom title bar** (frameless, traffic-lights kept) with a small **tool-health dot**, a **Connect bar** strip under it, a **left navigation rail** grouped into sections, and a content area on the right.
- Voice: precise, honest, no marketing fluff or overclaiming. It states real behavior (e.g. "not detected", "module-only") rather than hype.

## 2. The full feature set to surface (this is what the guide must cover)

Organize the tour around these; the user should leave knowing all of them exist:

**A. Memory — offline analysis (no running app needed).** The default surface. Import a heap-snapshot dump or a Perfetto `.pftrace` (button OR **drag-and-drop anywhere**). Then: **Dumps** list, **Class histogram**, **Retaining paths** (why an object is kept), **Compare** any two dumps, **Trends** across a soak.

**B. Connected mode — attach to a running app.** The **Connect bar** takes a `ws://…/ws` Dart VM Service URI; connecting **unlocks** the otherwise-locked **Performance** (Traces, Frames) and **Stability** (Errors, Stalls) rail groups, plus **live heap capture** and **Force GC**. Two ways to get the URI: paste it, or tap **Scan device** (Android) — it reads `adb logcat`, forwards the port, and fills the field for you. Honest degradation: if the target app doesn't embed the perf runtime, the perf/stability views say "not detected" rather than faking data.

**C. Android Native profiling — below the Dart heap.** Capture native-heap allocations from a device via `adb` + heapprofd + Perfetto. **Run device capture** (pick device / package / mode / duration), or import a `.pftrace`. Then: **per-module still-live** analysis (which `.so` holds retained native memory), checkpoint **Compare/diff**, an **FFI-allocations** lane, and **native symbolization** — **Resolve from .so directory** turns module-only frames into real function names via `llvm-symbolizer`.

**D. Tools — the external-tool manager.** A **Tools** screen (and a **health dot** in the title bar that goes amber when something's missing) shows each required CLI tool — `trace_processor`, `adb`, `llvm-symbolizer/llvm-readelf` — as **found (path + version)** or **missing**, with **Install** (one-click for `trace_processor`), **Locate…**, and **Re-check**. This is how a Finder-launched app finds its tools; worth surfacing because it's the thing a new user hits first if a tool is absent.

**E. Quality-of-life.** Every error has a **Copy** action (one tap to share the full message). The rail is grouped: **MEMORY · PERFORMANCE · STABILITY · ANDROID NATIVE · TOOLS** (perf/stability are visibly locked until connected).

## 3. Hard requirements for the guide

- **Shown once.** Appears automatically on the very first launch (fresh install / no persisted "seen" flag). Never again after it's completed or skipped. Specify the persistence: a boolean like `hasSeenFirstRunGuide` in the app-support store.
- **Skippable at any point** — a clear, always-visible Skip/Close that ends the guide immediately (and marks it seen).
- **Non-blocking & safe** — must not trap the user or gate real work behind it; it should feel optional. Decide whether it overlays the real UI or is a standalone welcome flow.
- **Re-openable on demand** — since it's once-only, define a way to reopen it later (e.g. a "Show guide" / "?" affordance in the title bar or Tools screen). Note where it lives.
- **Covers everything in §2** without being exhausting — you decide the right depth per step and how to group.
- **Accessible & calm** — keyboard-navigable (Esc to skip, arrows/Enter to advance), respects `prefers-reduced-motion` (no motion that ignores it), sufficient contrast on the dark surface.
- **Self-contained** — no external assets/fonts/network; reuse `radar_ui` tokens and the app's existing components/iconography. Any illustration must be describable/implementable in Flutter (SVG/canvas/widgets), not a raster from a design tool.

## 4. Open design decisions — please choose and justify in the spec

1. **Format.** Which pattern, and why: (a) a **welcome modal + multi-step carousel** (4–6 slides, each a feature area with a small illustration + 1–2 lines + primary/skip); (b) **coach-marks / spotlight** that dim the app and point at the real rail groups + Connect bar + health dot in sequence; (c) a **dedicated Welcome screen** shown first (a rail-less full view) with a feature grid; or (d) a hybrid (e.g. a short welcome, then optional spotlights). Consider the app's density and that some features (Performance/Stability) are locked until connected — a spotlight tour has to handle locked/disabled targets gracefully.
2. **Depth & grouping** of §2 into steps (how many, what each says). Keep copy tight and in the app's honest voice.
3. **Entry & exit**: the first frame the user sees, the Skip affordance, the final step's CTA (e.g. "Import a dump" / "Open Tools to set up" / "Done"), and where the re-open entry point lives.
4. **Visual treatment**: how each feature is illustrated (reuse real screenshots/components vs. simple diagrams vs. the radar motif), and how it reads at the app's typical window size (~1180×760) down to the min (920×600).
5. **State handling**: what a step shows when a prerequisite is absent (no device connected, no tools installed, nothing imported) — the guide should still explain the feature honestly.

## 5. Deliverable (what the spec should contain)

- A short **rationale** for the chosen format (§4.1).
- **Step-by-step or screen-by-screen**: for each step — its purpose, exact **copy** (headline + body + button labels), **layout** (what's where), **interaction** (advance/back/skip/keyboard), any **illustration/anchor** (which real UI element or diagram), and **states** (reduced-motion, locked-feature, prerequisite-absent).
- The **once-only + skip + re-open** behavior spelled out (persistence flag, triggers, the re-open entry point).
- **Accessibility** notes (keyboard map, focus order, contrast, reduced-motion).
- **Responsive** notes for ~1180×760 and the 920×600 minimum.
- Reference the real app structure in §1–§2 so it maps 1:1 to what exists (we'll reconcile any deltas before building).

Keep it implementable in Flutter with `radar_ui` — favor real components and the existing motif over bespoke art. When you're done we'll reconcile the spec against the shipped app and I'll build it.
