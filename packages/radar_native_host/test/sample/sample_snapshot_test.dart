import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

import 'sample_test_support.dart';

void main() {
  group('SampleValue', () {
    test('measured/unmeasured round-trip through JSON', () {
      const measured = SampleValue.measured(42);
      final measuredBack = SampleValue.fromJson(measured.toJson());
      expect(measuredBack, measured);
      expect(measuredBack.value, 42);
      expect(measuredBack.error, isNull);

      const missed = SampleValue.unmeasured('dead pid');
      final missedBack = SampleValue.fromJson(missed.toJson());
      expect(missedBack, missed);
      expect(missedBack.value, isNull);
      expect(missedBack.measured, isFalse);
      expect(missedBack.error, 'dead pid');
    });

    test('a measured 0 is distinct from an unmeasured reading', () {
      const zero = SampleValue.measured(0);
      const missed = SampleValue.unmeasured('miss');
      expect(zero == missed, isFalse);
      expect(zero.measured, isTrue);
      expect(zero.value, 0);
    });
  });

  group('NativeSampleSnapshot', () {
    test('round-trips through JSON keyed by column name', () {
      const snapshot = NativeSampleSnapshot(
        tMicros: 1000,
        values: {
          TriageColumn.nativePssKb: SampleValue.measured(74310),
          TriageColumn.gfxBufferKb: SampleValue.unmeasured('no section'),
        },
      );
      final back = NativeSampleSnapshot.fromJson(snapshot.toJson());
      expect(back.tMicros, 1000);
      expect(
        back.values[TriageColumn.nativePssKb],
        snapshot.values[TriageColumn.nativePssKb],
      );
      expect(
        back.values[TriageColumn.gfxBufferKb],
        snapshot.values[TriageColumn.gfxBufferKb],
      );
    });

    test('rejects an unknown column name', () {
      expect(
        () => NativeSampleSnapshot.fromJson({
          'tMicros': 1,
          'values': {
            'notAColumn': {'measured': true, 'value': 1},
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('CompositeSampler', () {
    ScriptedAdbRunner deviceRunner({required String statusFixture}) =>
        ScriptedAdbRunner((args) {
          if (args.contains('meminfo')) {
            return ok(fixture('meminfo_android13_modern.txt'));
          }
          if (args.contains('gfxinfo')) return ok(fixture('gfxinfo_good.txt'));
          if (args.any((a) => a.endsWith('/status'))) return ok(statusFixture);
          if (args.any((a) => a.endsWith('/comm'))) {
            return ok(fixture('thread_comm_good.txt'));
          }
          if (args.contains('ls')) return ok(fixture('fd_ls_good.txt'));
          return failed();
        });

    test('merges every sampler into one reading map', () async {
      final runner = deviceRunner(
        statusFixture: fixture('proc_status_good.txt'),
      );
      final composite = CompositeSampler([
        MeminfoSampler(runner),
        ProcStatusSampler(runner),
        FdSampler(runner),
        ThreadSampler(runner),
        GfxinfoSampler(runner),
      ]);

      final values = await composite.sample('com.example.app', 12345);

      expect(
        values[TriageColumn.nativePssKb],
        const SampleValue.measured(74310),
      );
      expect(
        values[TriageColumn.rssAnonKb],
        const SampleValue.measured(128360),
      );
      expect(values[TriageColumn.fdDmabuf], const SampleValue.measured(2));
      expect(
        values[TriageColumn.gfxBufferCount],
        const SampleValue.measured(3),
      );
      expect(composite.columns, hasLength(14));
    });

    test('first measured sampler wins a shared column (threads)', () async {
      final runner = deviceRunner(
        statusFixture: fixture('proc_status_good.txt'),
      );

      final statusFirst = await CompositeSampler([
        ProcStatusSampler(runner),
        ThreadSampler(runner),
      ]).sample('com.example.app', 12345);
      // /proc/status Threads (87) wins over task/*/comm count (16).
      expect(statusFirst[TriageColumn.threads], const SampleValue.measured(87));

      final threadFirst = await CompositeSampler([
        ThreadSampler(runner),
        ProcStatusSampler(runner),
      ]).sample('com.example.app', 12345);
      expect(threadFirst[TriageColumn.threads], const SampleValue.measured(16));
    });

    test(
      'an unmeasured column is upgraded by a later measured sampler',
      () async {
        final runner = deviceRunner(
          statusFixture: fixture('proc_status_malformed.txt'),
        );
        // ProcStatus fails to measure threads; ThreadSampler fills it in.
        final values = await CompositeSampler([
          ProcStatusSampler(runner),
          ThreadSampler(runner),
        ]).sample('com.example.app', 12345);

        expect(values[TriageColumn.threads], const SampleValue.measured(16));
        expect(values[TriageColumn.vmRssKb]?.measured, isFalse);
      },
    );

    test(
      'a throwing sampler loses only its own columns, not the tick',
      () async {
        final runner = FixedAdbRunner(ok(fixture('proc_status_good.txt')));
        final composite = CompositeSampler([
          _ThrowingSampler(const {
            TriageColumn.gfxBufferKb,
            TriageColumn.gfxBufferCount,
          }),
          ProcStatusSampler(runner),
        ]);

        final values = await composite.sample('com.example.app', 12345);

        // ProcStatus readings survive the earlier sampler's throw.
        expect(
          values[TriageColumn.vmRssKb],
          const SampleValue.measured(312044),
        );
        expect(values[TriageColumn.threads], const SampleValue.measured(87));
        // The throwing sampler's columns are present but not-measured (never
        // silently dropped, never zero).
        expect(values[TriageColumn.gfxBufferKb]?.measured, isFalse);
        expect(values[TriageColumn.gfxBufferKb]?.value, isNull);
        expect(
          values[TriageColumn.gfxBufferKb]?.error,
          contains('sampler threw'),
        );
      },
    );
  });

  group('TimelineBuilder', () {
    test('inserts a gap over an unmeasured stretch with the first error', () {
      final builder = TimelineBuilder()
        ..add(
          const NativeSampleSnapshot(
            tMicros: 100,
            values: {TriageColumn.nativePssKb: SampleValue.measured(74310)},
          ),
        )
        ..add(
          const NativeSampleSnapshot(
            tMicros: 200,
            values: {TriageColumn.nativePssKb: SampleValue.unmeasured('e1')},
          ),
        )
        ..add(
          const NativeSampleSnapshot(
            tMicros: 300,
            values: {TriageColumn.nativePssKb: SampleValue.unmeasured('e2')},
          ),
        )
        ..add(
          const NativeSampleSnapshot(
            tMicros: 400,
            values: {TriageColumn.nativePssKb: SampleValue.measured(80000)},
          ),
        );

      final series = builder.build().columns[TriageColumn.nativePssKb]!;

      expect(series.unit, 'kb');
      expect(series.samples, const [
        MetricSample(tMicros: 100, value: 74310),
        MetricSample(tMicros: 400, value: 80000),
      ]);
      expect(series.gaps, const [
        SeriesGap(startMicros: 200, endMicros: 300, reason: 'e1'),
      ]);
    });

    test('a column unmeasured in every snapshot is a gap-only series', () {
      final builder = TimelineBuilder()
        ..add(
          const NativeSampleSnapshot(
            tMicros: 10,
            values: {
              TriageColumn.gfxBufferKb: SampleValue.unmeasured('absent'),
            },
          ),
        )
        ..add(
          const NativeSampleSnapshot(
            tMicros: 20,
            values: {
              TriageColumn.gfxBufferKb: SampleValue.unmeasured('absent'),
            },
          ),
        );

      final series = builder.build().columns[TriageColumn.gfxBufferKb]!;
      expect(series.samples, isEmpty);
      expect(series.gaps, const [
        SeriesGap(startMicros: 10, endMicros: 20, reason: 'absent'),
      ]);
    });

    test('a column attempted in no snapshot is omitted entirely', () {
      final timeline =
          (TimelineBuilder()..add(
                const NativeSampleSnapshot(
                  tMicros: 1,
                  values: {TriageColumn.threads: SampleValue.measured(9)},
                ),
              ))
              .build();
      expect(timeline.columns.containsKey(TriageColumn.threads), isTrue);
      expect(timeline.columns.containsKey(TriageColumn.gfxBufferKb), isFalse);
    });

    test('sorts out-of-order snapshots and stamps marks from the clock', () {
      var clock = 5000;
      final builder = TimelineBuilder(nowMicros: () => clock += 1000)
        ..add(
          const NativeSampleSnapshot(
            tMicros: 300,
            values: {TriageColumn.threads: SampleValue.measured(3)},
          ),
        )
        ..add(
          const NativeSampleSnapshot(
            tMicros: 100,
            values: {TriageColumn.threads: SampleValue.measured(1)},
          ),
        )
        ..addMark('reconnect');

      final timeline = builder.build();
      expect(
        timeline.columns[TriageColumn.threads]!.samples.map((s) => s.tMicros),
        [100, 300],
      );
      expect(timeline.marks.single.label, 'reconnect');
      expect(timeline.marks.single.tMicros, 6000);
    });
  });
}

/// A [NativeSampler] that always throws from [sample] — models a mid-sweep
/// parse crash or a `ProcessException` from a failed `adb` launch.
class _ThrowingSampler implements NativeSampler {
  const _ThrowingSampler(this.columns);

  @override
  final Set<TriageColumn> columns;

  @override
  Future<Map<TriageColumn, SampleValue>> sample(String package, int pid) =>
      throw StateError('boom');
}
