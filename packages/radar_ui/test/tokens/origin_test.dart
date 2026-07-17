// test/tokens/origin_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('OriginTokens colors', () {
    test('every origin maps to a distinct color', () {
      final colors = RadarOrigin.values.map(OriginTokens.color).toSet();
      expect(colors.length, RadarOrigin.values.length);
    });

    test('project is violet, never accent', () {
      final projectColor = OriginTokens.color(RadarOrigin.project);
      expect(projectColor, isNot(RadarColors.accent));
      expect(projectColor, RadarColors.violet);
    });

    test('unknown reads as the most muted, distinct tone', () {
      expect(OriginTokens.color(RadarOrigin.unknown), RadarColors.text15);
    });
  });

  group('OriginTokens labels', () {
    test('project labels as yours', () {
      expect(OriginTokens.label(RadarOrigin.project), 'yours');
    });

    test('dependency labels as dependency', () {
      expect(OriginTokens.label(RadarOrigin.dependency), 'dependency');
    });

    test('framework labels as framework', () {
      expect(OriginTokens.label(RadarOrigin.framework), 'framework');
    });

    test('sdk labels as sdk', () {
      expect(OriginTokens.label(RadarOrigin.sdk), 'sdk');
    });

    test('unknown labels as an em dash', () {
      expect(OriginTokens.label(RadarOrigin.unknown), '—');
    });
  });
}
