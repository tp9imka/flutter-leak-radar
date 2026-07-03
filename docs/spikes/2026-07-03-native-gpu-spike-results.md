# radar_native v1 — device spike results

Device: **KATIM X3M "sadeem", Android 15 (SDK 35), userdebug, arm64-v8a**. `adb root` = uid 0.
Tools: `adb` 1.0.41, Perfetto `trace_processor` wrapper (get.perfetto.dev), on-device `/system/bin/perfetto`.
Note: `get.perfetto.dev/heap_profile` helper is **404 (gone)** — drive `perfetto` with a heapprofd config directly instead.

---

## Spike 1 — `.pftrace` round-trip (heapprofd → still-live → module)  ✅ PROVEN

Target: real app **`com.katim.connect`** (pid live), attach-mode, no profileable build needed (userdebug lifts it).
Config: `android.heapprofd`, `sampling_interval_bytes: 4096`, `block_client: true`, `continuous_dump_config { dump_interval_ms: 5000 }`, `duration_ms: 30000` → **7 checkpoints**, 8889 alloc rows, 5142 callsites, 33 mappings, ~200 KB trace.

### What works
- heapprofd attaches to an already-running app on userdebug; continuous dumps give a real multi-checkpoint series.
- `trace_processor <trace> -q q.sql` query pipeline works end-to-end.
- **build-ids present** on every real `.so` mapping (32/40-char hex, e.g. `libflutter.so` = `44cb79b2194628171030e7c45090558544ac868c`) → offline symbol-store symbolization is viable.
- Meaningful still-live-by-caller-module breakdown (idle 30 s window):
  | caller module | still-live bytes | count |
  |---|---|---|
  | libflutter.so | 465,248 | 105 |
  | vulkan.adreno.so (Adreno GPU driver) | 200,704 | 45 |
  | libc.so | 32,768 | 8 |
  | libc++.so | 4,096 | 1 |

