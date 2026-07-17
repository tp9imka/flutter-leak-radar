import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

import 'sample_test_support.dart';

/// The contract C1's triage router enforces: a built series whose unit differs
/// from `expectedUnit(column)` is silently degraded to not-measured. These
/// tests guard that every column any sampler emits reaches the timeline in its
/// expected unit, so a correctly-sampled column is never lost to a unit skew.
void main() {
  group('unit invariant', () {
    test('every emitted series carries expectedUnit(column)', () {
      // A snapshot measuring all 14 columns.
      final snapshot = NativeSampleSnapshot(
        tMicros: 1,
        values: {
          for (final column in TriageColumn.values)
            column: const SampleValue.measured(1),
        },
      );
      final timeline = (TimelineBuilder()..add(snapshot)).build();

      expect(timeline.columns, hasLength(TriageColumn.values.length));
      for (final entry in timeline.columns.entries) {
        expect(
          entry.value.unit,
          expectedUnit(entry.key),
          reason: '${entry.key} unit must equal expectedUnit',
        );
      }
    });

    test(
      'columns sampled off real fixtures reach the timeline in-unit',
      () async {
        final runner = ScriptedAdbRunner((args) {
          if (args.contains('meminfo')) {
            return ok(fixture('meminfo_android13_modern.txt'));
          }
          if (args.contains('gfxinfo')) return ok(fixture('gfxinfo_good.txt'));
          if (args.any((a) => a.endsWith('/status'))) {
            return ok(fixture('proc_status_good.txt'));
          }
          if (args.any((a) => a.endsWith('/comm'))) {
            return ok(fixture('thread_comm_good.txt'));
          }
          if (args.contains('ls')) return ok(fixture('fd_ls_good.txt'));
          return failed();
        });
        final composite = CompositeSampler([
          MeminfoSampler(runner),
          ProcStatusSampler(runner),
          FdSampler(runner),
          ThreadSampler(runner),
          GfxinfoSampler(runner),
        ]);

        final values = await composite.sample('com.example.app', 12345);
        final timeline =
            (TimelineBuilder()
                  ..add(NativeSampleSnapshot(tMicros: 1, values: values)))
                .build();

        // All 14 columns measured from the good fixtures, each in-unit.
        expect(timeline.columns, hasLength(14));
        for (final entry in timeline.columns.entries) {
          expect(entry.value.unit, expectedUnit(entry.key));
          expect(
            entry.value.samples.single.value,
            isNonNegative,
            reason: '${entry.key} sampled a value',
          );
        }
      },
    );
  });
}
