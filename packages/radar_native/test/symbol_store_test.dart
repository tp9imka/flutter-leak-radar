import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

NativeHeapProfile prof(List<NativeCallsite> c) => NativeHeapProfile(
  capturedAt: DateTime.utc(2026, 7, 3),
  label: 'x',
  meta: const NativeProfileMeta(),
  callsites: c,
);

void main() {
  const store = SymbolStore({
    'abc': {'0x1000': 'Foo::bar'},
  });

  group('SymbolStore.resolve', () {
    test('resolves a known buildId + raw function', () {
      expect(store.resolve(buildId: 'abc', function: '0x1000'), 'Foo::bar');
    });

    test('returns null for an unknown buildId', () {
      expect(store.resolve(buildId: 'zzz', function: '0x1000'), isNull);
    });

    test('returns null for a function not in the build map', () {
      expect(store.resolve(buildId: 'abc', function: '0x2000'), isNull);
    });

    test('returns null when buildId is null', () {
      expect(store.resolve(buildId: null, function: '0x1000'), isNull);
    });

    test('isEmpty reflects an empty map', () {
      expect(const SymbolStore({}).isEmpty, isTrue);
      expect(store.isEmpty, isFalse);
    });
  });

  group('SymbolStore JSON', () {
    test('fromJson(toJson()) round-trips', () {
      final json = store.toJson();
      expect(json, {
        'abc': {'0x1000': 'Foo::bar'},
      });

      final restored = SymbolStore.fromJson(json);
      expect(restored.resolve(buildId: 'abc', function: '0x1000'), 'Foo::bar');
    });
  });

  group('applySymbolStore', () {
    test('symbolizes a matching module-only frame', () {
      final profile = prof([
        NativeCallsite(
          frames: [
            const NativeFrame(
              function: '0x1000',
              module: 'libx.so',
              buildId: 'abc',
            ),
          ],
          allocBytes: 4000,
          allocCount: 2,
          freeBytes: 1000,
          freeCount: 1,
        ),
      ]);

      final resolved = applySymbolStore(profile, store);

      final frame = resolved.callsites.single.frames.single;
      expect(frame.function, 'Foo::bar');
      expect(frame.module, 'libx.so');
      expect(frame.buildId, 'abc');
    });

    test('leaves a frame with an unknown buildId unchanged', () {
      final profile = prof([
        NativeCallsite(
          frames: [
            const NativeFrame(
              function: '0x1000',
              module: 'libx.so',
              buildId: 'zzz',
            ),
          ],
          allocBytes: 100,
          allocCount: 1,
          freeBytes: 0,
          freeCount: 0,
        ),
      ]);

      final resolved = applySymbolStore(profile, store);

      expect(resolved.callsites.single.frames.single.function, '0x1000');
    });

    test('leaves a frame with a function absent from the build map '
        'unchanged', () {
      final profile = prof([
        NativeCallsite(
          frames: [
            const NativeFrame(
              function: '0x9999',
              module: 'libx.so',
              buildId: 'abc',
            ),
          ],
          allocBytes: 100,
          allocCount: 1,
          freeBytes: 0,
          freeCount: 0,
        ),
      ]);

      final resolved = applySymbolStore(profile, store);

      expect(resolved.callsites.single.frames.single.function, '0x9999');
    });

    test('leaves a frame with a null buildId unchanged', () {
      final profile = prof([
        NativeCallsite(
          frames: [const NativeFrame(function: '0x1000', module: 'libx.so')],
          allocBytes: 100,
          allocCount: 1,
          freeBytes: 0,
          freeCount: 0,
        ),
      ]);

      final resolved = applySymbolStore(profile, store);

      expect(resolved.callsites.single.frames.single.function, '0x1000');
      expect(resolved.callsites.single.frames.single.buildId, isNull);
    });

    test('does not mutate the original profile (immutability)', () {
      final profile = prof([
        NativeCallsite(
          frames: [
            const NativeFrame(
              function: '0x1000',
              module: 'libx.so',
              buildId: 'abc',
            ),
          ],
          allocBytes: 100,
          allocCount: 1,
          freeBytes: 0,
          freeCount: 0,
        ),
      ]);

      final resolved = applySymbolStore(profile, store);

      expect(profile.callsites.single.frames.single.function, '0x1000');
      expect(resolved.callsites.single.frames.single.function, 'Foo::bar');
      expect(identical(resolved, profile), isFalse);
    });

    test('preserves allocBytes/allocCount/freeBytes/freeCount on the '
        'rebuilt callsite', () {
      final profile = prof([
        NativeCallsite(
          frames: [
            const NativeFrame(
              function: '0x1000',
              module: 'libx.so',
              buildId: 'abc',
            ),
          ],
          allocBytes: 4000,
          allocCount: 3,
          freeBytes: 1500,
          freeCount: 1,
        ),
      ]);

      final resolved = applySymbolStore(profile, store);
      final callsite = resolved.callsites.single;

      expect(callsite.allocBytes, 4000);
      expect(callsite.allocCount, 3);
      expect(callsite.freeBytes, 1500);
      expect(callsite.freeCount, 1);
    });

    test('preserves capturedAt/label/meta on the rebuilt profile', () {
      final profile = prof([
        NativeCallsite(
          frames: [
            const NativeFrame(
              function: '0x1000',
              module: 'libx.so',
              buildId: 'abc',
            ),
          ],
          allocBytes: 1,
          allocCount: 1,
          freeBytes: 0,
          freeCount: 0,
        ),
      ]);

      final resolved = applySymbolStore(profile, store);

      expect(resolved.capturedAt, profile.capturedAt);
      expect(resolved.label, profile.label);
      expect(resolved.meta.toJson(), profile.meta.toJson());
    });

    test('empty store leaves every frame unchanged', () {
      final profile = prof([
        NativeCallsite(
          frames: [
            const NativeFrame(
              function: '0x1000',
              module: 'libx.so',
              buildId: 'abc',
            ),
          ],
          allocBytes: 1,
          allocCount: 1,
          freeBytes: 0,
          freeCount: 0,
        ),
      ]);

      final resolved = applySymbolStore(profile, const SymbolStore({}));

      expect(resolved.callsites.single.frames.single.function, '0x1000');
    });
  });
}
