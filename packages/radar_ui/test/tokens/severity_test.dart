// test/tokens/severity_test.dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarSeverity colors', () {
    test('critical maps to #ff5d6c', () {
      expect(
        RadarSeverity.critical.color,
        const Color(0xFFff5d6c),
      );
    });

    test('warning maps to #f5b54a', () {
      expect(
        RadarSeverity.warning.color,
        const Color(0xFFf5b54a),
      );
    });

    test('info maps to #5ad1e6', () {
      expect(
        RadarSeverity.info.color,
        const Color(0xFF5ad1e6),
      );
    });

    test('healthy maps to #2fe39b (accent green)', () {
      expect(
        RadarSeverity.healthy.color,
        const Color(0xFF2fe39b),
      );
    });

    test('SeverityTokens critical tagBg has alpha 0.12', () {
      final t = RadarSeverity.critical.tokens;
      final alpha = (t.tagBg.a * 255.0).round().clamp(0, 255);
      expect(alpha, closeTo(0.12 * 255, 2));
    });
  });
}
