import 'dart:convert';
import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

class _FakeRunner implements TraceProcessorRunner {
  _FakeRunner(this.rows);
  final List<PerfettoRow> rows;

  @override
  Future<List<PerfettoRow>> query(String tracePath) async => rows;
}

class _FakeBuildIdReader implements BuildIdReader {
  _FakeBuildIdReader(this._buildIdBySoPath);
  final Map<String, String?> _buildIdBySoPath;

  @override
  Future<String?> readBuildId(String soPath) async => _buildIdBySoPath[soPath];
}

class _FakeSymbolizer implements Symbolizer {
  _FakeSymbolizer(this._nameByKey);
  final Map<(String, int), String?> _nameByKey;

  @override
  Future<String?> symbolize({
    required String soPath,
    required int address,
  }) async => _nameByKey[(soPath, address)];
}

class _ThrowingToolBuildIdReader implements BuildIdReader {
  @override
  Future<String?> readBuildId(String soPath) async =>
      throw const SymbolizeToolException('boom', stderr: 'bad ELF notes');
}

class _MissingBinaryBuildIdReader implements BuildIdReader {
  @override
  Future<String?> readBuildId(String soPath) async =>
      throw const ProcessException(
        'llvm-readelf',
        ['-n', '/x'],
        'No such file or directory',
        2,
      );
}

/// Builds a single-frame, name-less row so the mapper synthesizes the
/// `0x<hex>` unsymbolized address from [relPc].
PerfettoRow _row({
  required String module,
  required String buildId,
  required int relPc,
}) => PerfettoRow(
  callsiteId: 1,
  depth: 0,
  function: '',
  module: module,
  buildId: buildId,
  allocBytes: 100,
  allocCount: 1,
  freeBytes: 0,
  freeCount: 0,
  relPc: relPc,
);

