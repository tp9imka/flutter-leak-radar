# Native Symbolization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Turn module-only Android native frames (`libflutter.so`, function unknown) into real function names, by (1) carrying each stripped frame's relative PC through as a canonical `0x<hex>` address, and (2) a **host-side producer** that build-id-matches unstripped `.so` files and runs `llvm-symbolizer` to emit the `SymbolStore` JSON the app already imports.

**Architecture:** The `SymbolStore` / `applySymbolStore` / "Attach symbol store (.json)" flow already exists and is keyed by `(buildId, function-string)`. `NativeFrame.function` is already documented as "a `0x…` address when unsymbolized", and `isFrameSymbolized(f) => f.isNotEmpty && !f.startsWith('0x')` already treats `0x…` as unsymbolized. Today the mapper emits `''` for stripped frames only because the SQL never selects `rel_pc`. So: select `rel_pc`, make the mapper emit `0x<hex(rel_pc)>`, and build a producer that keys a `SymbolStore` by those same `0x<hex>` strings. **`radar_native`'s `SymbolStore`/`applySymbolStore` do not change.**

**Tech Stack:** `radar_native_host` (Perfetto SQL, `PerfettoRow`, mapper, new `BuildIdReader`/`Symbolizer`/`SymbolStoreBuilder` + a `bin/symbolize.dart` CLI), `radar_native` (`SymbolStore` reused unchanged), `radar_desktop` (optional in-app "Resolve from .so directory" action).

## Global Constraints
- **`radar_native` `SymbolStore` + `applySymbolStore` are REUSED UNCHANGED.** The producer emits a store keyed by `(buildId → {"0x<hex>": name})`; the frame's unsymbolized `function` IS that `0x<hex>` key, so the existing `applySymbolStore` upgrades frames with no change. Do not add address fields to `NativeFrame`.
- **External tools are seamed + honestly degraded, exactly like `trace_processor`/`adb`.** `llvm-symbolizer` and `llvm-readelf`/`readelf` are injected behind interfaces; the concrete impls resolve a binary via an explicit path → env var → bare PATH name, and surface a clear error when the tool is absent or a `.so` doesn't match. A build-id with no matching `.so` is left unsymbolized (honest), never guessed.
- **Device/tool re-validation is gated.** Unit tests use fakes. A gated integration test (skips unless `RADAR_LLVM_SYMBOLIZER` + a fixture `.so` are set) exercises the real tool. The SQL `rel_pc` addition is low-risk (one standard column) but its on-trace re-validation runs through the existing gated `real_import` path (needs `RADAR_TP_BIN` + `.spikes/captures/leaklab.pftrace`).
- CI runs Flutter **3.44.4** for the `radar_desktop` task — no `containsSemantics` in tests; verify the CI JSON conclusion after merge. `radar_native_host`/`radar_native` are pure Dart (`dart test`). See [[project_flutter_leak_radar_ci_skew]].
- `git checkout -- packages/radar_desktop/macos` before committing if build artifacts appear.

---

### Task 1: carry `rel_pc` through as a `0x<hex>` address

**Files:**
- Modify `packages/radar_native_host/lib/src/perfetto/perfetto_sql.dart`
- Modify `packages/radar_native_host/lib/src/perfetto/perfetto_row.dart`
- Modify `packages/radar_native_host/lib/src/perfetto/trace_processor_runner.dart` (`_cellCount`)
- Modify `packages/radar_native_host/lib/src/perfetto/perfetto_profile_mapper.dart`
- Modify tests: `packages/radar_native_host/test/**` that build 9-cell rows / assert frames.

**Interfaces — Produces:** `PerfettoRow` gains `final int? relPc;`; the mapper emits `NativeFrame.function == '0x' + relPc.toRadixString(16)` for name-less frames.

**SQL** — append `rel_pc` as the 10th field (leave the rest byte-for-byte; append only). The `select` becomes:
```sql
select
  ch.root_callsite || char(31) || ch.depth || char(31) ||
  coalesce(spf.name,'') || char(31) || coalesce(spm.name,'') || char(31) ||
  coalesce(spm.build_id,'') || char(31) ||
  a.alloc_bytes || char(31) || a.alloc_count || char(31) ||
  a.free_bytes  || char(31) || a.free_count || char(31) ||
  coalesce(spf.rel_pc,'') as row
```
Update the file's header comment: `9 fields` → `10 fields`, and add `rel_pc` to the field list.

