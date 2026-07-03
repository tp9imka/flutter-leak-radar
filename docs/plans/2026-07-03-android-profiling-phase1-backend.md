# Android Profiling — Phase 1: pure `radar_native` backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Add the pure-Dart backend the Android Profiling UI needs beyond what's merged: per-module aggregation (the workhorse table / compare / detail all rest on it), the ffi-lane model + parser, and a symbol store. All pure `radar_native` (no dart:io/Flutter).

**Architecture:** Pure additions to `packages/radar_native`. `summarizeByModule` rolls a checkpoint's callsites up by attributed module; `diffModuleSummaries` joins two checkpoints' rollups for the Compare view (reusing the `added/gone/grew/shrank/flat` shape); the ffi model + JSON parser back the ffi lane; `SymbolStore`+`applySymbolStore` upgrade module-only frames to symbolized. Grounded in the scout's data→API map.

**Tech Stack:** Dart, `package:radar_native` models + existing helpers (`attributedModule`, `moduleShortName`, `moduleKind`, `NativeDiffStatus`).

## Global Constraints
- **Pure `radar_native`** — no dart:io/Flutter; `dart analyze --fatal-infos` + `dart format` clean; analysis mirrors `leak_graph`.
- **Do not modify existing merged behavior** — existing tests stay green. Existing helpers (`attributedModule`, `moduleShortName`, `moduleKind`, `diffNativeProfiles`, `NativeDiffStatus`) keep their contracts; `attributedModule`'s public behavior is unchanged (Task 1 only refactors it to share an internal helper).
- **Honest degradation** — reuse the `unknown` `NativeModuleKind`; a symbol store that can't resolve leaves `function` unchanged (still module-only), never a fabricated name.
- Existing types (construct, don't modify): `NativeHeapProfile({capturedAt,label,callsites,meta})`, `NativeCallsite({frames,allocBytes,allocCount,freeBytes,freeCount})` with getters `stillLiveBytes`/`stillLiveCount`, `NativeFrame({function,module,buildId})`, `NativeModuleKind{app,gpuDriver,engine,plugin,system,unknown}`.
- **The `attributedModule` full-path wrinkle** (scout): `attributedModule` returns the SHORT name but `moduleKind` needs the FULL path. Task 1 adds `attributedFrame` (returns the chosen `NativeFrame`, whose `.module` is the full path) and re-expresses `attributedModule` in terms of it, so summaries can get short name + kind from one walk.

---

### Task 1: `attributedFrame` (refactor; expose the attributed frame)

**Files:** Modify `packages/radar_native/lib/src/analysis/native_module.dart`; barrel export; extend `test/native_module_test.dart`.

**Interfaces — Produces:**
```dart
/// The frame a callsite is attributed to: the first non-allocator frame
/// (walking leaf-first, past the malloc/calloc libc leaf). Null if the
/// callsite has no frames; falls back to the LAST frame if all are allocators.
NativeFrame? attributedFrame(NativeCallsite callsite);
```
- Re-express existing `attributedModule` as `moduleShortName(attributedFrame(callsite)?.module ?? '')` — its behavior and existing tests MUST be unchanged. Move the allocator-skip loop into `attributedFrame`.

- [ ] **Step 1: failing test** — add to `native_module_test.dart`:
```dart
test('attributedFrame returns the first non-allocator frame (full module)', () {
  final c = cs([
    ['calloc', '/apex/com.android.runtime/lib64/bionic/libc.so'],
    ['flutter::Foo', '/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so'],
  ]);
  final f = attributedFrame(c)!;
  expect(f.module, '/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so'); // FULL path
  expect(f.function, 'flutter::Foo');
});
test('attributedFrame on empty frames is null', () {
  expect(attributedFrame(cs(const [])), isNull);
});
```
- [ ] **Step 2: run — fail.**
- [ ] **Step 3: implement** `attributedFrame`; refactor `attributedModule` to use it (all-allocator → last frame; empty → returns null → `attributedModule` yields `''`). Export from barrel.
- [ ] **Step 4: run — all green (incl. existing attributedModule tests).** analyze+format clean.
- [ ] **Step 5: commit** `feat(radar_native): attributedFrame (expose the attributed frame's full module)`.

---

### Task 2: `summarizeByModule` + `NativeModuleSummary`

**Files:** Create `packages/radar_native/lib/src/analysis/native_module_summary.dart`; barrel; create `test/native_module_summary_test.dart`.

**Interfaces — Produces:**
```dart
@immutable
final class NativeModuleSummary {
  const NativeModuleSummary({
    required this.module,          // short display name (moduleShortName of the attributed full path)
    required this.kind,            // NativeModuleKind (from the attributed FULL path)
    required this.stillLiveBytes,  // summed across the module's callsites
    required this.stillLiveCount,
    required this.callsites,       // the NativeCallsites attributed to this module
  });
  final String module; final NativeModuleKind kind;
  final int stillLiveBytes; final int stillLiveCount;
  final List<NativeCallsite> callsites;
}
/// Roll a checkpoint's callsites up by attributed module. Groups by the
/// attributed frame's SHORT module name; kind from its FULL path. Sorted by
/// stillLiveBytes descending, tie-broken by module name ascending.
List<NativeModuleSummary> summarizeByModule(NativeHeapProfile profile);
```
- Grouping key: `moduleShortName(attributedFrame(c)?.module ?? '')`. Kind: `moduleKind(attributedFrame(c)?.module ?? '')` (full path). Callsites with no frames → group under `''` / `NativeModuleKind.unknown`. Sum `stillLiveBytes`/`stillLiveCount` per group; keep callsites first-seen order within a group; sort groups by bytes desc then name asc.

- [ ] **Step 1: failing tests** (`native_module_summary_test.dart`):
```dart
import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';
NativeCallsite cs(List<List<String>> fr, int alloc) => NativeCallsite(
  frames: [for (final f in fr) NativeFrame(function: f[0], module: f[1])],
  allocBytes: alloc, allocCount: 1, freeBytes: 0, freeCount: 0);
NativeHeapProfile prof(List<NativeCallsite> c) => NativeHeapProfile(
  capturedAt: DateTime.utc(2026,7,3), label: 'x', meta: const NativeProfileMeta(), callsites: c);
void main() {
  const libc = '/apex/com.android.runtime/lib64/bionic/libc.so';
  const flutter = '/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so';
  const app = '/data/app/~~H==/com.katim.leak_lab-H==/base.apk';
  test('sums still-live per attributed module and tags kind', () {
    final p = prof([
      cs([['malloc', libc], ['a', flutter]], 1000),
      cs([['calloc', libc], ['b', flutter]], 500),
      cs([['malloc', libc], ['c', app]], 4000),
    ]);
    final s = summarizeByModule(p);
    expect(s.map((e)=>e.module).toList(), ['base.apk','libflutter.so']); // bytes desc: 4000, 1500
    expect(s.first.kind, NativeModuleKind.app);
    expect(s.first.stillLiveBytes, 4000);
    expect(s[1].kind, NativeModuleKind.engine);
    expect(s[1].stillLiveBytes, 1500);
    expect(s[1].callsites, hasLength(2));
  });
  test('empty profile -> empty', () => expect(summarizeByModule(prof(const [])), isEmpty));
}
```
- [ ] **Step 2-4:** run→fail, implement, run→pass, analyze+format clean.
- [ ] **Step 5: commit** `feat(radar_native): summarizeByModule + NativeModuleSummary`.

---

### Task 3: `diffModuleSummaries` + `NativeModuleDiff`

**Files:** Create `packages/radar_native/lib/src/analysis/native_module_diff.dart`; barrel; create `test/native_module_diff_test.dart`.

**Interfaces — Produces:**
```dart
@immutable
final class NativeModuleDiff {
  const NativeModuleDiff({required this.module, required this.kind,
    required this.beforeStillLiveBytes, required this.afterStillLiveBytes});
  final String module; final NativeModuleKind kind;
  final int beforeStillLiveBytes; final int afterStillLiveBytes;
  int get deltaBytes => afterStillLiveBytes - beforeStillLiveBytes;
  NativeDiffStatus get status; // same rules as NativeAllocationDiff.status (added/gone/grew/shrank/flat)
}
/// Join two checkpoints' module rollups by module name for the Compare view.
/// Modules present in only one side get 0 on the other. Sorted by |deltaBytes|
/// descending, tie-broken by module name ascending.
List<NativeModuleDiff> diffModuleSummaries(NativeHeapProfile before, NativeHeapProfile after);
```
- Internally: `summarizeByModule(before)` + `summarizeByModule(after)`, join by `module`, kind from whichever side has it (prefer `after`). `status` reuses the exact `added/gone/grew/shrank/flat` classification (factor the rule into a shared private helper or reuse `NativeDiffStatus` logic — do NOT duplicate divergently).

- [ ] **Step 1: failing test** — before has {app:4000, engine:1500}; after has {app:6000, engine:0, gpuDriver:2000(new)}. Assert: app GREW (Δ+2000), engine GONE (4000→... wait use engine before 1500 after 0 → gone), gpuDriver ADDED; sorted by |Δ|; statuses correct. (Write concrete NativeHeapProfiles like Task 2.)
- [ ] **Step 2-4:** run→fail, implement, run→pass, analyze+format clean.
- [ ] **Step 5: commit** `feat(radar_native): diffModuleSummaries + NativeModuleDiff (per-module Compare)`.

---

### Task 4: ffi-lane model + JSON parser

**Files:** Create `packages/radar_native/lib/src/model/ffi_allocation_log.dart`; Create `packages/radar_native/lib/src/parse/ffi_allocation_log_parser.dart`; barrel; create `test/ffi_allocation_log_test.dart`.

**Interfaces — Produces:**
```dart
@immutable
final class FfiAllocationSite {
  const FfiAllocationSite({required this.site, required this.file,
    required this.stillLiveBytes, required this.stillLiveBlocks, required this.dartStack});
  final String site;        // e.g. 'ImageCodec.decode'
  final String file;        // e.g. 'image_codec.dart:88'
  final int stillLiveBytes; final int stillLiveBlocks;
  final List<String> dartStack; // leaf-first 'Function  file.dart:line'
  Map<String,Object?> toJson(); factory FfiAllocationSite.fromJson(Map<String,Object?>);
}
@immutable
final class FfiAllocationLog {
  const FfiAllocationLog({required this.capturedAt, required this.sites});
  final DateTime capturedAt; final List<FfiAllocationSite> sites;
  int get totalStillLiveBytes; // sum
  Map<String,Object?> toJson(); factory FfiAllocationLog.fromJson(Map<String,Object?>);
}
abstract interface class FfiAllocationLogParser { FfiAllocationLog parse(Object source); }
/// Parses the Spike-3 LoggingAllocator dump: a JSON of raw records
/// `[{address, byteCount, stack: [..], timestamp}]` — GROUPS still-live
/// (not-yet-freed) records by their leaf Dart frame into FfiAllocationSites.
final class JsonFfiAllocationLogParser implements FfiAllocationLogParser {
  const JsonFfiAllocationLogParser();
  @override FfiAllocationLog parse(Object source); // source is a JSON String
}
```
- Group raw records by their leaf stack frame (site+file); sum bytes; count blocks; keep the leaf record's stack. `version: 1` envelope + tolerant `fromJson`, mirroring `NativeHeapProfile`.

- [ ] **Step 1: failing tests** — parse a small JSON with 3 records (2 sharing a leaf, 1 distinct) → 2 sites, correct byte sums + block counts + stacks; JSON round-trip of `FfiAllocationLog`; empty → empty.
- [ ] **Step 2-4:** run→fail, implement, run→pass, analyze+format clean.
- [ ] **Step 5: commit** `feat(radar_native): ffi allocation log model + JSON parser (Lane D import)`.

---

### Task 5: `SymbolStore` + `applySymbolStore`

**Files:** Create `packages/radar_native/lib/src/analysis/symbol_store.dart`; barrel; create `test/symbol_store_test.dart`.

**Interfaces — Produces:**
```dart
@immutable
final class SymbolStore {
  const SymbolStore(this.byBuildId);
  /// buildId -> (raw address/name -> resolved function name).
  final Map<String, Map<String, String>> byBuildId;
  String? resolve({required String? buildId, required String function});
  bool get isEmpty;
  /// JSON map importer: {"<buildId>": {"<raw>": "<resolved>"}}
  factory SymbolStore.fromJson(Map<String, Object?> json);
}
/// Returns a NEW profile with each frame's `function` replaced by the store's
/// resolution when available (matched by the frame's buildId + current function);
/// frames with no match are left UNCHANGED (still module-only). Immutable.
NativeHeapProfile applySymbolStore(NativeHeapProfile profile, SymbolStore store);
```
- `applySymbolStore` rebuilds callsites/frames immutably; only replaces `function` when `store.resolve(...)` is non-null. Note: the concrete unstripped-`.so`→symbols extraction (nm/llvm-symbolizer) is host-side and DEFERRED — this JSON-map store is enough to drive the fidelity UX and is testable now.

- [ ] **Step 1: failing tests** — a store maps buildId `abc`,`0x1000`→`Foo::bar`; `applySymbolStore` on a profile whose frame has buildId `abc`,function `0x1000` → function becomes `Foo::bar`, a frame with unknown buildId stays unchanged, original profile untouched (immutability). `SymbolStore.fromJson` round-trip.
- [ ] **Step 2-4:** run→fail, implement, run→pass, analyze+format clean.
- [ ] **Step 5: commit** `feat(radar_native): SymbolStore + applySymbolStore (module-only -> symbolized)`.

---

## Self-review notes
- Coverage: table/compare/detail rollup (T1-T3), ffi lane (T4), symbol fidelity (T5). ✓
- Purity: all pure; no dart:io. ✓
- Type consistency: `NativeModuleSummary.module` (short) reused as the diff join key in T3; `NativeDiffStatus` reused for the module-level status (shared, not duplicated). ✓
- Out of scope: adb capture (Phase 2), UI widgets (Phase 3), desktop wiring (Phase 4), unstripped-.so symbol extraction (follow-up).
