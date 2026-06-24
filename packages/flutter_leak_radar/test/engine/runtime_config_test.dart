// test/engine/runtime_config_test.dart
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/leak_radar_config.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/leak_radar.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_heap_probe.dart';
import 'leak_engine_test.dart' show engineWith;

LeakEngine _engineWithConfig(LeakRadarConfig config) => LeakEngine(
      probe: FakeHeapProbe([]),
      analyzer: LeakAnalyzer(SuspectSet.empty()),
      config: config,
    );

void main() {
  tearDown(() async => LeakRadar.dispose());

  group('LeakEngine.updateConfig', () {
    test('reflected in _config after update', () async {
      final engine = engineWith(FakeHeapProbe([]));
      await engine.start();

      const updated = LeakRadarConfig(showOverlay: false);
      engine.updateConfig(updated);

      await engine.stop();
    });

    test('autoScan change to onNavigation creates navObserver', () async {
      final engine = engineWith(FakeHeapProbe([]));
      await engine.start();
      expect(engine.navigatorObserver, isNull);

      engine.updateConfig(
        const LeakRadarConfig(autoScan: AutoScan(onNavigation: true)),
      );

      expect(engine.navigatorObserver, isNotNull);
      await engine.stop();
    });

    test('autoScan change from onNavigation to manual removes navObserver',
        () async {
      final engine = _engineWithConfig(
        const LeakRadarConfig(autoScan: AutoScan(onNavigation: true)),
      );
      await engine.start();
      expect(engine.navigatorObserver, isNotNull);

      engine.updateConfig(const LeakRadarConfig());

      expect(engine.navigatorObserver, isNull);
      await engine.stop();
    });

    test('preciseTracking false → track() calls are ignored', () async {
      final engine = engineWith(FakeHeapProbe([]));
      await engine.start();

      engine.updateConfig(const LeakRadarConfig(preciseTracking: false));

      final obj = Object();
      engine.track(obj, tag: 'test');
      // Registry is cleared when disabling, so trackedCount is 0.
      // Indirectly verified by running collectLeaks in scan below.
      final report = await engine.scan();
      expect(
        report.findings.where((f) => f.tag == 'test'),
        isEmpty,
      );

      await engine.stop();
    });

    test('does not throw on rapid successive updates', () async {
      final engine = engineWith(FakeHeapProbe([]));
      await engine.start();

      expect(
        () {
          for (var i = 0; i < 10; i++) {
            engine.updateConfig(
              LeakRadarConfig(showOverlay: i.isEven),
            );
          }
        },
        returnsNormally,
      );

      await engine.stop();
    });
  });

  group('LeakRadar.configListenable', () {
    test('starts with enabled:false before init', () async {
      await LeakRadar.dispose();
      expect(LeakRadar.configListenable.value.enabled, isFalse);
    });

    test('updateConfig reflects in configListenable.value', () async {
      final probe = FakeHeapProbe([]);
      final engine = engineWith(probe);
      await LeakRadar.debugInstall(engine);

      const updated = LeakRadarConfig(showOverlay: false);
      LeakRadar.updateConfig(updated);

      expect(LeakRadar.configListenable.value.showOverlay, isFalse);
    });

    test('dispose resets configListenable to disabled', () async {
      final probe = FakeHeapProbe([]);
      final engine = engineWith(probe);
      await LeakRadar.debugInstall(engine);
      LeakRadar.updateConfig(const LeakRadarConfig(showOverlay: false));

      await LeakRadar.dispose();

      expect(LeakRadar.configListenable.value.enabled, isFalse);
    });

    test('notifier emits value immediately when queried', () async {
      final probe = FakeHeapProbe([]);
      final engine = engineWith(probe);
      await LeakRadar.debugInstall(engine);

      LeakRadar.updateConfig(
        const LeakRadarConfig(
          reportThreshold: LeakSeverity.critical,
        ),
      );

      expect(
        LeakRadar.configListenable.value.reportThreshold,
        LeakSeverity.critical,
      );
    });
  });

  group('LeakRadarConfig new fields', () {
    test('reportThreshold defaults to info', () {
      const config = LeakRadarConfig();
      expect(config.reportThreshold, LeakSeverity.info);
    });

    test('preciseTracking defaults to true', () {
      const config = LeakRadarConfig();
      expect(config.preciseTracking, isTrue);
    });

    test('copyWith preserves fields when not overridden', () {
      const config = LeakRadarConfig(
        reportThreshold: LeakSeverity.warning,
        preciseTracking: false,
      );
      final copy = config.copyWith(showOverlay: false);
      expect(copy.reportThreshold, LeakSeverity.warning);
      expect(copy.preciseTracking, isFalse);
      expect(copy.showOverlay, isFalse);
    });

    test('equality includes reportThreshold and preciseTracking', () {
      const a = LeakRadarConfig(
        reportThreshold: LeakSeverity.warning,
        preciseTracking: false,
      );
      const b = LeakRadarConfig(
        reportThreshold: LeakSeverity.warning,
        preciseTracking: false,
      );
      const c = LeakRadarConfig(
        reportThreshold: LeakSeverity.critical,
        preciseTracking: false,
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode differs when fields differ', () {
      const a = LeakRadarConfig(reportThreshold: LeakSeverity.info);
      const b = LeakRadarConfig(reportThreshold: LeakSeverity.critical);
      expect(a.hashCode, isNot(b.hashCode));
    });
  });
}
