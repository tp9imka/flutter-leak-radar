# radar_native analysis helpers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the three pure `radar_native` analysis helpers the Android Profiling UI needs — a GONE-aware diff with a status classifier, caller-module attribution, and a module-kind classifier — so the Compare view, the still-live table grouping, and the module color-tags have real data behind them.

**Architecture:** Pure additions to `packages/radar_native` (no I/O, no Flutter). Each helper is a small, independently-testable function/enum. Grounded in the device-proven module reality (`docs/spikes/2026-07-03-native-gpu-spike-results.md`) and the design↔engineering reconciliation (`docs/design-briefs/2026-07-03-android-profiling-reconciliation.md`).

**Tech Stack:** Dart, `package:radar_native` models (`NativeCallsite`, `NativeAllocationDiff`, `NativeHeapProfile`, `NativeFrame`).

## Global Constraints
- **Pure `radar_native`** — no `dart:io`, no Flutter; analysis strictness mirrors `leak_graph` (`dart analyze --fatal-infos` clean, `dart format` clean).
- **Backward compatibility** — `diffNativeProfiles(before, after)` must keep its current behavior by default (its merged tests still pass); GONE rows are opt-in via a new named param.
- **Honest degradation** — the module-kind classifier returns an explicit `unknown` rather than guessing a wrong kind (per [[feedback_honest_degradation]]).
- **Real module shapes** the helpers must handle (verbatim from the device):
  - `/apex/com.android.runtime/lib64/bionic/libc.so` (allocator leaf)
  - `/data/app/~~HASH==/com.katim.leak_lab-HASH==/base.apk` (app dex/AOT; the `~~HASH==` segments vary per install)
  - `/data/app/~~HASH==/com.katim.connect-HASH==/base.apk!libflutter.so` (engine; note the `apk!lib.so` form)
  - `/vendor/lib64/hw/vulkan.adreno.so`, `/vendor/lib64/egl/libGLESv2_adreno.so` (GPU driver)
  - `/system/lib64/libc++.so`, `/apex/.../libc++.so`, `/[anon:dart-code]`
- Existing model API (construct, do not modify): `NativeAllocationDiff({signature, frames, beforeStillLiveBytes, afterStillLiveBytes, beforeStillLiveCount, afterStillLiveCount})` with getters `growthBytes`, `growthCount`; `NativeCallsite.frames` is `List<NativeFrame>` leaf-first; `NativeFrame({function, module, buildId})`.

---

### Task 1: GONE-aware diff + deterministic tie-break + status classifier

**Files:**
- Modify: `packages/radar_native/lib/src/analysis/native_diff.dart`
- Create: `packages/radar_native/lib/src/analysis/native_diff_status.dart`
- Modify: barrel `lib/radar_native.dart` (export the new file)
- Modify/create tests: `packages/radar_native/test/native_diff_test.dart` (existing) + `test/native_diff_status_test.dart`

**Interfaces:**
- Produces:
  ```dart
  // native_diff.dart — extended signature (backward compatible):
  List<NativeAllocationDiff> diffNativeProfiles(
    NativeHeapProfile before, NativeHeapProfile after, {bool includeRemoved = false});
  // native_diff_status.dart:
  enum NativeDiffStatus { added, grew, shrank, gone, flat }
  extension NativeAllocationDiffStatus on NativeAllocationDiff {
    NativeDiffStatus get status;
  }
  ```

**Behavior:**
- `includeRemoved: false` (default) → identical to today (iterate `after.callsites`, zero-baseline for new, before-only dropped).
- `includeRemoved: true` → ALSO append, for every `before` callsite whose signature is absent from `after`, a diff with `afterStillLiveBytes: 0`, `afterStillLiveCount: 0`, `frames: b.frames` (from `before`), before-values from `b`.
- Sort: `growthBytes` **descending**, tie-broken by `signature` **ascending** (deterministic — removes the nondeterministic ordering of equal-growth rows).
- `status` getter: `beforeStillLiveBytes == 0 && afterStillLiveBytes > 0` → `added`; else `afterStillLiveBytes == 0 && beforeStillLiveBytes > 0` → `gone`; else `growthBytes > 0` → `grew`; else `growthBytes < 0` → `shrank`; else `flat`.

