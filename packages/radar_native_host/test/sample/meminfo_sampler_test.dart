import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

import 'sample_test_support.dart';

void main() {
  group('MeminfoSampler', () {
    test(
      'parses the modern two-column (Pss/Rss) App Summary exactly',
      () async {
        final values = await MeminfoSampler(
          FixedAdbRunner(ok(fixture('meminfo_android13_modern.txt'))),
        ).sample('com.example.app', 12345);

        expect(
          values[TriageColumn.javaHeapKb],
          const SampleValue.measured(18452),
        );
        expect(
          values[TriageColumn.nativePssKb],
          const SampleValue.measured(74310),
        );
        expect(values[TriageColumn.codeKb], const SampleValue.measured(39820));
        expect(
          values[TriageColumn.graphicsKb],
          const SampleValue.measured(51216),
        );
        expect(
          values[TriageColumn.totalPssKb],
          const SampleValue.measured(312044),
        );
      },
    );

    test('parses the older single-column (Pss) App Summary exactly', () {
      final values = parseMeminfoAppSummary(
        fixture('meminfo_android10_legacy.txt'),
      );

      expect(values[TriageColumn.javaHeapKb], const SampleValue.measured(8452));
      expect(
        values[TriageColumn.nativePssKb],
        const SampleValue.measured(23096),
      );
      expect(values[TriageColumn.codeKb], const SampleValue.measured(9800));
      expect(
        values[TriageColumn.graphicsKb],
        const SampleValue.measured(12768),
      );
      // Legacy layout labels the aggregate 'TOTAL:' (no 'PSS').
      expect(
        values[TriageColumn.totalPssKb],
        const SampleValue.measured(78920),
      );
    });

    test('malformed output (no App Summary) is not-measured, never 0', () {
      final values = parseMeminfoAppSummary(fixture('meminfo_malformed.txt'));

      for (final column in const {
        TriageColumn.javaHeapKb,
        TriageColumn.nativePssKb,
        TriageColumn.codeKb,
        TriageColumn.graphicsKb,
        TriageColumn.totalPssKb,
      }) {
        expect(values[column]?.measured, isFalse, reason: '$column');
        expect(values[column]?.value, isNull, reason: '$column');
        expect(values[column]?.error, isNotNull, reason: '$column');
      }
    });

    test('Rss-first column order refuses all columns, never mislabels Rss', () {
      final values = parseMeminfoAppSummary(fixture('meminfo_rss_first.txt'));

      for (final column in const {
        TriageColumn.javaHeapKb,
        TriageColumn.nativePssKb,
        TriageColumn.codeKb,
        TriageColumn.graphicsKb,
        TriageColumn.totalPssKb,
      }) {
        expect(values[column]?.measured, isFalse, reason: '$column');
      }
      expect(
        values[TriageColumn.javaHeapKb]?.error,
        contains('unrecognized column order'),
      );
    });

    test('a tracked row with a blank Pss cell is not-measured, not the Rss '
        'value', () {
      final values = parseMeminfoAppSummary(fixture('meminfo_blank_pss.txt'));

      // Graphics Pss is blank; the lone 51216 is Rss and must not be read.
      expect(values[TriageColumn.graphicsKb]?.measured, isFalse);
      expect(values[TriageColumn.graphicsKb]?.value, isNull);
      expect(
        values[TriageColumn.graphicsKb]?.error,
        contains('Pss cell is blank'),
      );
      // The rows with a real Pss cell still measure.
      expect(
        values[TriageColumn.nativePssKb],
        const SampleValue.measured(74310),
      );
      expect(
        values[TriageColumn.totalPssKb],
        const SampleValue.measured(312044),
      );
    });

    test('non-zero adb exit reads all columns not-measured', () async {
      final values = await MeminfoSampler(
        FixedAdbRunner(failed(code: 1, stderr: 'device offline')),
      ).sample('com.example.app', 12345);

      expect(values.values.every((v) => !v.measured), isTrue);
      expect(values.values.every((v) => v.value == null), isTrue);
    });
  });
}
