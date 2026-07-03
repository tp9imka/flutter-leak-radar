import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';

/// Canned "before" checkpoint: two callsites, each an allocator leaf frame
/// (index 0, skipped by attribution) followed by the real caller frame.
NativeHeapProfile _beforeProfile() => NativeHeapProfile(
  capturedAt: DateTime(2026, 1, 1),
  label: 'before',
  meta: const NativeProfileMeta(),
  callsites: [
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0xdeadbeef',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libapp.so',
          buildId: 'BUILD_APP',
        ),
      ],
      allocBytes: 1000,
      allocCount: 10,
      freeBytes: 200,
      freeCount: 2,
    ),
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'calloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: 'DoWork',
          module: '/data/app/~~abc==/com.example.app-1/lib/arm64/libfoo.so',
          buildId: 'BUILD_FOO',
        ),
      ],
      allocBytes: 500,
      allocCount: 5,
      freeBytes: 100,
      freeCount: 1,
    ),
  ],
);

/// Canned "after" checkpoint: the app callsite grew, the plugin callsite
/// shrank — enough signal to exercise [NativeModuleDiff.deltaBytes] in both
/// directions.
NativeHeapProfile _afterProfile() => NativeHeapProfile(
  capturedAt: DateTime(2026, 1, 2),
  label: 'after',
  meta: const NativeProfileMeta(),
  callsites: [
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'malloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: '0xdeadbeef',
          module: '/data/app/~~abc==/com.example.app-1/base.apk!libapp.so',
          buildId: 'BUILD_APP',
        ),
      ],
      allocBytes: 1500,
      allocCount: 15,
      freeBytes: 200,
      freeCount: 2,
    ),
    NativeCallsite(
      frames: const [
        NativeFrame(function: 'calloc', module: '/system/lib64/libc.so'),
        NativeFrame(
          function: 'DoWork',
          module: '/data/app/~~abc==/com.example.app-1/lib/arm64/libfoo.so',
          buildId: 'BUILD_FOO',
        ),
      ],
      allocBytes: 500,
      allocCount: 5,
      freeBytes: 300,
      freeCount: 3,
    ),
  ],
);

/// `NativeModuleSummary`/`NativeModuleDiff` don't override `==`, so compare
/// their fields via records instead of relying on identity equality.
typedef _SummaryShape = (String, NativeModuleKind, int, int);

List<_SummaryShape> _summaryShapes(List<NativeModuleSummary> summaries) => [
  for (final s in summaries)
    (s.module, s.kind, s.stillLiveBytes, s.stillLiveCount),
];

typedef _DiffShape = (String, NativeModuleKind, int, int);

List<_DiffShape> _diffShapes(List<NativeModuleDiff> diffs) => [
  for (final d in diffs)
    (d.module, d.kind, d.beforeStillLiveBytes, d.afterStillLiveBytes),
];

class _FakeImporter implements NativeTraceImporter {
  _FakeImporter({
    Map<String, NativeHeapProfile> profilesByLabel = const {},
    this.symbolStore,
    this.ffiLog,
    this.traceError,
  }) : _profilesByLabel = profilesByLabel;

  final Map<String, NativeHeapProfile> _profilesByLabel;
  final SymbolStore? symbolStore;
  final FfiAllocationLog? ffiLog;
  final Object? traceError;

  int importTraceCalls = 0;

  @override
  Future<NativeHeapProfile> importTrace(
    String path, {
    required String label,
  }) async {
    importTraceCalls++;
    if (traceError != null) throw traceError!;
    final profile = _profilesByLabel[label];
    if (profile == null) {
      throw StateError('_FakeImporter has no canned profile for "$label"');
    }
    return profile;
  }

  @override
  Future<SymbolStore> importSymbolStore(String path) async {
    final store = symbolStore;
    if (store == null) throw StateError('_FakeImporter has no symbol store');
    return store;
  }

  @override
  Future<FfiAllocationLog> importFfiLog(String path) async {
    final log = ffiLog;
    if (log == null) throw StateError('_FakeImporter has no ffi log');
    return log;
  }
}

