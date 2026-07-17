import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

import 'sample_test_support.dart';

void main() {
  group('GfxinfoSampler', () {
    test('parses GraphicBufferAllocator total KiB and buffer count', () async {
      final values = await GfxinfoSampler(
        FixedAdbRunner(ok(fixture('gfxinfo_good.txt'))),
      ).sample('com.example.app', 12345);

      expect(
        values[TriageColumn.gfxBufferKb],
        const SampleValue.measured(16712),
      );
      expect(
        values[TriageColumn.gfxBufferCount],
        const SampleValue.measured(3),
      );
    });

    test('absent GraphicBufferAllocator section is not-measured, never 0', () {
      final values = parseGfxinfo(fixture('gfxinfo_no_allocator.txt'));

      expect(values[TriageColumn.gfxBufferKb]?.measured, isFalse);
      expect(values[TriageColumn.gfxBufferKb]?.value, isNull);
      expect(values[TriageColumn.gfxBufferCount]?.measured, isFalse);
      expect(values[TriageColumn.gfxBufferCount]?.value, isNull);
    });

    test('a foreign-unit total refuses KiB while the count still measures', () {
      // Table present, total advertised in MB — KiB refuses, count holds.
      const output = '''
GraphicBufferAllocator buffers:
    Handle |   Size | Requestor
0x7b10 |  8100.00 KiB | app#0
0x7b20 |   512.00 KiB | app#1
Total allocated by GraphicBufferAllocator (estimated): 8.41 MB
''';
      final values = parseGfxinfo(output);

      expect(values[TriageColumn.gfxBufferKb]?.measured, isFalse);
      expect(
        values[TriageColumn.gfxBufferCount],
        const SampleValue.measured(2),
      );
    });

    test('tolerates a KiB-spelled total (same magnitude)', () {
      const output = '''
GraphicBufferAllocator buffers:
0x7b10 |  8100.00 KiB | app#0
Total allocated by GraphicBufferAllocator (estimated): 16712.00 KiB
''';
      final values = parseGfxinfo(output);
      expect(
        values[TriageColumn.gfxBufferKb],
        const SampleValue.measured(16712),
      );
    });

    test('a malformed total magnitude refuses KiB without crashing', () {
      for (final bad in ['1.2.3', '.', '9' * 400]) {
        final output =
            '''
GraphicBufferAllocator buffers:
0x7b10 |  8100.00 KiB | app#0
Total allocated by GraphicBufferAllocator (estimated): $bad KB
''';
        final values = parseGfxinfo(output);
        expect(
          values[TriageColumn.gfxBufferKb]?.measured,
          isFalse,
          reason: 'total "$bad"',
        );
        // The count is independent and still measures.
        expect(
          values[TriageColumn.gfxBufferCount],
          const SampleValue.measured(1),
          reason: 'total "$bad"',
        );
      }
    });

    test('non-zero adb exit reads both columns not-measured', () async {
      final values = await GfxinfoSampler(
        FixedAdbRunner(failed()),
      ).sample('com.example.app', 12345);

      expect(values.values.every((v) => !v.measured), isTrue);
    });
  });
}
