import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

import 'sample_test_support.dart';

void main() {
  group('ProcStatusSampler', () {
    test('parses VmRSS, RssAnon (KiB) and Threads exactly', () async {
      final values = await ProcStatusSampler(
        FixedAdbRunner(ok(fixture('proc_status_good.txt'))),
      ).sample('com.example.app', 12345);

      expect(values[TriageColumn.vmRssKb], const SampleValue.measured(312044));
      expect(
        values[TriageColumn.rssAnonKb],
        const SampleValue.measured(128360),
      );
      expect(values[TriageColumn.threads], const SampleValue.measured(87));
    });

    test('issues a read-only cat of /proc/<pid>/status', () async {
      final runner = FixedAdbRunner(ok(fixture('proc_status_good.txt')));
      await ProcStatusSampler(runner).sample('com.example.app', 12345);

      expect(runner.calls.single, ['shell', 'cat', '/proc/12345/status']);
    });

    test('malformed output (No such file) is not-measured, never 0', () {
      final values = parseProcStatus(fixture('proc_status_malformed.txt'));

      for (final column in const {
        TriageColumn.vmRssKb,
        TriageColumn.rssAnonKb,
        TriageColumn.threads,
      }) {
        expect(values[column]?.measured, isFalse, reason: '$column');
        expect(values[column]?.value, isNull, reason: '$column');
      }
    });

    test(
      'a memory line without the kB unit refuses rather than mis-scaling',
      () {
        // Hypothetical OEM kernel reporting bytes: honest refuse, not a value.
        final values = parseProcStatus('VmRSS:\t 319533056 B\nThreads:\t42\n');

        expect(values[TriageColumn.vmRssKb]?.measured, isFalse);
        // Threads has no unit and still parses.
        expect(values[TriageColumn.threads], const SampleValue.measured(42));
      },
    );

    test('non-zero adb exit reads all columns not-measured', () async {
      final values = await ProcStatusSampler(
        FixedAdbRunner(failed()),
      ).sample('com.example.app', 12345);

      expect(values.values.every((v) => !v.measured), isTrue);
    });
  });
}
