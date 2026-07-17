import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

import 'sample_test_support.dart';

void main() {
  group('ThreadSampler', () {
    test('counts live threads exactly', () async {
      final values = await ThreadSampler(
        FixedAdbRunner(ok(fixture('thread_comm_good.txt'))),
      ).sample('com.example.app', 12345);

      expect(values[TriageColumn.threads], const SampleValue.measured(16));
    });

    test('groups name prefixes (digit runs collapsed), top-n by count', () {
      final breakdown = parseThreadComm(fixture('thread_comm_good.txt'));

      expect(breakdown, isNotNull);
      expect(breakdown!.total, 16);
      // Binder pool (idx 7) and worker pool (idx 13) both 3 — tie broken by
      // first appearance, so Binder precedes pool; hwuiTask (2) follows.
      expect(breakdown.topThreadNamePrefixes(3), {
        'Binder:#_#': 3,
        'pool-#-thread-#': 3,
        'hwuiTask#': 2,
      });
    });

    test('topThreadNamePrefixes(0) is empty', () {
      final breakdown = parseThreadComm(fixture('thread_comm_good.txt'));
      expect(breakdown!.topThreadNamePrefixes(0), isEmpty);
    });

    test('malformed output (No such file) is not-measured, never 0', () async {
      final values = await ThreadSampler(
        FixedAdbRunner(ok(fixture('thread_comm_malformed.txt'))),
      ).sample('com.example.app', 12345);

      expect(values[TriageColumn.threads]?.measured, isFalse);
      expect(values[TriageColumn.threads]?.value, isNull);
      expect(parseThreadComm(fixture('thread_comm_malformed.txt')), isNull);
    });

    test('non-zero adb exit reads the thread column not-measured', () async {
      final values = await ThreadSampler(
        FixedAdbRunner(failed()),
      ).sample('com.example.app', 12345);

      expect(values[TriageColumn.threads]?.measured, isFalse);
    });
  });
}