**`trace_processor_runner.dart`:** `const int _cellCount = 9;` → `10`. Update the `parseTraceProcessorOutput` doc comment `9 [PerfettoRow] cells` → `10`.

**`PerfettoRow`:** add `final int? relPc;` (doc: "Relative PC of this frame within its module (Perfetto `stack_profile_frame.rel_pc`), used to build the `0x<hex>` unsymbolized address / feed the symbolizer; null when absent."). Update the constructor and `fromCells` (10 cells now, `relPc` is `cells[9]`):
```dart
  factory PerfettoRow.fromCells(List<String> cells) => PerfettoRow(
    callsiteId: int.parse(cells[0]),
    depth: int.parse(cells[1]),
    function: cells[2],
    module: cells[3],
    buildId: cells[4].isEmpty ? null : cells[4],
    allocBytes: int.parse(cells[5]),
    allocCount: int.parse(cells[6]),
    freeBytes: int.parse(cells[7]),
    freeCount: int.parse(cells[8]),
    relPc: cells[9].isEmpty ? null : int.parse(cells[9]),
  );
```
Update the `fromCells` doc from "9 cells" to "10 cells" and add `relPc` to the column-order list.

**Mapper** (`_toCallsite`): keep name when present, else synthesize the `0x<hex>` address from `relPc`:
```dart
          NativeFrame(
            function: row.function.isNotEmpty
                ? row.function
                : (row.relPc != null ? '0x${row.relPc!.toRadixString(16)}' : ''),
            module: row.module,
            buildId: row.buildId,
          ),
```

- [ ] **Step 1: failing tests.** In the parser test, feed a 10-cell quoted line (with a `rel_pc`) → assert the row's `relPc` parses and (via the mapper) a name-less frame's `function` is `0x<hex>` while a named frame keeps its name. Add a mapper unit test: a `PerfettoRow(function:'', relPc: 0x1a2b, …)` → `NativeFrame.function == '0x1a2b'`; `PerfettoRow(function:'malloc', relPc: 5, …)` → `function == 'malloc'`; `relPc: null, function:''` → `function == ''`. Update every existing test that constructs a `PerfettoRow` or a raw trace_processor line to include the 10th cell (an empty `rel_pc` cell is valid → `relPc == null`, `function` stays `''`).
- [ ] **Step 2-4:** run→fail, implement, run→pass. `dart analyze` (from `packages/radar_native_host`) clean.
- [ ] **Step 5: commit** `feat(radar_native_host): carry rel_pc as 0x<hex> address for unsymbolized frames`.

---

### Task 2: `BuildIdReader` seam (`.so` → build-id)

**Files:** Create `packages/radar_native_host/lib/src/symbolize/build_id_reader.dart`; export from the package barrel `lib/radar_native_host.dart`; test `test/symbolize/build_id_reader_test.dart`.

**Interfaces — Produces:**
```dart
/// Reads the GNU build-id of an unstripped ELF `.so`, to match it against a
/// frame's `buildId` before symbolizing. Null when the file has no build-id.
abstract interface class BuildIdReader {
  Future<String?> readBuildId(String soPath);
}

/// [BuildIdReader] backed by `llvm-readelf`/`readelf -n`. Resolve the binary
/// via [binaryPath] → `RADAR_READELF` env → the bare name on PATH.
final class LlvmReadelfBuildIdReader implements BuildIdReader {
  const LlvmReadelfBuildIdReader({this.binaryPath = 'llvm-readelf'});
  final String binaryPath;
  @override Future<String?> readBuildId(String soPath); // Process.run([binaryPath,'-n',soPath]); parse "Build ID: <hex>"
}

/// Resolve the readelf binary: explicit > RADAR_READELF > 'llvm-readelf'.
String resolveReadelfBinary({String? explicit, Map<String,String>? env});
```
- `readBuildId`: `Process.run(binaryPath, ['-n', soPath])`; on non-zero exit, throw a `SymbolizeToolException` carrying stderr (do NOT return null on tool failure — null means "no build-id in a readable file"). Parse the notes output for a line matching `Build ID: <hex>` (case-insensitive `Build ID:`), return the hex (lowercased, no spaces); return null if absent.

