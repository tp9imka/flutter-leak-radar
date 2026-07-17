import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

import 'sample_test_support.dart';

void main() {
  group('FdSampler', () {
    test('classifies sync_file / dmabuf / ashmem targets and totals', () async {
      final values = await FdSampler(
        FixedAdbRunner(ok(fixture('fd_ls_good.txt'))),
      ).sample('com.example.app', 12345);

      expect(values[TriageColumn.fdTotal], const SampleValue.measured(12));
      expect(values[TriageColumn.fdSyncFile], const SampleValue.measured(3));
      expect(values[TriageColumn.fdDmabuf], const SampleValue.measured(2));
      expect(values[TriageColumn.fdAshmem], const SampleValue.measured(2));
    });

    test('a class with no matching fd is a measured 0, not not-measured', () {
      final values = parseFdList(fixture('fd_ls_no_graphics.txt'));

      expect(values[TriageColumn.fdTotal], const SampleValue.measured(5));
      // Saw the table, none matched — a genuine measured zero.
      expect(values[TriageColumn.fdSyncFile], const SampleValue.measured(0));
      expect(values[TriageColumn.fdDmabuf], const SampleValue.measured(0));
      expect(values[TriageColumn.fdAshmem], const SampleValue.measured(0));
    });

    test('vendor GPU/memfd fds count in the total, not misclassified', () {
      // Adreno kgsl + Android-11 memfd: real graphics/shared-memory fds that
      // are not named dmabuf/ashmem. They must swell fdTotal (the safety-net)
      // without being mislabelled into a class.
      const output = '''
total 0
lrwx------ 1 u0_a1 u0_a1 64 2026-07-17 09:14 0 -> /dev/null
lrwx------ 1 u0_a1 u0_a1 64 2026-07-17 09:14 3 -> /dev/kgsl-3d0
lrwx------ 1 u0_a1 u0_a1 64 2026-07-17 09:14 4 -> /memfd:jit-cache (deleted)
''';
      final values = parseFdList(output);

      expect(values[TriageColumn.fdTotal], const SampleValue.measured(3));
      expect(values[TriageColumn.fdDmabuf], const SampleValue.measured(0));
      expect(values[TriageColumn.fdAshmem], const SampleValue.measured(0));
    });

    test('malformed output (No such file) is not-measured, never 0', () {
      final values = parseFdList(fixture('fd_ls_malformed.txt'));

      for (final column in const {
        TriageColumn.fdTotal,
        TriageColumn.fdSyncFile,
        TriageColumn.fdDmabuf,
        TriageColumn.fdAshmem,
      }) {
        expect(values[column]?.measured, isFalse, reason: '$column');
        expect(values[column]?.value, isNull, reason: '$column');
      }
    });

    test('non-zero adb exit reads all columns not-measured', () async {
      final values = await FdSampler(
        FixedAdbRunner(failed()),
      ).sample('com.example.app', 12345);

      expect(values.values.every((v) => !v.measured), isTrue);
    });
  });
}
