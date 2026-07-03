import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

/// Maps a `.so` path to a canned build-id (or null for "no build-id").
class _FakeBuildIdReader implements BuildIdReader {
  _FakeBuildIdReader(this._buildIdBySoPath);

  final Map<String, String?> _buildIdBySoPath;

  @override
  Future<String?> readBuildId(String soPath) async => _buildIdBySoPath[soPath];
}

/// Maps a `(soPath, address)` pair to a canned symbol name (or null for
/// "did not resolve").
class _FakeSymbolizer implements Symbolizer {
  _FakeSymbolizer(this._nameByKey);

  final Map<(String, int), String?> _nameByKey;

  @override
  Future<String?> symbolize({
    required String soPath,
    required int address,
  }) async => _nameByKey[(soPath, address)];
}

NativeHeapProfile _profile(List<NativeCallsite> callsites) => NativeHeapProfile(
  capturedAt: DateTime.utc(2026, 7, 3),
  label: 'x',
  meta: const NativeProfileMeta(),
  callsites: callsites,
);

NativeFrame _frame(String function, {String? buildId, String module = 'lib'}) =>
    NativeFrame(function: function, module: module, buildId: buildId);

NativeCallsite _callsite(List<NativeFrame> frames) => NativeCallsite(
  frames: frames,
  allocBytes: 100,
  allocCount: 1,
  freeBytes: 0,
  freeCount: 0,
);

