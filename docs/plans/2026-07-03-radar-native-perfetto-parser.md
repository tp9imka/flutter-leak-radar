# radar_native_host — Perfetto still-live parser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the concrete, device-validated parser that turns a heapprofd `.pftrace` into a `radar_native` `NativeHeapProfile` checkpoint — the real implementation behind the `NativeProfileParser` seam.

**Architecture:** A new host-side package `packages/radar_native_host` (depends on `radar_native` + `dart:io`; `radar_native` stays pure). Async I/O (running a `trace_processor` binary over the trace) lives in a `TraceProcessorRunner`. A **pure** `PerfettoProfileMapper implements NativeProfileParser` turns query rows → `NativeHeapProfile` and is fully unit-testable with fixture rows — no device, no binary. A thin async `PerfettoTraceProcessorParser` facade wires runner → mapper.

**Tech Stack:** Dart (host, `dart:io` allowed), `package:radar_native` (models + seam), Perfetto `trace_processor` (external binary, invoked via `Process`).

## Global Constraints

- **`radar_native` stays pure** — this package may use `dart:io`; `radar_native/lib/**` must not gain any dependency from this work.
- **Analysis strictness mirrors `leak_graph`** — copy `packages/leak_graph/analysis_options.yaml`; `dart analyze --fatal-infos` must be clean (strict-casts / strict-inference / strict-raw-types).
- **The pure mapper does no I/O.** All `Process`/file work is confined to `TraceProcessorRunner`. The mapper is sync and takes already-fetched rows, matching the seam's `parse(Object source)` contract ("`source` is an opaque handle, e.g. query rows").
- **Device-proven semantics are law** (from `docs/spikes/2026-07-03-native-gpu-spike-results.md`):
  1. `heap_profile_allocation.size`/`.count` rows are **signed per-dump deltas** — split per callsite into alloc (`size>0`) and free (`size<0`) totals; `stillLive = alloc − free`.
  2. Frames are recorded **leaf-first** (index 0 = the allocating frame, always `malloc`/`calloc` in `libc.so`); callers follow. Consumers walk past the allocator — the parser records the faithful full stack, it does not pre-collapse it.
  3. Module comes from `stack_profile_mapping.name`; **build-ids are present** on real `.so` mappings (carry them through for a future symbol store). Function names may be **empty** (unsymbolized) — store them as-is.
- **`NativeProfileParser.parse` is synchronous** — the mapper implements it directly; the async entry point is the separate facade, not the interface.
- Version envelope, `==`, and `toJson` already live on the `radar_native` models — this package only constructs them; it does not re-serialize.

### Exact `radar_native` types this package constructs (do not redefine)
```dart
NativeFrame({required String function, required String module, String? buildId})
NativeCallsite({required List<NativeFrame> frames, required int allocBytes,
                required int allocCount, required int freeBytes, required int freeCount})
NativeProfileMeta({int? pid, String? package, int? samplingIntervalBytes})
NativeHeapProfile({required DateTime capturedAt, required String label,
                   required List<NativeCallsite> callsites, required NativeProfileMeta meta})
// NativeProfileParser: NativeHeapProfile parse(Object source, {String label = ''});
```

---

### Task 1: Scaffold `radar_native_host` package

**Files:**
- Create: `packages/radar_native_host/pubspec.yaml`
- Create: `packages/radar_native_host/analysis_options.yaml`
- Create: `packages/radar_native_host/lib/radar_native_host.dart` (barrel)
- Create: `packages/radar_native_host/test/scaffold_test.dart`
- Modify: root `pubspec.yaml` workspace list (add `packages/radar_native_host`)

**Interfaces:**
- Consumes: `package:radar_native` (path dep within the workspace).
- Produces: an importable, analyze-clean empty package that resolves `radar_native`.

- [ ] **Step 1: pubspec** — `name: radar_native_host`, `publish_to: none`, `environment: sdk` matching the other packages, `resolution: workspace`, deps: `radar_native` (path or workspace), `meta`; dev_deps: `test`, `lints` (or whatever `leak_graph` uses). Mirror `packages/leak_graph/pubspec.yaml` shape.
- [ ] **Step 2: analysis_options** — copy `packages/leak_graph/analysis_options.yaml` verbatim.
- [ ] **Step 3: barrel** — `library;` with a doc comment; exports added as later tasks land.
- [ ] **Step 4: smoke test** — a test that imports `package:radar_native/radar_native.dart` and asserts a trivial fact (e.g. `NativeProfileMeta().pid` is null), proving the dep resolves.
- [ ] **Step 5: add to root workspace**, run `dart pub get` at root, `dart test` + `dart analyze --fatal-infos` in the package.
- [ ] **Step 6: Commit** `feat(radar_native_host): scaffold host-side Perfetto parser package`.

