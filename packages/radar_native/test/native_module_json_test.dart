import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

void main() {
  group('NativeDiffStatus JSON', () {
    test('every value round-trips by name', () {
      for (final status in NativeDiffStatus.values) {
        expect(NativeDiffStatus.fromJson(status.toJson()), status);
        expect(status.toJson(), status.name);
      }
    });

    test('fromJson throws on an unknown name', () {
      expect(
        () => NativeDiffStatus.fromJson('exploded'),
        throwsFormatException,
      );
    });
  });

  group('NativeModuleDiff JSON', () {
    test('round-trips all fields and preserves the kind name', () {
      const diff = NativeModuleDiff(
        module: 'libwebrtc.so',
        kind: NativeModuleKind.plugin,
        beforeStillLiveBytes: 1500,
        afterStillLiveBytes: 4200,
      );
      final back = NativeModuleDiff.fromJson(diff.toJson());
      expect(back.module, 'libwebrtc.so');
      expect(back.kind, NativeModuleKind.plugin);
      expect(back.beforeStillLiveBytes, 1500);
      expect(back.afterStillLiveBytes, 4200);
      // Derived fields survive because their inputs did.
      expect(back.deltaBytes, 2700);
      expect(back.status, NativeDiffStatus.grew);
    });

    test('fromJson throws on an unknown kind name', () {
      final json = {
        'module': 'x',
        'kind': 'notAKind',
        'beforeStillLiveBytes': 0,
        'afterStillLiveBytes': 1,
      };
      expect(() => NativeModuleDiff.fromJson(json), throwsFormatException);
    });
  });

  group('NativeModuleSummary JSON', () {
    test('round-trips including nested callsites', () {
      const summary = NativeModuleSummary(
        module: 'libflutter.so',
        kind: NativeModuleKind.engine,
        stillLiveBytes: 9000,
        stillLiveCount: 12,
        callsites: [
          NativeCallsite(
            frames: [
              NativeFrame(
                function: 'SkStrikeCache::add',
                module: 'libflutter.so',
              ),
            ],
            allocBytes: 9000,
            allocCount: 12,
            freeBytes: 0,
            freeCount: 0,
          ),
        ],
      );
      final back = NativeModuleSummary.fromJson(summary.toJson());
      expect(back.module, 'libflutter.so');
      expect(back.kind, NativeModuleKind.engine);
      expect(back.stillLiveBytes, 9000);
      expect(back.stillLiveCount, 12);
      expect(
        back.callsites.single.frames.single.function,
        'SkStrikeCache::add',
      );
      expect(back.callsites.single.stillLiveBytes, 9000);
    });

    test('round-trips with no callsites', () {
      const summary = NativeModuleSummary(
        module: '',
        kind: NativeModuleKind.unknown,
        stillLiveBytes: 0,
        stillLiveCount: 0,
        callsites: [],
      );
      final back = NativeModuleSummary.fromJson(summary.toJson());
      expect(back.callsites, isEmpty);
      expect(back.kind, NativeModuleKind.unknown);
    });
  });
}
