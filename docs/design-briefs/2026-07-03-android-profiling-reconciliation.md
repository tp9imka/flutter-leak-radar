# Reconciliation — designer UX spec ↔ engineering reality

**Inputs:** designer handoff `docs/flutter_radar_android_profiling/` (README + `Flutter Radar - Desktop.dc.html`) ↔ proven capabilities in `docs/spikes/2026-07-03-native-gpu-spike-results.md` and the merged `radar_native` package.
**Verdict:** the design is **strong, faithful, and buildable.** It honored the honesty rule, the IA, folded Lane C into the native lane, and made the ffi lane conditional — all matching what the device proved. Below: where it aligns, and the concrete engineering deltas the build phase must close.

## Aligns cleanly (no change needed)
- **Fidelity model** (measured / module-only / n/a-on-device) ↔ spikes exactly: still-live + module = measured; function names = conditional on a symbol store (build-ids are present, confirmed); GPU total = frequently 0 = n/a.
- **Module color-tags** (app / GPU-driver / engine / plugin) ↔ real modules observed: `base.apk`=app, `vulkan.adreno.so`/`libGLESv2_adreno.so`=GPU-driver, `libflutter.so`=engine.
- **ffi lane** with real `file:line` Dart stacks ↔ Spike 3 (exact stacks, works in profile).
- **"still-live / growing," never "leak"** ↔ the still-live-can't-distinguish-cache caveat.
- **Data shape** the Native table wants (module ▸ callsite · still-live bytes · alloc count · Δ) ↔ `NativeHeapProfile`/`NativeCallsite` fields as built.

## Engineering deltas to close (in the analysis/parser layer, before the UI)
1. **Compare needs a `GONE` status — the merged `diffNativeProfiles` drops before-only callsites.** The design's Compare view (`.dc.html` L930–963) shows ADDED / GREW / SHRANK / **GONE** (seed has a freed tflite buffer as GONE). Current `radar_native.diffNativeProfiles(before, after)` zero-baselines new callsites but **drops** those present in `before` and absent in `after`. **Change:** extend the diff to also emit removed callsites (negative growth / a `gone` marker), or add a diff variant that does. Lives in `radar_native` (pure). Also fold in the deterministic tie-break already logged as a fast-follow.
2. **Module grouping must use the CALLER module (walk past the allocator).** The Native table groups by module; the parser faithfully records leaf-first frames whose **leaf is always `malloc`/`calloc` in `libc.so`**. Grouping by the leaf module would label everything "libc." **Add** a pure helper — `attributedModule(NativeCallsite)` — that skips allocator frames (`malloc`/`calloc`/`realloc`/`free`/`operator new`, and the `libc.so` leaf) and returns the first meaningful caller module (proven: gives `libflutter.so` / `base.apk` / `vulkan.adreno.so`). Lives in `radar_native`.
3. **Module-kind classification.** The color-tags need `moduleKind(module) → {app, gpuDriver, engine, plugin, system}`. Rules from observed modules: the app's own `base.apk` / package path → **app**; `libflutter.so` → **engine**; names matching `adreno`/`mali`/`libGLES`/`vulkan`/`egl` → **gpuDriver**; other app-bundled `.so` (plugins) → **plugin**; `libc*`/`libutils`/system paths → **system**. Pure helper in `radar_native` (data-driven, not hardcoded to one vendor).
4. **Symbol store & ffi log are separate importers** (deferred, not v1-parser scope): symbol store = build-id → unstripped `.so` lookup that fills empty `NativeFrame.function`; ffi log = ingest the Spike-3 `LoggingAllocator` dump into the ffi lane. The current parser already carries `buildId` through for (a). Each is its own follow-on task.
5. **Large-trace UX** (design's 331 MB loading state): the `Process`→`trace_processor` runner handles large traces natively; the Dart side just awaits. The desktop layer runs it off the UI isolate. No parser change — note for the desktop integration.

## Sequence
Parser (in progress) → the 3 pure `radar_native` analysis helpers above (GONE-aware diff, `attributedModule`, `moduleKind`) → capture backend (adb/heapprofd) + symbol-store & ffi-log importers → rebuild the 6 views as Flutter widgets on `radar_ui`, using the `.dc.html` as the visual reference. No new design system, no new analysis engine — as the handoff requires.