---

### Task 2: `PerfettoProfileMapper` — pure rows → `NativeHeapProfile`

**Files:**
- Create: `packages/radar_native_host/lib/src/perfetto/perfetto_row.dart`
- Create: `packages/radar_native_host/lib/src/perfetto/perfetto_profile_mapper.dart`
- Create: `packages/radar_native_host/test/perfetto_profile_mapper_test.dart`
- Modify: barrel to export both.

**Interfaces:**
- Consumes: `NativeFrame`/`NativeCallsite`/`NativeHeapProfile`/`NativeProfileMeta`/`NativeProfileParser` from `radar_native`.
- Produces:
  ```dart
  /// One denormalized row from the still-live query: a single stack frame of a
  /// single allocating callsite, carrying that callsite's aggregate accounting.
  class PerfettoRow {
    const PerfettoRow({
      required this.callsiteId, required this.depth,
      required this.function, required this.module, this.buildId,
      required this.allocBytes, required this.allocCount,
      required this.freeBytes, required this.freeCount,
    });
    // ... fields; a factory `PerfettoRow.fromCells(List<String> cells)`
  }
  /// Pure mapper: groups rows by callsiteId, orders each group by depth
  /// (leaf-first) into frames, and builds one NativeCallsite per callsite.
  final class PerfettoProfileMapper implements NativeProfileParser {
    const PerfettoProfileMapper({this.capturedAt, this.meta});
    // source is List<PerfettoRow>
    NativeHeapProfile parse(Object source, {String label = ''});
  }
  ```