- [ ] **Step 1: failing tests** with a fake runner OR by parsing canned `readelf -n` text (pure-function parse): given sample output containing `Build ID: 1b2c3d4e...` → returns `1b2c3d4e...`; output without a build-id → null. Extract the parsing into a testable pure function `parseBuildId(String readelfStdout)` and test it directly (no process needed). Test `resolveReadelfBinary` precedence (explicit > env > default).
- [ ] **Step 2-4:** run→fail, implement, run→pass; `dart analyze` clean.
- [ ] **Step 5: commit** `feat(radar_native_host): BuildIdReader (llvm-readelf build-id of a .so)`.

---

### Task 3: `Symbolizer` seam (`.so` + address → function name)

**Files:** Create `packages/radar_native_host/lib/src/symbolize/symbolizer.dart`; export from the barrel; test `test/symbolize/symbolizer_test.dart`.

**Interfaces — Produces:**
```dart
/// Resolves one relative-PC address inside an unstripped `.so` to a function
/// name. Null when the address does not resolve (llvm-symbolizer prints `??`).
abstract interface class Symbolizer {
  Future<String?> symbolize({required String soPath, required int address});
}

/// [Symbolizer] backed by `llvm-symbolizer --obj=<so> <address>`. Resolve the
/// binary via [binaryPath] → `RADAR_LLVM_SYMBOLIZER` env → bare name on PATH.
final class LlvmSymbolizer implements Symbolizer {
  const LlvmSymbolizer({this.binaryPath = 'llvm-symbolizer'});
  final String binaryPath;
  @override Future<String?> symbolize({required String soPath, required int address});
}

String resolveSymbolizerBinary({String? explicit, Map<String,String>? env});
/// Pure parse of llvm-symbolizer stdout → the function name (first line),
/// or null when it is `??`/empty.
String? parseSymbolizerOutput(String stdout);
```
- `symbolize`: `Process.run(binaryPath, ['--obj=$soPath', '0x${address.toRadixString(16)}'])`; non-zero exit → throw `SymbolizeToolException(stderr)`; else `parseSymbolizerOutput(result.stdout)`. `parseSymbolizerOutput`: first non-empty line; if it is `??` or empty → null; else return it trimmed.
- Define `SymbolizeToolException` once (in `build_id_reader.dart` or a shared `symbolize/symbolize_exception.dart`) and reuse; don't duplicate.

- [ ] **Step 1: failing tests** on `parseSymbolizerOutput`: `"flutter::Shell::Run\n/path:12:3\n"` → `flutter::Shell::Run`; `"??\n??:0:0\n"` → null; `""` → null. Test `resolveSymbolizerBinary` precedence.
- [ ] **Step 2-4:** run→fail, implement, run→pass; `dart analyze` clean.
- [ ] **Step 5: commit** `feat(radar_native_host): Symbolizer (llvm-symbolizer address→function)`.

---

### Task 4: `SymbolStoreBuilder` — profile + `.so` files → `SymbolStore`

**Files:** Create `packages/radar_native_host/lib/src/symbolize/symbol_store_builder.dart`; export from the barrel; test `test/symbolize/symbol_store_builder_test.dart`.

