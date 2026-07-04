import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/seams/android/lazy_tool_seams.dart';
import 'package:radar_native_host/radar_native_host.dart';

class _FakeAdbRunner implements AdbRunner {
  @override
  Future<AdbResult> run(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async => const AdbResult(0, '', '');
}

class _FakeSymbolizer implements Symbolizer {
  @override
  Future<String?> symbolize({
    required String soPath,
    required int address,
  }) async => 'fake';
}

class _FakeBuildIdReader implements BuildIdReader {
  @override
  Future<String?> readBuildId(String soPath) async => 'fake-build-id';
}

void main() {
  group('LazyAdbRunner', () {
    test('builds its delegate from the resolver\'s current path', () async {
      var current = '/first/adb';
      String? seenPath;
      final runner = LazyAdbRunner(
        () => current,
        runnerFor: (path) {
          seenPath = path;
          return _FakeAdbRunner();
        },
      );

      await runner.run(['devices']);
      expect(seenPath, '/first/adb');

      current = '/second/adb';
      await runner.run(['devices']);
      expect(
        seenPath,
        '/second/adb',
        reason: 'a changed resolver result is picked up on the next call',
      );
    });

    test(
      'falls back to the bare "adb" name when the resolver is null',
      () async {
        String? seenPath;
        final runner = LazyAdbRunner(
          null,
          runnerFor: (path) {
            seenPath = path;
            return _FakeAdbRunner();
          },
        );

        await runner.run(['devices']);
        expect(seenPath, 'adb');
      },
    );

    test(
      'falls back to the bare "adb" name when the resolver returns null',
      () async {
        String? seenPath;
        final runner = LazyAdbRunner(
          () => null,
          runnerFor: (path) {
            seenPath = path;
            return _FakeAdbRunner();
          },
        );

        await runner.run(['devices']);
        expect(seenPath, 'adb');
      },
    );

    test('forwards args/serial/stdin to the delegate', () async {
      final calls = <List<String>>[];
      final runner = LazyAdbRunner(
        () => '/x/adb',
        runnerFor: (_) => _RecordingAdbRunner(calls),
      );

      final result = await runner.run(
        ['shell', 'echo'],
        serial: 'abc123',
        stdin: 'hello',
      );

      expect(calls, [
        ['shell', 'echo'],
      ]);
      expect(result.ok, isTrue);
    });
  });

  group('LazySymbolizer', () {
    test('builds its delegate from the resolver\'s current path', () async {
      var current = '/first/llvm-symbolizer';
      String? seenPath;
      final symbolizer = LazySymbolizer(
        () => current,
        symbolizerFor: (path) {
          seenPath = path;
          return _FakeSymbolizer();
        },
      );

      await symbolizer.symbolize(soPath: 'lib.so', address: 0x10);
      expect(seenPath, '/first/llvm-symbolizer');

      current = '/second/llvm-symbolizer';
      await symbolizer.symbolize(soPath: 'lib.so', address: 0x10);
      expect(seenPath, '/second/llvm-symbolizer');
    });

    test('falls back to the bare "llvm-symbolizer" name when the resolver '
        'is null', () async {
      String? seenPath;
      final symbolizer = LazySymbolizer(
        null,
        symbolizerFor: (path) {
          seenPath = path;
          return _FakeSymbolizer();
        },
      );

      await symbolizer.symbolize(soPath: 'lib.so', address: 0x10);
      expect(seenPath, 'llvm-symbolizer');
    });
  });

  group('LazyBuildIdReader', () {
    test('builds its delegate from the resolver\'s current path', () async {
      var current = '/first/llvm-readelf';
      String? seenPath;
      final reader = LazyBuildIdReader(
        () => current,
        readerFor: (path) {
          seenPath = path;
          return _FakeBuildIdReader();
        },
      );

      await reader.readBuildId('lib.so');
      expect(seenPath, '/first/llvm-readelf');

      current = '/second/llvm-readelf';
      await reader.readBuildId('lib.so');
      expect(seenPath, '/second/llvm-readelf');
    });

    test('falls back to the bare "llvm-readelf" name when the resolver is '
        'null', () async {
      String? seenPath;
      final reader = LazyBuildIdReader(
        null,
        readerFor: (path) {
          seenPath = path;
          return _FakeBuildIdReader();
        },
      );

      await reader.readBuildId('lib.so');
      expect(seenPath, 'llvm-readelf');
    });
  });
}

class _RecordingAdbRunner implements AdbRunner {
  _RecordingAdbRunner(this.calls);

  final List<List<String>> calls;

  @override
  Future<AdbResult> run(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async {
    calls.add(args);
    return const AdbResult(0, '', '');
  }
}
