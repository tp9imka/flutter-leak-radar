// test/config/suspect_set_test.dart
import 'package:flutter_leak_radar/src/config/leak_rule.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeakRule.matches (glob)', () {
    test('suffix *Bloc', () {
      const r = LeakRule.growth('*Bloc');
      expect(r.matches('HomeBloc'), true);
      expect(r.matches('BlocBase'), false);
    });
    test('prefix State*', () {
      const r = LeakRule.growth('State*');
      expect(r.matches('StateController'), true);
      expect(r.matches('AppState'), false);
    });
    test('contains *Stream*', () {
      const r = LeakRule.growth('*Stream*');
      expect(r.matches('_StreamSubscriptionImpl'), true);
    });
    test('exact', () {
      const r = LeakRule.growth('Timer');
      expect(r.matches('Timer'), true);
      expect(r.matches('_Timer'), false);
    });
  });

  group('SuspectSet', () {
    test('ruleFor returns first matching default', () {
      final s = SuspectSet.defaults();
      expect(s.ruleFor('LoginBloc')?.mode, LeakDetectionMode.growth);
      expect(s.ruleFor('PlainModel'), isNull);
    });

    test('merge precedence: ignore beats default and override', () {
      final s = SuspectSet.defaults().merge([
        const LeakRule.maxLive('*Bloc', 1),
        const LeakRule.ignore('SpecialBloc'),
      ]);
      expect(s.ruleFor('SpecialBloc')?.mode, LeakDetectionMode.ignore);
      expect(s.ruleFor('OtherBloc')?.mode, LeakDetectionMode.maxLive);
      expect(s.ruleFor('OtherBloc')?.maxLive, 1);
    });

    test('defaults() *Timer matches the VM private _Timer impl class', () {
      final s = SuspectSet.defaults();
      expect(s.ruleFor('_Timer')?.mode, LeakDetectionMode.growth);
      expect(s.ruleFor('Timer')?.mode, LeakDetectionMode.growth);
    });
  });
}