- [ ] **Step 1: Write failing tests** (`perfetto_profile_mapper_test.dart`):
```dart
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

PerfettoRow row(int cid, int depth, String fn, String mod,
    {String? build, int ab = 0, int ac = 0, int fb = 0, int fc = 0}) =>
    PerfettoRow(callsiteId: cid, depth: depth, function: fn, module: mod,
        buildId: build, allocBytes: ab, allocCount: ac, freeBytes: fb, freeCount: fc);

void main() {
  final when = DateTime.utc(2026, 7, 3);
  test('one callsite, multi-frame stack ordered leaf-first', () {
    final rows = [
      row(7, 0, 'malloc', 'libc.so', ab: 1024, ac: 2, fb: 0, fc: 0),
      row(7, 1, 'flutter::Foo', 'libflutter.so', build: 'abc', ab: 1024, ac: 2),
      row(7, 2, '', 'base.apk', ab: 1024, ac: 2),
    ];
    final p = PerfettoProfileMapper(capturedAt: when).parse(rows, label: 'after');
    expect(p.label, 'after');
    expect(p.capturedAt, when);
    expect(p.callsites, hasLength(1));
    final c = p.callsites.single;
    expect(c.frames.map((f) => f.module).toList(),
        ['libc.so', 'libflutter.so', 'base.apk']); // leaf-first
    expect(c.frames[1].function, 'flutter::Foo');
    expect(c.frames[1].buildId, 'abc');
    expect(c.frames[2].function, ''); // unsymbolized stays empty
    expect(c.frames[2].buildId, isNull);
    expect(c.allocBytes, 1024);
    expect(c.stillLiveBytes, 1024); // alloc - free
  });

  test('alloc and free split; still-live subtracts', () {
    final rows = [row(1, 0, 'malloc', 'libc.so', ab: 4096, ac: 4, fb: 1024, fc: 1)];
    final c = PerfettoProfileMapper(capturedAt: when).parse(rows).callsites.single;
    expect(c.allocBytes, 4096);
    expect(c.freeBytes, 1024);
    expect(c.stillLiveBytes, 3072);
    expect(c.stillLiveCount, 3);
  });

  test('multiple callsites become multiple NativeCallsites', () {
    final rows = [
      row(1, 0, 'malloc', 'libc.so', ab: 10),
      row(2, 0, 'calloc', 'libc.so', ab: 20),
    ];
    final p = PerfettoProfileMapper(capturedAt: when).parse(rows);
    expect(p.callsites, hasLength(2));
    expect(p.totalStillLiveBytes, 30);
  });

  test('empty rows -> empty profile', () {
    final p = PerfettoProfileMapper(capturedAt: when).parse(<PerfettoRow>[]);
    expect(p.callsites, isEmpty);
    expect(p.totalStillLiveBytes, 0);
  });

  test('meta is carried through', () {
    final p = PerfettoProfileMapper(
      capturedAt: when,
      meta: const NativeProfileMeta(pid: 42, package: 'com.x', samplingIntervalBytes: 4096),
    ).parse(<PerfettoRow>[]);
    expect(p.meta.pid, 42);
    expect(p.meta.package, 'com.x');
  });
}
```
- [ ] **Step 2: Run — expect fail** (`dart test test/perfetto_profile_mapper_test.dart`) — types not defined.
- [ ] **Step 3: Implement `PerfettoRow`** with the fields above and a `factory PerfettoRow.fromCells(List<String> cells)` that parses `[callsiteId, depth, function, module, buildId, allocBytes, allocCount, freeBytes, freeCount]` (ints via `int.parse`; empty `buildId` → null; empty `function`/`module` kept as `''`).
- [ ] **Step 4: Implement `PerfettoProfileMapper.parse`:** cast `source` to `List<PerfettoRow>`; group by `callsiteId` preserving first-seen order; within each group sort by `depth` ascending → `frames` (leaf-first) as `NativeFrame(function, module, buildId)`; take alloc/free aggregates from any row of the group (they repeat); build `NativeCallsite`; assemble `NativeHeapProfile(capturedAt: capturedAt ?? <caller-supplied>, label: label, callsites: ..., meta: meta ?? const NativeProfileMeta())`. If `capturedAt` is null, require it — keep the field required via constructor default of "now is NOT allowed" (pass it in; the facade supplies it). Decision: make `capturedAt` a required constructor arg (a checkpoint must know its time; the facade passes it) — simplifies the null branch away.
- [ ] **Step 5: Run tests — expect pass.** `dart analyze --fatal-infos` clean.
- [ ] **Step 6: Commit** `feat(radar_native_host): PerfettoProfileMapper (pure rows -> NativeHeapProfile)`.

---

### Task 3: still-live SQL + `TraceProcessorRunner`

**Files:**
- Create: `packages/radar_native_host/lib/src/perfetto/perfetto_sql.dart`
- Create: `packages/radar_native_host/lib/src/perfetto/trace_processor_runner.dart`
- Create: `packages/radar_native_host/test/trace_processor_output_test.dart`
- Modify: barrel to export the runner interface + SQL.

**Interfaces:**
- Produces:
  ```dart
  /// The device-proven still-live-with-stack query. Emits ONE column named
  /// `row`: the 9 fields joined by U+001F, ordered by (callsiteId, depth).
  const String kStillLiveWithStackSql = '...';
  abstract interface class TraceProcessorRunner {
    Future<List<PerfettoRow>> query(String tracePath);
  }
  final class ProcessTraceProcessorRunner implements TraceProcessorRunner {
    const ProcessTraceProcessorRunner({required this.binaryPath});
    final String binaryPath;
  }
  /// Exposed for testing: parse trace_processor's stdout into rows.
  List<PerfettoRow> parseTraceProcessorOutput(String stdout);
  ```

**SQL (`kStillLiveWithStackSql`) — use verbatim; proven on device:**
```sql
with recursive
agg as (
  select callsite_id,
    sum(case when size  > 0 then size  else 0 end) as alloc_bytes,
    sum(case when count > 0 then count else 0 end) as alloc_count,
    sum(case when size  < 0 then -size  else 0 end) as free_bytes,
    sum(case when count < 0 then -count else 0 end) as free_count
  from heap_profile_allocation
  group by callsite_id
  having alloc_bytes > 0
),
chain(root_callsite, id, frame_id, parent_id, depth) as (
  select a.callsite_id, c.id, c.frame_id, c.parent_id, 0
  from agg a join stack_profile_callsite c on c.id = a.callsite_id
  union all
  select ch.root_callsite, c.id, c.frame_id, c.parent_id, ch.depth + 1
  from stack_profile_callsite c join chain ch on c.id = ch.parent_id
)
select
  ch.root_callsite || char(31) || ch.depth || char(31) ||
  coalesce(spf.name,'') || char(31) || coalesce(spm.name,'') || char(31) ||
  coalesce(spm.build_id,'') || char(31) ||
  a.alloc_bytes || char(31) || a.alloc_count || char(31) ||
  a.free_bytes  || char(31) || a.free_count as row
from chain ch
join agg a on a.callsite_id = ch.root_callsite
join stack_profile_frame spf on ch.frame_id = spf.id
left join stack_profile_mapping spm on spf.mapping = spm.id
order by ch.root_callsite, ch.depth;
```