/// Fixed one-device probe result, enough to exercise [refreshDevices]
/// without touching real `adb`.
class _FakeDeviceProbe implements DeviceProbe {
  @override
  Future<List<AndroidDevice>> probe() async => const [
    AndroidDevice(serial: 'DEV', state: 'device', model: 'KATIM X3M'),
  ];
}

/// [BuildIdReader] stand-in keyed by exact `.so` path, so controller tests
/// can drive [SymbolStoreBuilder] without a real `llvm-readelf`.
class _FakeBuildIdReader implements BuildIdReader {
  _FakeBuildIdReader(this._buildIdBySoPath);

  final Map<String, String> _buildIdBySoPath;

  @override
  Future<String?> readBuildId(String soPath) async => _buildIdBySoPath[soPath];
}

/// [Symbolizer] stand-in keyed by address, so controller tests can drive
/// [SymbolStoreBuilder] without a real `llvm-symbolizer`.
class _FakeSymbolizer implements Symbolizer {
  _FakeSymbolizer(this._nameByAddress);

  final Map<int, String> _nameByAddress;

  @override
  Future<String?> symbolize({
    required String soPath,
    required int address,
  }) async => _nameByAddress[address];
}

/// A [BuildIdReader] that always throws [_error] — stands in for a missing
/// or misbehaving `llvm-readelf`.
class _ThrowingBuildIdReader implements BuildIdReader {
  _ThrowingBuildIdReader(this._error);

  final Object _error;

  @override
  Future<String?> readBuildId(String soPath) async => throw _error;
}

/// A [Symbolizer] that always throws [_error] — stands in for a misbehaving
/// `llvm-symbolizer` (a genuine tool failure, not "address unresolved").
class _ThrowingSymbolizer implements Symbolizer {
  _ThrowingSymbolizer(this._error);

  final Object _error;

  @override
  Future<String?> symbolize({
    required String soPath,
    required int address,
  }) async => throw _error;
}

/// Stands in for a real `adb`-driven capture: writes [bytes] dummy bytes
/// to `outputPath` (or throws, if [throwing]), and records the last call
/// so tests can assert the controller forwarded the right request.
class _FakeCapture implements NativeHeapCapture {
  _FakeCapture({this.bytes = 2048, this.throwing = false});

  final int bytes;
  final bool throwing;

  CaptureRequest? lastRequest;
  String? lastOutputPath;

  @override
  Future<String> capture(
    CaptureRequest request, {
    required String outputPath,
  }) async {
    lastRequest = request;
    lastOutputPath = outputPath;
    if (throwing) throw Exception('adb capture failed');
    File(outputPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(bytes, 0));
    return outputPath;
  }
}

