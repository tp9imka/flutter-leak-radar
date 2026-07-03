import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_native/radar_native.dart';

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
}