void main() {
  group('runSymbolize', () {
    late Directory tempDir;
    late String tracePath;
    late String outPath;
    late String soPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('symbolize_cli_test_');
      tracePath = '${tempDir.path}/capture.pftrace';
      File(tracePath).writeAsStringSync('unused by the fake runner');
      outPath = '${tempDir.path}/symbols.json';
      soPath = '${tempDir.path}/libA.so';
      File(soPath).writeAsStringSync('unused by the fake reader');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('writes the resolved symbol store JSON and returns 0', () async {
      final err = StringBuffer();
      final out = StringBuffer();

      final exitCode = await runSymbolize(
        ['--trace', tracePath, '--so', soPath, '--out', outPath],
        runner: _FakeRunner([
          _row(module: 'libA.so', buildId: 'buildA', relPc: 0x1000),
        ]),
        reader: _FakeBuildIdReader({soPath: 'buildA'}),
        symbolizer: _FakeSymbolizer({(soPath, 0x1000): 'flutter::Foo::bar'}),
        out: out,
        err: err,
      );

      expect(exitCode, 0);
      expect(err.toString(), isEmpty);
      final written =
          jsonDecode(File(outPath).readAsStringSync()) as Map<String, Object?>;
      expect(written, {
        'buildA': {'0x1000': 'flutter::Foo::bar'},
      });
      expect(out.toString(), contains('matched 1/1 build-ids'));
      expect(out.toString(), contains('resolved 1/1 addresses'));
      expect(out.toString(), contains(outPath));
    });

    test('gathers .so files from every --so-dir', () async {
      final soDir = Directory('${tempDir.path}/so-dir')..createSync();
      final dirSoPath = '${soDir.path}/libB.so';
      File(dirSoPath).writeAsStringSync('unused by the fake reader');
      final out = StringBuffer();

      final exitCode = await runSymbolize(
        ['--trace', tracePath, '--so-dir', soDir.path, '--out', outPath],
        runner: _FakeRunner([
          _row(module: 'libB.so', buildId: 'buildB', relPc: 0x2000),
        ]),
        reader: _FakeBuildIdReader({dirSoPath: 'buildB'}),
        symbolizer: _FakeSymbolizer({(dirSoPath, 0x2000): 'flutter::Foo::baz'}),
        out: out,
        err: StringBuffer(),
      );

      expect(exitCode, 0);
      final written =
          jsonDecode(File(outPath).readAsStringSync()) as Map<String, Object?>;
      expect(written, {
        'buildB': {'0x2000': 'flutter::Foo::baz'},
      });
    });

    test('missing --trace returns non-zero with a clear message', () async {
      final err = StringBuffer();

      final exitCode = await runSymbolize(
        ['--so', soPath, '--out', outPath],
        runner: _FakeRunner(const []),
        reader: _FakeBuildIdReader(const {}),
        symbolizer: _FakeSymbolizer(const {}),
        err: err,
      );

      expect(exitCode, isNot(0));
      expect(err.toString(), contains('--trace'));
      expect(File(outPath).existsSync(), isFalse);
    });

    test('missing --out returns non-zero with a clear message', () async {
      final err = StringBuffer();

      final exitCode = await runSymbolize(
        ['--trace', tracePath, '--so', soPath],
        runner: _FakeRunner(const []),
        reader: _FakeBuildIdReader(const {}),
        symbolizer: _FakeSymbolizer(const {}),
        err: err,
      );

      expect(exitCode, isNot(0));
      expect(err.toString(), contains('--out'));
    });

    test(
      'no --so and no --so-dir returns non-zero with a clear message',
      () async {
        final err = StringBuffer();

        final exitCode = await runSymbolize(
          ['--trace', tracePath, '--out', outPath],
          runner: _FakeRunner(const []),
          reader: _FakeBuildIdReader(const {}),
          symbolizer: _FakeSymbolizer(const {}),
          err: err,
        );

        expect(exitCode, isNot(0));
        expect(err.toString(), contains('.so'));
        expect(File(outPath).existsSync(), isFalse);
      },
    );

    test('missing trace_processor (no --tp-bin, no RADAR_TP_BIN) returns '
        'non-zero with a clear message', () async {
      final err = StringBuffer();

      final exitCode = await runSymbolize(
        ['--trace', tracePath, '--so', soPath, '--out', outPath],
        env: const <String, String>{},
        err: err,
      );

      expect(exitCode, isNot(0));
      expect(err.toString(), contains('trace_processor'));
      expect(err.toString(), contains('RADAR_TP_BIN'));
    });

    test('a SymbolizeToolException from a seam is caught with a clear message, '
        'not an unhandled stack trace', () async {
      final err = StringBuffer();

      final exitCode = await runSymbolize(
        ['--trace', tracePath, '--so', soPath, '--out', outPath],
        runner: _FakeRunner([
          _row(module: 'libA.so', buildId: 'buildA', relPc: 0x1000),
        ]),
        reader: _ThrowingToolBuildIdReader(),
        symbolizer: _FakeSymbolizer(const {}),
        err: err,
      );

      expect(exitCode, isNot(0));
      expect(err.toString(), contains('bad ELF notes'));
      expect(File(outPath).existsSync(), isFalse);
    });

    test('a ProcessException (tool binary missing from PATH) is caught with a '
        'clear message, not an unhandled stack trace', () async {
      final err = StringBuffer();

      final exitCode = await runSymbolize(
        ['--trace', tracePath, '--so', soPath, '--out', outPath],
        runner: _FakeRunner([
          _row(module: 'libA.so', buildId: 'buildA', relPc: 0x1000),
        ]),
        reader: _MissingBinaryBuildIdReader(),
        symbolizer: _FakeSymbolizer(const {}),
        err: err,
      );

      expect(exitCode, isNot(0));
      expect(err.toString(), contains('llvm-readelf'));
      expect(err.toString(), contains('RADAR_READELF'));
      expect(File(outPath).existsSync(), isFalse);
    });
  });
}