void main() {
  group('importTrace', () {
    test('appends the checkpoint, selects it, and notifies', () async {
      final before = _beforeProfile();
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': before}),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.importTrace('before.pftrace', label: 'before');

      expect(controller.checkpoints, [before]);
      expect(controller.selectedIndex, 0);
      expect(controller.selected, before);
      expect(controller.state, NativeImportState.idle);
      expect(controller.errorMessage, isNull);
      expect(notifications, greaterThanOrEqualTo(2));
    });

    test('a second import appends and selects the newest checkpoint', () async {
      final before = _beforeProfile();
      final after = _afterProfile();
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': before, 'after': after}),
      );

      await controller.importTrace('before.pftrace', label: 'before');
      await controller.importTrace('after.pftrace', label: 'after');

      expect(controller.checkpoints, [before, after]);
      expect(controller.selectedIndex, 1);
      expect(controller.selected, after);
    });

    test('a thrown error sets state=error and errorMessage', () async {
      final controller = NativeProfilingController(
        _FakeImporter(traceError: Exception('boom')),
      );

      await controller.importTrace('bad.pftrace', label: 'before');

      expect(controller.state, NativeImportState.error);
      expect(controller.errorMessage, contains('boom'));
      expect(controller.checkpoints, isEmpty);
    });
  });

  group('selectedSummaries', () {
    test('equals summarizeByModule of the selected checkpoint', () async {
      final before = _beforeProfile();
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': before}),
      );
      await controller.importTrace('before.pftrace', label: 'before');

      expect(
        _summaryShapes(controller.selectedSummaries),
        _summaryShapes(summarizeByModule(before)),
      );
      expect(
        controller.selectedTotalStillLiveBytes,
        before.totalStillLiveBytes,
      );
    });

    test('returns const [] and 0 bytes when nothing is selected', () {
      final controller = NativeProfilingController(_FakeImporter());
      expect(controller.selected, isNull);
      expect(controller.selectedSummaries, isEmpty);
      expect(controller.selectedTotalStillLiveBytes, 0);
    });
  });

  group('symbol store', () {
    test('resolves frame functions in the derived selected view', () async {
      final before = _beforeProfile();
      final store = SymbolStore({
        'BUILD_APP': {'0xdeadbeef': 'MyApp::allocateBuffer'},
      });
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': before}, symbolStore: store),
      );
      await controller.importTrace('before.pftrace', label: 'before');

      // Unsymbolized: the raw checkpoint still carries the address.
      expect(
        controller.selected!.callsites.first.frames[1].function,
        '0xdeadbeef',
      );
      expect(controller.isSymbolized, isFalse);

      await controller.importSymbolStore('symbols.json');

      expect(controller.isSymbolized, isTrue);
      expect(
        controller.selectedSymbolized!.callsites.first.frames[1].function,
        'MyApp::allocateBuffer',
      );
      // The raw checkpoint itself is untouched — immutable derivation.
      expect(
        controller.selected!.callsites.first.frames[1].function,
        '0xdeadbeef',
      );
      expect(
        _summaryShapes(controller.selectedSummaries),
        _summaryShapes(summarizeByModule(applySymbolStore(before, store))),
      );
    });
  });

  group('diffCheckpoints', () {
    test('returns diffModuleSummaries for the given pair', () async {
      final before = _beforeProfile();
      final after = _afterProfile();
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': before, 'after': after}),
      );
      await controller.importTrace('before.pftrace', label: 'before');
      await controller.importTrace('after.pftrace', label: 'after');

      expect(
        _diffShapes(controller.diffCheckpoints(0, 1)),
        _diffShapes(diffModuleSummaries(before, after)),
      );
    });
  });

  group('selectCheckpoint', () {
    test('moves selectedIndex and notifies', () async {
      final before = _beforeProfile();
      final after = _afterProfile();
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': before, 'after': after}),
      );
      await controller.importTrace('before.pftrace', label: 'before');
      await controller.importTrace('after.pftrace', label: 'after');

      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.selectCheckpoint(0);

      expect(controller.selectedIndex, 0);
      expect(controller.selected, before);
      expect(notifications, 1);
    });
  });

  group('importFfiLog', () {
    test('stores the imported log and notifies', () async {
      final log = FfiAllocationLog(
        capturedAt: DateTime(2026, 1, 1),
        sites: const [],
      );
      final controller = NativeProfilingController(_FakeImporter(ffiLog: log));

      await controller.importFfiLog('ffi.json');

      expect(controller.ffiLog, log);
      expect(controller.state, NativeImportState.idle);
    });
  });

  group('canCapture', () {
    test('true when both capture seams are injected', () {
      final controller = NativeProfilingController(
        _FakeImporter(),
        deviceProbe: _FakeDeviceProbe(),
        capture: _FakeCapture(),
      );

      expect(controller.canCapture, isTrue);
    });

    test('false when neither capture seam is injected', () {
      final controller = NativeProfilingController(_FakeImporter());

      expect(controller.canCapture, isFalse);
    });
  });

  group('refreshDevices', () {
    test('populates devices, ends idle, and notifies', () async {
      final controller = NativeProfilingController(
        _FakeImporter(),
        deviceProbe: _FakeDeviceProbe(),
        capture: _FakeCapture(),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.refreshDevices();

      expect(controller.devices, hasLength(1));
      expect(controller.devices.single.serial, 'DEV');
      expect(controller.captureState, CaptureState.idle);
      expect(notifications, greaterThanOrEqualTo(1));
    });

    test('throws StateError when no device probe was injected', () {
      final controller = NativeProfilingController(_FakeImporter());

      expect(controller.refreshDevices(), throwsStateError);
    });

    test('clears a stale captureError after a successful refresh', () async {
      final controller = NativeProfilingController(
        _FakeImporter(),
        deviceProbe: _FakeDeviceProbe(),
        capture: _FakeCapture(throwing: true),
      );

      // Drive the controller into a captureError state first.
      await controller.captureAndImport(
        const CaptureRequest(packageId: 'com.example.app'),
      );
      expect(controller.captureError, isNotNull);

      await controller.refreshDevices();

      expect(controller.captureError, isNull);
      expect(controller.captureState, CaptureState.idle);
    });
  });

  group('captureAndImport', () {
    test('appends and selects a checkpoint on a successful capture', () async {
      final before = _beforeProfile();
      final fakeCapture = _FakeCapture(bytes: 4096);
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'com.katim.leak_lab': before}),
        deviceProbe: _FakeDeviceProbe(),
        capture: fakeCapture,
      );
      const request = CaptureRequest(
        packageId: 'com.katim.leak_lab',
        mode: CaptureMode.startup,
        durationMs: 12000,
        serial: 'DEV',
      );

      await controller.captureAndImport(request);

      expect(controller.checkpoints, [before]);
      expect(controller.selectedIndex, 0);
      expect(controller.captureState, CaptureState.idle);
      expect(fakeCapture.lastRequest, same(request));
      expect(fakeCapture.lastOutputPath, isNotEmpty);
    });

    test(
      'rejects a too-small capture without importing a checkpoint',
      () async {
        final controller = NativeProfilingController(
          _FakeImporter(),
          deviceProbe: _FakeDeviceProbe(),
          capture: _FakeCapture(bytes: 10),
        );

        await controller.captureAndImport(
          const CaptureRequest(packageId: 'com.example.app'),
        );

        expect(controller.captureState, CaptureState.error);
        expect(controller.captureError, contains('no data'));
        expect(controller.checkpoints, isEmpty);
      },
    );

    test('surfaces a thrown capture error without importing', () async {
      final controller = NativeProfilingController(
        _FakeImporter(),
        deviceProbe: _FakeDeviceProbe(),
        capture: _FakeCapture(throwing: true),
      );

      await controller.captureAndImport(
        const CaptureRequest(packageId: 'com.example.app'),
      );

      expect(controller.captureState, CaptureState.error);
      expect(controller.captureError, isNotNull);
      expect(controller.checkpoints, isEmpty);
    });

    test('throws StateError when no capture seam was injected', () {
      final controller = NativeProfilingController(_FakeImporter());

      expect(
        controller.captureAndImport(
          const CaptureRequest(packageId: 'com.example.app'),
        ),
        throwsStateError,
      );
    });
  });

  group('canResolveSymbols', () {
    test('false when no SymbolStoreBuilder was injected', () async {
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': _beforeProfile()}),
      );
      await controller.importTrace('before.pftrace', label: 'before');

      expect(controller.canResolveSymbols, isFalse);
    });

    test('false when a builder is injected but nothing is selected', () {
      final controller = NativeProfilingController(
        _FakeImporter(),
        symbolStoreBuilder: SymbolStoreBuilder(
          buildIdReader: _FakeBuildIdReader(const {}),
          symbolizer: _FakeSymbolizer(const {}),
        ),
      );

      expect(controller.selected, isNull);
      expect(controller.canResolveSymbols, isFalse);
    });

    test(
      'true once a builder is injected and a checkpoint is selected',
      () async {
        final controller = NativeProfilingController(
          _FakeImporter(profilesByLabel: {'before': _beforeProfile()}),
          symbolStoreBuilder: SymbolStoreBuilder(
            buildIdReader: _FakeBuildIdReader(const {}),
            symbolizer: _FakeSymbolizer(const {}),
          ),
        );
        await controller.importTrace('before.pftrace', label: 'before');

        expect(controller.canResolveSymbols, isTrue);
      },
    );
  });

  group('resolveSymbolsFromSoDir', () {
    late Directory soDir;

    setUp(() {
      soDir = Directory.systemTemp.createTempSync('radar_so_dir_test');
    });

    tearDown(() {
      if (soDir.existsSync()) soDir.deleteSync(recursive: true);
    });

    test('resolves a matched .so\'s addresses and applies the store', () async {
      final soPath = '${soDir.path}/libapp.so';
      File(soPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('not a real elf, just a marker file');
      final before = _beforeProfile();
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': before}),
        symbolStoreBuilder: SymbolStoreBuilder(
          buildIdReader: _FakeBuildIdReader({soPath: 'BUILD_APP'}),
          symbolizer: _FakeSymbolizer({0xdeadbeef: 'MyApp::allocateBuffer'}),
        ),
      );
      await controller.importTrace('before.pftrace', label: 'before');

      await controller.resolveSymbolsFromSoDir(soDir.path);

      expect(controller.state, NativeImportState.idle);
      expect(controller.errorMessage, isNull);
      expect(controller.isSymbolized, isTrue);
      expect(
        controller.selectedSymbolized!.callsites.first.frames[1].function,
        'MyApp::allocateBuffer',
      );
      expect(controller.symbolizeMessage, contains('Resolved 1 function'));
    });

    test('an empty directory resolves nothing and sets an honest message, '
        'without crashing', () async {
      final before = _beforeProfile();
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': before}),
        symbolStoreBuilder: SymbolStoreBuilder(
          buildIdReader: _FakeBuildIdReader(const {}),
          symbolizer: _FakeSymbolizer(const {}),
        ),
      );
      await controller.importTrace('before.pftrace', label: 'before');

      await controller.resolveSymbolsFromSoDir(soDir.path);

      expect(controller.state, NativeImportState.idle);
      expect(controller.isSymbolized, isFalse);
      expect(controller.symbolizeMessage, contains('nothing resolved'));
      // Raw checkpoint untouched, still module-only.
      expect(
        controller.selectedSymbolized!.callsites.first.frames[1].function,
        '0xdeadbeef',
      );
    });

    test('a ProcessException (tool missing from PATH) sets an honest error '
        'state, without crashing', () async {
      final soPath = '${soDir.path}/libapp.so';
      File(soPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('marker');
      final before = _beforeProfile();
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': before}),
        symbolStoreBuilder: SymbolStoreBuilder(
          buildIdReader: _ThrowingBuildIdReader(
            ProcessException('llvm-readelf', const []),
          ),
          symbolizer: _FakeSymbolizer(const {}),
        ),
      );
      await controller.importTrace('before.pftrace', label: 'before');

      await controller.resolveSymbolsFromSoDir(soDir.path);

      expect(controller.state, NativeImportState.error);
      expect(controller.errorMessage, contains('llvm-readelf'));
      expect(controller.errorMessage, contains('not found'));
    });

    test('a SymbolizeToolException (tool exited non-zero) sets an honest '
        'error state, without crashing', () async {
      final soPath = '${soDir.path}/libapp.so';
      File(soPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('marker');
      final before = _beforeProfile();
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': before}),
        symbolStoreBuilder: SymbolStoreBuilder(
          buildIdReader: _FakeBuildIdReader({soPath: 'BUILD_APP'}),
          symbolizer: _ThrowingSymbolizer(
            const SymbolizeToolException(
              'llvm-symbolizer exited with code 1',
              stderr: 'boom',
            ),
          ),
        ),
      );
      await controller.importTrace('before.pftrace', label: 'before');

      await controller.resolveSymbolsFromSoDir(soDir.path);

      expect(controller.state, NativeImportState.error);
      expect(controller.errorMessage, contains('Symbolization tool failed'));
    });

    test('throws StateError when no SymbolStoreBuilder was injected', () async {
      final controller = NativeProfilingController(
        _FakeImporter(profilesByLabel: {'before': _beforeProfile()}),
      );
      await controller.importTrace('before.pftrace', label: 'before');

      expect(controller.resolveSymbolsFromSoDir(soDir.path), throwsStateError);
    });

    test('throws StateError when no checkpoint is selected', () {
      final controller = NativeProfilingController(
        _FakeImporter(),
        symbolStoreBuilder: SymbolStoreBuilder(
          buildIdReader: _FakeBuildIdReader(const {}),
          symbolizer: _FakeSymbolizer(const {}),
        ),
      );

      expect(controller.resolveSymbolsFromSoDir(soDir.path), throwsStateError);
    });
  });
}