- [ ] **Step 1: Write failing test** (`trace_processor_output_test.dart`) for `parseTraceProcessorOutput`:
```dart
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

void main() {
  test('parses quoted single-column US-delimited output, skips header', () {
    const us = '';
    final out = '"row"\n'
        '"7${us}0${us}malloc${us}libc.so$us${us}1024${us}2${us}0${us}0"\n'
        '"7${us}1${us}Foo::bar${us}libflutter.so${us}abc${us}1024${us}2${us}0${us}0"\n';
    final rows = parseTraceProcessorOutput(out);
    expect(rows, hasLength(2));
    expect(rows[0].callsiteId, 7);
    expect(rows[0].module, 'libc.so');
    expect(rows[0].buildId, isNull); // empty build_id field
    expect(rows[1].function, 'Foo::bar');
    expect(rows[1].buildId, 'abc');
  });

  test('handles CSV-escaped embedded quotes and ignores blank lines', () {
    const us = '';
    final out = '"row"\n\n'
        '"1${us}0${us}op""x""${us}libc.so$us${us}8${us}1${us}0${us}0"\n';
    final rows = parseTraceProcessorOutput(out);
    expect(rows, hasLength(1));
    expect(rows[0].function, 'op"x"'); // "" -> "
  });
}
```
- [ ] **Step 2: Run — expect fail.**
- [ ] **Step 3: Implement `parseTraceProcessorOutput`:** split into lines; drop the `"row"` header and blank lines; for each line strip the surrounding double-quotes and unescape `""`→`"`; split on U+001F into 9 cells; `PerfettoRow.fromCells`. Guard against short/garbage lines (skip with no throw, but count is exact in tests).
- [ ] **Step 4: Implement `kStillLiveWithStackSql`** (verbatim above) and `ProcessTraceProcessorRunner.query`: write the SQL to a temp file (`Directory.systemTemp.createTempSync`), run `Process.run(binaryPath, [tracePath, '-q', sqlFile])`, on non-zero exit throw a `TraceProcessorException` with stderr, else `parseTraceProcessorOutput(result.stdout as String)`; always clean up the temp file. (No unit test drives a real Process — covered by the gated integration test in Task 5; the output parser is fully tested here.)
- [ ] **Step 5: Run tests — expect pass.** analyze clean.
- [ ] **Step 6: Commit** `feat(radar_native_host): still-live SQL + trace_processor runner + output parser`.

---

### Task 4: `PerfettoTraceProcessorParser` async facade

**Files:**
- Create: `packages/radar_native_host/lib/src/perfetto/perfetto_trace_processor_parser.dart`
- Create: `packages/radar_native_host/test/perfetto_trace_processor_parser_test.dart`
- Modify: barrel to export it.

**Interfaces:**
- Consumes: `TraceProcessorRunner`, `PerfettoProfileMapper`.
- Produces:
  ```dart
  final class PerfettoTraceProcessorParser {
    const PerfettoTraceProcessorParser(this._runner);
    /// Runs the runner over [tracePath] and maps the rows into a checkpoint.
    Future<NativeHeapProfile> parseTrace(
      String tracePath, {
      required DateTime capturedAt,
      String label = '',
      NativeProfileMeta meta = const NativeProfileMeta(),
    });
  }
  ```