**Interfaces — Consumes:** `BuildIdReader`, `Symbolizer` (Tasks 2-3), `radar_native`'s `SymbolStore`, `NativeHeapProfile`, `applySymbolStore`.
**Produces:**
```dart
/// Builds a [SymbolStore] for [profile] by build-id-matching the unstripped
/// [soPaths] and symbolizing every module-only (`0x…`) frame address.
/// build-ids with no matching `.so` are left out (those frames stay
/// module-only — honest). Deterministic; no I/O beyond the injected seams.
final class SymbolStoreBuilder {
  const SymbolStoreBuilder({required BuildIdReader buildIdReader, required Symbolizer symbolizer});
  Future<SymbolStore> build(NativeHeapProfile profile, {required List<String> soPaths});
  Future<SymbolStoreBuildReport> buildWithReport(NativeHeapProfile profile, {required List<String> soPaths});
}
/// Summary for the CLI/UI: how many build-ids matched a `.so`, how many
/// addresses resolved, how many stayed unsymbolized.
final class SymbolStoreBuildReport {
  const SymbolStoreBuildReport({required this.store, required this.matchedBuildIds, required this.unmatchedBuildIds, required this.resolvedAddresses, required this.unresolvedAddresses});
  final SymbolStore store; final int matchedBuildIds; final int unmatchedBuildIds;
  final int resolvedAddresses; final int unresolvedAddresses;
}
```
- Algorithm: 1) Read each `.so`'s build-id via `buildIdReader` → `{buildId: soPath}` (first wins; skip files whose build-id is null or errors — surface a tool error only for a genuine process failure, not a missing build-id). 2) Walk `profile.callsites`' frames; collect the set of `(buildId, functionHex)` where `frame.buildId != null` and `frame.function.startsWith('0x')`. 3) For each such `(buildId, hex)` whose `buildId` is in the `.so` map: `address = int.parse(hex.substring(2), radix: 16)`; `name = await symbolizer.symbolize(soPath, address)`; if non-null, add `store[buildId][hex] = name`. 4) Return the `SymbolStore` (+ counts in `buildWithReport`).
- The store's keys are exactly the frames' `0x<hex>` function strings, so `applySymbolStore(profile, store)` upgrades them.

- [ ] **Step 1: failing tests** with fakes: `_FakeBuildIdReader` (map soPath→buildId), `_FakeSymbolizer` (map (soPath,address)→name). Given a profile with two `0x…` frames under buildId `A` (matched to `libA.so`) and one under buildId `B` (no `.so`): the store has `A`'s two addresses resolved, `B` absent; `applySymbolStore(profile, store).callsites`'s frames under `A` are now named (`isFrameSymbolized`-equivalent: `!function.startsWith('0x')`), `B`'s frame still `0x…`; the report counts `matchedBuildIds==1, unmatchedBuildIds==1, resolvedAddresses==2`. A symbolizer that returns null for an address → that address absent from the store (stays module-only). Named frames (not `0x…`) are ignored.
- [ ] **Step 2-4:** run→fail, implement, run→pass; `dart analyze` clean.
- [ ] **Step 5:** add a **gated** real integration test `test/symbolize/real_symbolize_test.dart`: skips (prints + returns) unless `RADAR_LLVM_SYMBOLIZER`, `RADAR_READELF` (optional, default `llvm-readelf`), and `RADAR_SYMBOL_SO` (a real unstripped `.so`) are set; when set, read its build-id, pick a known address (env `RADAR_SYMBOL_ADDR`), and assert `LlvmSymbolizer` returns a non-empty, non-`0x` name — proving the real tool wiring. Keep it green-by-skip in CI.
- [ ] **Step 6: commit** `feat(radar_native_host): SymbolStoreBuilder (.so + profile → SymbolStore) + gated real test`.

---

### Task 5: `symbolize` CLI

**Files:** Create `packages/radar_native_host/bin/symbolize.dart`; test `test/symbolize/symbolize_cli_test.dart` (test the arg-parsing/orchestration via an injectable entrypoint, not a real process).

**Interfaces — Produces:** a `dart run radar_native_host:symbolize` command:
```
symbolize --trace <capture.pftrace> --so <libA.so> [--so <libB.so> ...] [--so-dir <dir>] \
          --out symbols.json [--tp-bin <trace_processor>] [--symbolizer <llvm-symbolizer>] [--readelf <llvm-readelf>]
```
- Resolve `trace_processor` (explicit `--tp-bin` → `RADAR_TP_BIN` → error) and parse the `.pftrace` via `PerfettoTraceProcessorParser` into a `NativeHeapProfile`. Gather `.so` paths from `--so` + every `*.so` under each `--so-dir`. Run `SymbolStoreBuilder.buildWithReport`. Write `SymbolStore.toJson` (pretty JSON) to `--out`. Print the report (`matched X/Y build-ids, resolved N/M addresses → symbols.json`). Honest, specific errors for: no trace, no `.so`, missing `trace_processor`, missing `llvm-symbolizer`.
- Factor the body into `Future<int> runSymbolize(List<String> args, {TraceProcessorRunner? runner, BuildIdReader? reader, Symbolizer? symbolizer, ...})` so the test can inject fakes and assert the written JSON + exit code, with `main(args) => exit(await runSymbolize(args))`.