- [ ] **Step 1: Write failing tests.** In `native_diff_status_test.dart`:
```dart
import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

NativeAllocationDiff d(int before, int after) => NativeAllocationDiff(
  signature: 's', frames: const [],
  beforeStillLiveBytes: before, afterStillLiveBytes: after,
  beforeStillLiveCount: before == 0 ? 0 : 1, afterStillLiveCount: after == 0 ? 0 : 1);

void main() {
  test('status classifies added/gone/grew/shrank/flat', () {
    expect(d(0, 100).status, NativeDiffStatus.added);
    expect(d(100, 0).status, NativeDiffStatus.gone);
    expect(d(100, 300).status, NativeDiffStatus.grew);
    expect(d(300, 100).status, NativeDiffStatus.shrank);
    expect(d(200, 200).status, NativeDiffStatus.flat);
  });
}
```
   In `native_diff_test.dart` add:
```dart
test('includeRemoved surfaces before-only sites as gone rows', () {
  // before has sites A(1000) + B(500); after has A(1000) only.
  final before = NativeHeapProfile(capturedAt: DateTime.utc(2026,7,3), label:'b',
    meta: const NativeProfileMeta(), callsites: [
      NativeCallsite(frames: const [NativeFrame(function:'fa', module:'libA.so')],
        allocBytes:1000, allocCount:1, freeBytes:0, freeCount:0),
      NativeCallsite(frames: const [NativeFrame(function:'fb', module:'libB.so')],
        allocBytes:500, allocCount:1, freeBytes:0, freeCount:0),
    ]);
  final after = NativeHeapProfile(capturedAt: DateTime.utc(2026,7,3,1), label:'a',
    meta: const NativeProfileMeta(), callsites: [
      NativeCallsite(frames: const [NativeFrame(function:'fa', module:'libA.so')],
        allocBytes:1000, allocCount:1, freeBytes:0, freeCount:0),
    ]);
  final without = diffNativeProfiles(before, after);
  expect(without.map((e)=>e.signature), isNot(contains(after.callsites.first.signature == '' ? '' : anything)));
  expect(without, hasLength(1)); // default: before-only dropped
  final with_ = diffNativeProfiles(before, after, includeRemoved: true);
  expect(with_, hasLength(2));
  final gone = with_.firstWhere((e)=>e.afterStillLiveBytes==0);
  expect(gone.beforeStillLiveBytes, 500);
  expect(gone.frames.single.module, 'libB.so'); // frames from `before`
  expect(gone.status, NativeDiffStatus.gone);
});

test('equal-growth rows are ordered deterministically by signature', () {
  // two new sites with identical growth must sort by signature ascending
  NativeCallsite cs(String fn) => NativeCallsite(
    frames: [NativeFrame(function: fn, module: 'm.so')],
    allocBytes: 100, allocCount: 1, freeBytes: 0, freeCount: 0);
  final before = NativeHeapProfile(capturedAt: DateTime.utc(2026,7,3), label:'b',
    meta: const NativeProfileMeta(), callsites: const []);
  final after = NativeHeapProfile(capturedAt: DateTime.utc(2026,7,3,1), label:'a',
    meta: const NativeProfileMeta(), callsites: [cs('zzz'), cs('aaa')]);
  final out = diffNativeProfiles(before, after);
  expect(out.map((e)=>e.frames.single.function).toList(), ['aaa','zzz']);
});
```
- [ ] **Step 2: Run — expect fail** (`status`/`includeRemoved` undefined).
- [ ] **Step 3: Implement.** Add `includeRemoved` param + the before-only append loop; change the sort to `(x,y){final g=y.growthBytes.compareTo(x.growthBytes); return g!=0?g:x.signature.compareTo(y.signature);}`. Add `native_diff_status.dart` with the enum + extension. Export the new file from the barrel.
- [ ] **Step 4: Run tests — expect pass** (incl. the pre-existing diff tests). analyze + format clean.
- [ ] **Step 5: Commit** `feat(radar_native): GONE-aware diff + deterministic tie-break + NativeDiffStatus`.

