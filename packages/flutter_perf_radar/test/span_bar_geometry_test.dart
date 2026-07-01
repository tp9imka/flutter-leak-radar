import 'package:flutter_perf_radar/src/ui/widgets/traces_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('spanBarGeometry', () {
    test('places a normal bar within the track', () {
      final geo = spanBarGeometry(
        offsetFraction: 0.25,
        widthFraction: 0.5,
        totalWidth: 400,
      );
      expect(geo.left, 100);
      expect(geo.width, 200);
      expect(geo.left + geo.width, lessThanOrEqualTo(400));
    });

    test('a span at the right edge does not throw and stays in bounds', () {
      // This is the "Invalid argument(s): 6.0" crash case: remaining space
      // (totalWidth - left) drops below the 6px minimum bar width.
      final geo = spanBarGeometry(
        offsetFraction: 0.999,
        widthFraction: 0.0001,
        totalWidth: 400,
      );
      expect(geo.width, greaterThanOrEqualTo(6.0));
      expect(geo.left, greaterThanOrEqualTo(0.0));
      expect(geo.left + geo.width, lessThanOrEqualTo(400.0 + 1e-9));
    });

    test('a span at fraction 1.0 shifts left to remain visible', () {
      final geo = spanBarGeometry(
        offsetFraction: 1.0,
        widthFraction: 0.0,
        totalWidth: 400,
      );
      expect(geo.width, 6.0);
      expect(geo.left, 394.0);
    });

    test('non-finite inputs degrade to safe values', () {
      expect(
        spanBarGeometry(
          offsetFraction: 0.5,
          widthFraction: 0.5,
          totalWidth: double.nan,
        ),
        (left: 0.0, width: 0.0),
      );
      final infWidth = spanBarGeometry(
        offsetFraction: double.infinity,
        widthFraction: double.infinity,
        totalWidth: 400,
      );
      expect(infWidth.width, 6.0);
      expect(infWidth.left, inInclusiveRange(0.0, 400.0));
    });

    test('a width fraction over 1 is capped to the track', () {
      final geo = spanBarGeometry(
        offsetFraction: 0.0,
        widthFraction: 2.0,
        totalWidth: 400,
      );
      expect(geo.width, 400);
      expect(geo.left, 0);
    });

    test('a track narrower than the minimum bar never inverts the range', () {
      final geo = spanBarGeometry(
        offsetFraction: 0.9,
        widthFraction: 0.9,
        totalWidth: 4,
      );
      expect(geo.width, lessThanOrEqualTo(4.0));
      expect(geo.left, inInclusiveRange(0.0, 4.0));
      expect(geo.left + geo.width, lessThanOrEqualTo(4.0 + 1e-9));
    });
  });
}