void main() {
  group('SymbolStoreBuilder', () {
    test('resolves addresses under a matched build-id, leaves an unmatched '
        'build-id out of the store', () async {
      final profile = _profile([
        _callsite([
          _frame('0x1000', buildId: 'buildA', module: 'libA.so'),
          _frame('0x2000', buildId: 'buildA', module: 'libA.so'),
        ]),
        _callsite([_frame('0x3000', buildId: 'buildB', module: 'libB.so')]),
      ]);
      final builder = SymbolStoreBuilder(
        buildIdReader: _FakeBuildIdReader({'/so/libA.so': 'buildA'}),
        symbolizer: _FakeSymbolizer({
          ('/so/libA.so', 0x1000): 'flutter::Foo::bar',
          ('/so/libA.so', 0x2000): 'flutter::Foo::baz',
        }),
      );

      final store = await builder.build(profile, soPaths: ['/so/libA.so']);

      expect(store.byBuildId.keys, ['buildA']);
      expect(store.byBuildId['buildA'], {
        '0x1000': 'flutter::Foo::bar',
        '0x2000': 'flutter::Foo::baz',
      });
      expect(store.byBuildId.containsKey('buildB'), isFalse);
    });

    test('applySymbolStore names the matched build-id\'s frames and leaves the '
        'unmatched build-id\'s frame module-only', () async {
      final profile = _profile([
        _callsite([_frame('0x1000', buildId: 'buildA', module: 'libA.so')]),
        _callsite([_frame('0x3000', buildId: 'buildB', module: 'libB.so')]),
      ]);
      final builder = SymbolStoreBuilder(
        buildIdReader: _FakeBuildIdReader({'/so/libA.so': 'buildA'}),
        symbolizer: _FakeSymbolizer({
          ('/so/libA.so', 0x1000): 'flutter::Foo::bar',
        }),
      );

      final store = await builder.build(profile, soPaths: ['/so/libA.so']);
      final resolved = applySymbolStore(profile, store);

      final frameA = resolved.callsites[0].frames.single;
      final frameB = resolved.callsites[1].frames.single;
      expect(frameA.function, 'flutter::Foo::bar');
      expect(frameA.function.startsWith('0x'), isFalse);
      expect(frameB.function, '0x3000');
    });

    test(
      'report counts matched/unmatched build-ids and resolved addresses',
      () async {
        final profile = _profile([
          _callsite([
            _frame('0x1000', buildId: 'buildA', module: 'libA.so'),
            _frame('0x2000', buildId: 'buildA', module: 'libA.so'),
          ]),
          _callsite([_frame('0x3000', buildId: 'buildB', module: 'libB.so')]),
        ]);
        final builder = SymbolStoreBuilder(
          buildIdReader: _FakeBuildIdReader({'/so/libA.so': 'buildA'}),
          symbolizer: _FakeSymbolizer({
            ('/so/libA.so', 0x1000): 'flutter::Foo::bar',
            ('/so/libA.so', 0x2000): 'flutter::Foo::baz',
          }),
        );

        final report = await builder.buildWithReport(
          profile,
          soPaths: ['/so/libA.so'],
        );

        expect(report.matchedBuildIds, 1);
        expect(report.unmatchedBuildIds, 1);
        expect(report.resolvedAddresses, 2);
        expect(report.unresolvedAddresses, 0);
      },
    );

    test('an address the symbolizer cannot resolve is absent from the store '
        'and counted as unresolved', () async {
      final profile = _profile([
        _callsite([
          _frame('0x1000', buildId: 'buildA', module: 'libA.so'),
          _frame('0x2000', buildId: 'buildA', module: 'libA.so'),
        ]),
      ]);
      final builder = SymbolStoreBuilder(
        buildIdReader: _FakeBuildIdReader({'/so/libA.so': 'buildA'}),
        symbolizer: _FakeSymbolizer({
          ('/so/libA.so', 0x1000): 'flutter::Foo::bar',
          ('/so/libA.so', 0x2000): null,
        }),
      );

      final report = await builder.buildWithReport(
        profile,
        soPaths: ['/so/libA.so'],
      );

      expect(report.store.byBuildId['buildA'], {'0x1000': 'flutter::Foo::bar'});
      expect(report.resolvedAddresses, 1);
      expect(report.unresolvedAddresses, 1);
      expect(report.matchedBuildIds, 1);
      expect(report.unmatchedBuildIds, 0);
    });

    test('an already-symbolized frame is ignored', () async {
      final profile = _profile([
        _callsite([
          _frame(
            'flutter::Already::Named',
            buildId: 'buildA',
            module: 'libA.so',
          ),
        ]),
      ]);
      final builder = SymbolStoreBuilder(
        buildIdReader: _FakeBuildIdReader({'/so/libA.so': 'buildA'}),
        symbolizer: _FakeSymbolizer({}),
      );

      final report = await builder.buildWithReport(
        profile,
        soPaths: ['/so/libA.so'],
      );

      expect(report.store.isEmpty, isTrue);
      expect(report.matchedBuildIds, 0);
      expect(report.unmatchedBuildIds, 0);
      expect(report.resolvedAddresses, 0);
      expect(report.unresolvedAddresses, 0);
    });

    test('a frame with no buildId is ignored', () async {
      final profile = _profile([
        _callsite([_frame('0x1000', module: 'libA.so')]),
      ]);
      final builder = SymbolStoreBuilder(
        buildIdReader: _FakeBuildIdReader({}),
        symbolizer: _FakeSymbolizer({}),
      );

      final report = await builder.buildWithReport(profile, soPaths: []);

      expect(report.store.isEmpty, isTrue);
      expect(report.matchedBuildIds, 0);
      expect(report.unmatchedBuildIds, 0);
    });

    test(
      'a .so file with no build-id (null) is skipped, not an error',
      () async {
        final profile = _profile([
          _callsite([_frame('0x1000', buildId: 'buildA', module: 'libA.so')]),
        ]);
        final builder = SymbolStoreBuilder(
          buildIdReader: _FakeBuildIdReader({'/so/libA.so': null}),
          symbolizer: _FakeSymbolizer({}),
        );

        final report = await builder.buildWithReport(
          profile,
          soPaths: ['/so/libA.so'],
        );

        expect(report.store.isEmpty, isTrue);
        expect(report.unmatchedBuildIds, 1);
      },
    );

    test('the first .so wins when two files share a build-id', () async {
      final profile = _profile([
        _callsite([_frame('0x1000', buildId: 'buildA', module: 'libA.so')]),
      ]);
      final builder = SymbolStoreBuilder(
        buildIdReader: _FakeBuildIdReader({
          '/so/first.so': 'buildA',
          '/so/second.so': 'buildA',
        }),
        symbolizer: _FakeSymbolizer({('/so/first.so', 0x1000): 'first::Name'}),
      );

      final store = await builder.build(
        profile,
        soPaths: ['/so/first.so', '/so/second.so'],
      );

      expect(store.byBuildId['buildA'], {'0x1000': 'first::Name'});
    });

    test(
      'a genuine tool failure from the build-id reader propagates',
      () async {
        final profile = _profile([
          _callsite([_frame('0x1000', buildId: 'buildA', module: 'libA.so')]),
        ]);
        final builder = SymbolStoreBuilder(
          buildIdReader: _ThrowingBuildIdReader(),
          symbolizer: _FakeSymbolizer({}),
        );

        expect(
          () => builder.build(profile, soPaths: ['/so/libA.so']),
          throwsA(isA<SymbolizeToolException>()),
        );
      },
    );

    test('same inputs produce an identical store (deterministic)', () async {
      final profile = _profile([
        _callsite([
          _frame('0x1000', buildId: 'buildA', module: 'libA.so'),
          _frame('0x2000', buildId: 'buildA', module: 'libA.so'),
        ]),
      ]);
      SymbolStoreBuilder makeBuilder() => SymbolStoreBuilder(
        buildIdReader: _FakeBuildIdReader({'/so/libA.so': 'buildA'}),
        symbolizer: _FakeSymbolizer({
          ('/so/libA.so', 0x1000): 'flutter::Foo::bar',
          ('/so/libA.so', 0x2000): 'flutter::Foo::baz',
        }),
      );

      final storeOne = await makeBuilder().build(
        profile,
        soPaths: ['/so/libA.so'],
      );
      final storeTwo = await makeBuilder().build(
        profile,
        soPaths: ['/so/libA.so'],
      );

      expect(storeOne.toJson(), storeTwo.toJson());
    });
  });
}

class _ThrowingBuildIdReader implements BuildIdReader {
  @override
  Future<String?> readBuildId(String soPath) async =>
      throw const SymbolizeToolException('boom', stderr: 'no such file');
}