---

### Task 2: `moduleShortName` + `attributedModule`

**Files:**
- Create: `packages/radar_native/lib/src/analysis/native_module.dart`
- Modify: barrel (export it)
- Create: `packages/radar_native/test/native_module_test.dart`

**Interfaces:**
- Produces:
  ```dart
  /// The display basename of a mapping path: the segment after the last '/'
  /// AND after the last '!' (so `/data/app/../base.apk!libflutter.so` -> `libflutter.so`).
  String moduleShortName(String module);
  /// The module a callsite should be ATTRIBUTED to: walk frames leaf-first,
  /// skip allocator frames (the malloc/calloc/... leaf in libc), and return
  /// moduleShortName() of the first real caller. Empty stack -> ''.
  String attributedModule(NativeCallsite callsite);
  ```

**Behavior:**
- `moduleShortName`: take substring after last `/`; if that contains `!`, take substring after last `!`. `''` → `''`.
- Allocator frames to skip (a leading frame is an allocator if): `moduleShortName(frame.module) == 'libc.so'` OR `frame.function` (lowercased) is one of `{malloc, calloc, realloc, free, memalign, aligned_alloc, posix_memalign, operator new, operator new[], operator delete, operator delete[]}`.
- `attributedModule`: skip leading allocator frames; return `moduleShortName` of the first non-allocator frame. If all frames are allocators, return `moduleShortName` of the last frame. If `frames` is empty, return `''`.

- [ ] **Step 1: Write failing tests** (`native_module_test.dart`):
```dart
import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

NativeCallsite cs(List<List<String>> frames) => NativeCallsite(
  frames: [for (final f in frames) NativeFrame(function: f[0], module: f[1])],
  allocBytes: 0, allocCount: 0, freeBytes: 0, freeCount: 0);

void main() {
  test('moduleShortName strips path and apk! prefix', () {
    expect(moduleShortName('/apex/com.android.runtime/lib64/bionic/libc.so'), 'libc.so');
    expect(moduleShortName('/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so'), 'libflutter.so');
    expect(moduleShortName('/data/app/~~H==/com.katim.leak_lab-H==/base.apk'), 'base.apk');
    expect(moduleShortName(''), '');
  });
  test('attributedModule skips the malloc/libc allocator leaf', () {
    final c = cs([
      ['calloc', '/apex/com.android.runtime/lib64/bionic/libc.so'],
      ['', '/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so'],
      ['', '/data/app/~~H==/com.katim.leak_lab-H==/base.apk'],
    ]);
    expect(attributedModule(c), 'libflutter.so');
  });
  test('attributedModule on empty frames -> empty string', () {
    expect(attributedModule(cs(const [])), '');
  });
  test('attributedModule when all frames are allocators -> last module short', () {
    final c = cs([
      ['malloc', '/apex/.../bionic/libc.so'],
      ['free', '/system/lib64/libc.so'],
    ]);
    expect(attributedModule(c), 'libc.so');
  });
}
```
- [ ] **Step 2: Run — expect fail.**
- [ ] **Step 3: Implement** `moduleShortName` + the allocator-name set + `attributedModule`. Keep the allocator set a `const Set<String>` of lowercased names.
- [ ] **Step 4: Run tests — expect pass.** analyze + format clean.
- [ ] **Step 5: Commit** `feat(radar_native): moduleShortName + attributedModule (walk past allocator leaf)`.

---

### Task 3: `moduleKind` classifier

**Files:**
- Create: `packages/radar_native/lib/src/analysis/native_module_kind.dart`
- Modify: barrel (export it)
- Create: `packages/radar_native/test/native_module_kind_test.dart`