### Semantic findings the concrete parser MUST encode (a naive impl gets these wrong)
1. **`heap_profile_allocation.size`/`.count` rows are SIGNED PER-DUMP DELTAS, not cumulative snapshots.** Proven empirically: one dump's `SUM(size)` was **−21,618** (cumulative still-live can never be negative). ⇒ still-live at time T = `SUM(size) WHERE ts <= T`; a checkpoint diff = sum of deltas between two ts.
2. **Attribute one frame UP from the allocator.** Every allocation's LEAF frame is `malloc`/`calloc` in `libc.so`, so grouping by leaf module always says "libc." Walk to the parent callsite frame (or first non-allocator mapping) for real attribution.
3. **Function-name symbolization needs the unstripped `.so`.** Frame `name`s are empty in-trace; only MODULE resolves from the mapping path. Module-level attribution (the review's stated target) works with zero extra inputs; function names require matching build-id → unstripped binary in a symbol store.
4. Top callsite walked leaf→root: `calloc` → `libflutter.so` ×5 → `/[anon:dart-code]` → the owner is the Flutter engine / Dart code, as expected.

### Caveats / open
- Attach-mode misses the **pre-existing heap** (only allocations after attach are counted) — 702 KB total still-live over idle 30 s is "new" allocations only. For a real leak hunt use **startup mode** or a longer window while exercising the app.
- Idle capture shows engine/driver churn, not a leak. Spike 1b (leak-lab, known native leak) validates the growth/diff path with a known answer.

### Reusable query (still-live per caller module)
```sql
select case when instr(spm.name,'!')>0 then substr(spm.name, instr(spm.name,'!')+1) else spm.name end as caller_module,
       sum(hpa.size) as still_live_bytes, sum(hpa.count) as still_live_count
from heap_profile_allocation hpa
join stack_profile_callsite leaf   on hpa.callsite_id = leaf.id
join stack_profile_callsite parent on leaf.parent_id  = parent.id
join stack_profile_frame pf        on parent.frame_id = pf.id
join stack_profile_mapping spm     on pf.mapping = spm.id
group by caller_module having still_live_bytes <> 0 order by still_live_bytes desc;
```

---

Also (from the parallel runbook research): for a **retail `user` build** (not userdebug), the app must carry `<profileable android:shell="true"/>` in `android/app/src/profile/AndroidManifest.xml` (Flutter does NOT auto-inject it for `--profile`). On-demand checkpoints without continuous-dump: `adb shell killall -USR1 heapprofd` inside one live session. heapprofd is **not retroactive** — one continuous session, not two captures.

---

## Spike 1b — leak-lab known-answer (heapprofd isolates a known native leak)  ✅ PROVEN
App: `com.katim.leak_lab` (profile APK), deliberate **10 MB ffi leak at startup** (10×1 MB `malloc` never freed) + 5 MB alloc'd-and-freed. Captured in **startup mode** (force-stop → start trace → launch) so heapprofd sees the leak from process birth.

- Total still-live 21.3 MB (10 MB leak + ~11 MB normal startup: GPU driver + engine).
- **Top caller-module = `com.katim.leak_lab/base.apk` = EXACTLY 10,485,760 B / 10 blocks** — the known leak, attributed to the app's own module, cleanly separated from `vulkan.adreno.so` (4.2 MB), `libGLESv2_adreno.so` (2.3 MB), `libflutter.so` (2.3 MB) startup churn.
- Exactly **one** callsite ≥1 MB (id 32408 = 10 MB / 10); full 40-frame native stack present (Dart AOT frames live in `base.apk`, unsymbolized names but correct module).
- ⇒ heapprofd distinguishes **app-code native leaks (base.apk) from engine (libflutter.so) from GPU driver (adreno)** by module — the core "who is leaking" signal.

## Spike 2 — FlutterMemoryAllocations hook in profile mode  ⚠️ RESULT: HOOK IS DEBUG-ONLY
Ran the real profile APK: `build mode: debug=false profile=true release=false`, and **`kFlutterMemoryAllocationsEnabled = false`**.
- The entire `FlutterMemoryAllocations` / `leak_tracker` dispatch is **disabled in profile & release** — it is debug-only. **Zero** events fire for ValueNotifier, ChangeNotifier, ui.Image, or ImageStream in profile mode.
- This is STRONGER than the review's B3: not just the `Texture` native hook is infeasible — the whole framework dispatch mechanism is off in the exact builds native/GPU analysis targets.
- **Consequence for Lane C:** it cannot lean on the framework hook. Options: (a) leak_radar-owned explicit wrappers around image/texture create/dispose (works any mode, but requires the app to route through them), or (b) fold image/texture leaks into **Lane B heapprofd** as native bytes — already demonstrated (GPU-driver modules `vulkan.adreno.so`/`libGLESv2_adreno.so` show up as still-live native memory). Recommend (b) as the honest v1; (a) as opt-in.

## Spike 3 — ffi Allocator wrapper (still-live-with-stack, no JOIN)  ✅ PROVEN
`LoggingAllocator implements Allocator` records `{address, size, StackTrace.current, ts}` on allocate, clears on free.
- Result: `still-live: 10 blocks / 10485760 bytes (allocs=15 frees=5)` — exact known answer.
- **Every still-live block carries its exact Dart stack** (`_LeakLabHomeState._spike3 (package:leak_lab/main.dart:136)`).
- Confirms the review's reframe: the wrapper alone is **fix-grade** (real Dart stack, no heapprofd pointer-JOIN — which is impossible anyway). Works in **profile mode** (unlike Lane C's framework hook). Cost: opt-in — the app must allocate through the wrapper.
- Minor: `Pointer.address` prints as signed hex (high-bit set) — cosmetic only; use unsigned formatting in any UI.

---

## Bottom line for radar_native v1
- **Lane B (heapprofd) is the proven anchor** — capture + still-live diff + module attribution all validated on real + known-answer data. The 3 parser semantics (signed deltas, walk-past-allocator, module-from-mapping) are now known and must be encoded.
- **Lane D (ffi wrapper) works standalone** and is fix-grade — ship it as an opt-in in-app allocator; drop the pointer-JOIN.
- **Lane C (framework image/texture hook) is NOT viable in profile/release** — fold image/GPU leaks into Lane B as native bytes; offer explicit wrappers only as opt-in.
- Symbolization: **module-level works with zero extra inputs**; **function-level needs the unstripped `.so` + build-id** (build-ids confirmed present) → a symbol-store follow-up, not a v1 blocker.
- Product framing (Ivan, 2026-07-03): all of this lives as an **"Android profiling" section inside the single unified Radar desktop app**, not a separate tool.
