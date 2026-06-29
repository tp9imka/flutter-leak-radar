import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarTypography tabular figures', () {
    test('monoBody has tabular figures', () {
      final style = RadarTypography.monoBody;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('monoNumber has tabular figures', () {
      final style = RadarTypography.monoNumber;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('monoTag has tabular figures', () {
      final style = RadarTypography.monoTag;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });
}