**Interfaces:**
- Consumes: `moduleShortName` from Task 2.
- Produces:
  ```dart
  enum NativeModuleKind { app, gpuDriver, engine, plugin, system, unknown }
  /// Best-effort classification of a mapping path into a UI color-kind.
  /// Takes the FULL module path (needs '/data/app/' + '!' to tell app vs plugin).
  NativeModuleKind moduleKind(String module);
  ```

**Behavior (ordered rules — first match wins):**
1. GPU driver — the path (lowercased) contains any of `adreno`, `mali`, `powervr`, `libgles`, `vulkan`, `/egl/`, `libegl`, `libgsl` → `gpuDriver`. (Check FIRST: GPU libs live under `/vendor` which would otherwise read as system.)
2. Engine — `moduleShortName(module) == 'libflutter.so'` → `engine`.
3. App — `moduleShortName(module)` is `base.apk`, `libapp.so`, or ends with `.oat`/`.dex`/`.odex` AND the module is NOT an `apk!lib.so` form (no `!` after the apk) → `app`. (The app's own dex/AOT code.)
4. System — path starts with `/system/`, `/apex/`, `/vendor/`, contains `/bionic/`, or `moduleShortName` matches `libc.so`/`libc++.so`/`libc++_shared.so`/`libutils.so`/`libbinder.so`/`libart.so`/`libandroid*.so`/`libui.so`/`libgui.so`/`libhwui.so` → `system`.
5. Plugin — the module is app-bundled (path contains `/data/app/` OR has an `!` apk-embedded lib form) and didn't match engine/app above → `plugin`.
6. Otherwise → `unknown` (honest fallback: e.g. `/[anon:dart-code]`, `/memfd:jit-cache`).

- [ ] **Step 1: Write failing tests** (`native_module_kind_test.dart`) — use the REAL device paths:
```dart
import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';
void main() {
  test('classifies the real device modules', () {
    expect(moduleKind('/vendor/lib64/hw/vulkan.adreno.so'), NativeModuleKind.gpuDriver);
    expect(moduleKind('/vendor/lib64/egl/libGLESv2_adreno.so'), NativeModuleKind.gpuDriver);
    expect(moduleKind('/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so'), NativeModuleKind.engine);
    expect(moduleKind('/data/app/~~H==/com.katim.leak_lab-H==/base.apk'), NativeModuleKind.app);
    expect(moduleKind('/apex/com.android.runtime/lib64/bionic/libc.so'), NativeModuleKind.system);
    expect(moduleKind('/system/lib64/libc++.so'), NativeModuleKind.system);
    expect(moduleKind('/data/app/~~H==/com.example-H==/base.apk!libwebrtc.so'), NativeModuleKind.plugin);
    expect(moduleKind('/[anon:dart-code]'), NativeModuleKind.unknown);
  });
}
```
- [ ] **Step 2: Run — expect fail.**
- [ ] **Step 3: Implement** the ordered rules. Use `moduleShortName` (Task 2) + lowercased-path `contains` checks. Document each rule inline (one short line each) and that `unknown` is the deliberate honest fallback.
- [ ] **Step 4: Run tests — expect pass.** analyze + format clean.
- [ ] **Step 5: Commit** `feat(radar_native): moduleKind classifier (app/gpuDriver/engine/plugin/system/unknown)`.

---

## Self-review notes
- Coverage: reconciliation deltas #1 (GONE diff → Task 1), #2 (attributedModule → Task 2), #3 (moduleKind → Task 3), plus the logged deterministic-tie-break fast-follow (Task 1). ✓
- Backward-compat: `includeRemoved` defaults false; the merged diff tests stay green. ✓
- Type consistency: `moduleShortName` defined in Task 2 and reused by Task 3; enums named `NativeDiffStatus` / `NativeModuleKind` consistently. ✓
- Out of scope: no UI, no capture/import, no symbol resolution, no changes to `radar_native_host`.
