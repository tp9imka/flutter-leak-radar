// test/config/leak_radar_config_test.dart
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeakRadarConfig equality', () {
    const ruleA = LeakRule.maxLive('A', 1);

    test('configs differing only in rules are NOT equal', () {
      const withRule = LeakRadarConfig(rules: [ruleA]);
      const withoutRule = LeakRadarConfig(rules: []);
      expect(withRule == withoutRule, isFalse);
    });

    test('configs differing only in rules have different hashCodes', () {
      const withRule = LeakRadarConfig(rules: [ruleA]);
      const withoutRule = LeakRadarConfig(rules: []);
      expect(withRule.hashCode == withoutRule.hashCode, isFalse);
    });

    test('two fully-identical configs are equal with equal hashCodes', () {
      const a = LeakRadarConfig(rules: [ruleA]);
      const b = LeakRadarConfig(rules: [ruleA]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith(rules: ...) produces a config that differs by rules', () {
      const base = LeakRadarConfig(rules: []);
      final changed = base.copyWith(rules: [ruleA]);
      expect(base == changed, isFalse);
      expect(base.hashCode == changed.hashCode, isFalse);
    });
  });

  group('LeakRadarConfig.standard precise tuning', () {
    test('defaults match production values', () {
      final c = LeakRadarConfig.standard();
      expect(c.gcCyclesForPreciseLeak, 3);
      expect(c.disposalGrace, const Duration(seconds: 2));
    });

    test('forwards gcCyclesForPreciseLeak and disposalGrace', () {
      final c = LeakRadarConfig.standard(
        gcCyclesForPreciseLeak: 1,
        disposalGrace: const Duration(seconds: 1),
      );
      expect(c.gcCyclesForPreciseLeak, 1);
      expect(c.disposalGrace, const Duration(seconds: 1));
    });
  });

  group('LeakRadarConfig graphScan integration', () {
    test('standard(graphScan: GraphScan()) sets graphScan', () {
      final c = LeakRadarConfig.standard(graphScan: const GraphScan());
      expect(c.graphScan, isNotNull);
      expect(c.graphScan, equals(const GraphScan()));
    });

    test('standard() leaves graphScan null by default', () {
      final c = LeakRadarConfig.standard();
      expect(c.graphScan, isNull);
    });

    test('configs differing only by graphScan are not equal', () {
      const a = LeakRadarConfig(graphScan: GraphScan());
      const b = LeakRadarConfig();
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test('copyWith(graphScan: ...) changes equality', () {
      const base = LeakRadarConfig();
      final changed = base.copyWith(graphScan: const GraphScan());
      expect(base == changed, isFalse);
    });
  });
}