- [ ] **Step 1: Write failing test** with a fake runner (no binary):
```dart
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

class _FakeRunner implements TraceProcessorRunner {
  _FakeRunner(this.rows);
  final List<PerfettoRow> rows;
  String? lastPath;
  @override
  Future<List<PerfettoRow>> query(String tracePath) async {
    lastPath = tracePath;
    return rows;
  }
}

void main() {
  test('facade runs the runner and maps rows into a checkpoint', () async {
    final rows = [
      PerfettoRow(callsiteId: 1, depth: 0, function: 'malloc', module: 'libc.so',
          allocBytes: 2048, allocCount: 2, freeBytes: 0, freeCount: 0),
    ];
    final fake = _FakeRunner(rows);
    final parser = PerfettoTraceProcessorParser(fake);
    final when = DateTime.utc(2026, 7, 3);
    final p = await parser.parseTrace('/x/trace.pftrace',
        capturedAt: when, label: 'before',
        meta: const NativeProfileMeta(package: 'com.katim.leak_lab'));
    expect(fake.lastPath, '/x/trace.pftrace');
    expect(p.label, 'before');
    expect(p.capturedAt, when);
    expect(p.meta.package, 'com.katim.leak_lab');
    expect(p.totalStillLiveBytes, 2048);
  });
}
```
- [ ] **Step 2: Run — expect fail.**
- [ ] **Step 3: Implement** `parseTrace`: `final rows = await _runner.query(tracePath); return PerfettoProfileMapper(capturedAt: capturedAt, meta: meta).parse(rows, label: label);`
- [ ] **Step 4: Run tests — expect pass.** analyze clean.
- [ ] **Step 5: Commit** `feat(radar_native_host): PerfettoTraceProcessorParser async facade`.

---

### Task 5: Gated end-to-end integration test (real binary + real trace)

**Files:**
- Create: `packages/radar_native_host/test/integration/real_trace_test.dart`

**Interfaces:** none new — exercises `ProcessTraceProcessorParser` end to end when the environment supplies a binary and a trace.

- [ ] **Step 1: Write the gated test.** Read `RADAR_TP_BIN` (path to a `trace_processor` binary) and `RADAR_TP_TRACE` (path to a `.pftrace`) from `Platform.environment`. If either is unset, `return` early after a `print('[skip] set RADAR_TP_BIN and RADAR_TP_TRACE to run')` — the test must PASS (skip) in CI where they're unset.
```dart
import 'dart:io';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

void main() {
  test('parses a real .pftrace into a non-empty checkpoint', () async {
    final bin = Platform.environment['RADAR_TP_BIN'];
    final trace = Platform.environment['RADAR_TP_TRACE'];
    if (bin == null || trace == null) {
      print('[skip] set RADAR_TP_BIN and RADAR_TP_TRACE to run this test');
      return;
    }
    final parser = PerfettoTraceProcessorParser(
        ProcessTraceProcessorRunner(binaryPath: bin));
    final p = await parser.parseTrace(trace, capturedAt: DateTime.now(), label: 'real');
    expect(p.callsites, isNotEmpty);
    expect(p.totalStillLiveBytes, greaterThan(0));
    // leaf frame of the top callsite is an allocator in libc
    final top = (p.callsites.toList()
          ..sort((a, b) => b.stillLiveBytes.compareTo(a.stillLiveBytes)))
        .first;
    expect(top.frames.first.module, contains('libc.so'));
  });
}
```
- [ ] **Step 2: Run unset — expect PASS (skips).** `dart test test/integration/real_trace_test.dart`.
- [ ] **Step 3: Run against the local fixtures** (`.spikes/tools/trace_processor` + `.spikes/captures/leaklab.pftrace`) to confirm it really works end-to-end; record the observed top-callsite in the commit body. (This run is local-only; the committed test still skips in CI.)
- [ ] **Step 4: Commit** `test(radar_native_host): gated end-to-end real-trace integration test`.

---

## Self-review notes
- Spec coverage: seam impl (T2/T4), proven SQL semantics — signed deltas / alloc-free split / leaf-first frames / build-ids (T2/T3), robust output parsing (T3), gated real-trace proof (T5). ✓
- Purity: only `radar_native_host` uses `dart:io`; `radar_native` untouched. ✓
- Type consistency: `PerfettoRow` fields and the 9-field SQL column order match across T2/T3; mapper builds the exact `radar_native` constructors listed in Global Constraints. ✓
- Out of scope (do not build): adb capture, symbol-store resolution (build-ids are carried but not resolved), desktop UI, checkpoint diff (already in `radar_native.diffNativeProfiles`), caller-module collapsing (a consumer concern).