- [ ] **Step 1: failing tests** on `runSymbolize` with injected fakes + temp files: a fake runner yielding rows with a `0x…` frame + a fake reader/symbolizer → the `--out` file contains the expected `{buildId:{"0x..":name}}` JSON and exit code 0; missing `--trace` → non-zero + a clear message; no `.so` → non-zero + message.
- [ ] **Step 2-4:** run→fail, implement, run→pass; `dart analyze` clean.
- [ ] **Step 5: commit** `feat(radar_native_host): symbolize CLI (.pftrace + .so → symbols.json)`.

---

### Task 6: desktop "Resolve symbols from .so directory" action

**Files:** Modify `packages/radar_desktop/lib/src/android/native_profiling_controller.dart` (add a symbolize seam + `resolveSymbolsFromSoDir`); Modify `packages/radar_desktop/lib/src/screens/android_capture_screen.dart` (a new action next to "Attach symbol store"); Modify `packages/radar_desktop/lib/src/shell/desktop_shell.dart` (wire the real `SymbolStoreBuilder` seam); tests under `packages/radar_desktop/test/`.

> **Sequencing:** this task edits `android_capture_screen.dart`, which the finishing-touches polish branch also edits — land after that branch merges (rebase this branch on updated main first).

**Controller additions:**
```dart
// constructor gains an optional builder seam (null → in-app symbolize unavailable):
NativeProfilingController(this._importer, {..., SymbolStoreBuilder? symbolStoreBuilder});
bool get canResolveSymbols => _symbolStoreBuilder != null && selectedProfile != null;
Future<void> resolveSymbolsFromSoDir(String dirPath); // list *.so under dir → builder.buildWithReport(selectedProfile) → apply the store (same path as importSymbolStore) → surface a report/errors via state
```
- Reuse the existing symbol-store application path (`importSymbolStore` currently parses a JSON `SymbolStore` and applies it — factor a shared `_applySymbolStore(SymbolStore)` so both the JSON import and this new builder path apply identically). On zero resolved addresses, set an honest message ("no matching .so / nothing resolved") rather than a silent no-op.

**Screen:** add an `_ImportActionRow`-style action "Resolve from .so directory" (only when `controller.canResolveSymbols`) → `getDirectoryPath()` → `controller.resolveSymbolsFromSoDir(dir)` → report success (N names resolved) or error (SnackBar). Place it beside "Attach symbol store".

**Shell:** construct the controller with `symbolStoreBuilder: SymbolStoreBuilder(buildIdReader: const LlvmReadelfBuildIdReader(), symbolizer: const LlvmSymbolizer())`.

- [ ] **Step 1: failing tests.** Controller test with a fake `SymbolStoreBuilder` (returns a store that resolves a seeded profile's `0x…` frame) → `resolveSymbolsFromSoDir` makes `selectedSymbolized` true / frames named; a builder returning an empty store → an honest "nothing resolved" state, no crash; `canResolveSymbols` false when no builder/profile. Screen widget test: the action shows when `canResolveSymbols`, hidden otherwise (avoid `containsSemantics`).
- [ ] **Step 2-4:** run→fail, implement, `flutter analyze` clean, `flutter test` green, `flutter build macos --debug` succeeds, `git checkout -- packages/radar_desktop/macos`.
- [ ] **Step 5: commit** `feat(radar_desktop): resolve native symbols from a .so directory in-app`.

---

## Self-review notes
- Coverage: rel_pc plumbing (T1), build-id read (T2), symbolize (T3), store builder (T4), CLI (T5), in-app action (T6). ✓
- Reuse: `SymbolStore`/`applySymbolStore`/"attach .json" unchanged; the `0x<hex>` key is the existing unsymbolized-frame contract. External tools seamed + honestly degraded like `trace_processor`/`adb`. ✓
- Honesty: unmatched build-ids / unresolved addresses stay module-only and are counted/surfaced; tool-absent → clear error; real validation gated. ✓
- Out of scope: `file:line` / inline-frame expansion (function name only), automatic `.so` discovery from the build tree, Approach-B (`traceconv symbolize` the whole trace) — noted as a fallback if `llvm-symbolizer` proves unavailable.
