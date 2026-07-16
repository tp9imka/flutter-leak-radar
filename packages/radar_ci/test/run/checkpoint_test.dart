import 'package:radar_ci/radar_ci.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import '../support/fake_vm_service.dart';

const int _second = 1000000;

/// Serves a fixed allocation profile per isolate, keyed by isolate id.
class _AllocFakeService extends FakeVmService {
  _AllocFakeService(this._membersByIsolate);

  final Map<String, List<ClassHeapStats>> _membersByIsolate;

  @override
  Future<VM> getVM() async => VM(
    isolates: [for (final id in _membersByIsolate.keys) IsolateRef(id: id)],
  );

  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? reset,
    bool? gc,
  }) async =>
      AllocationProfile()..members = _membersByIsolate[isolateId] ?? const [];
}

ClassHeapStats _stats(String name, {required int bytes, required int count}) =>
    ClassHeapStats(
      classRef: ClassRef(id: 'c/$name', name: name),
      bytesCurrent: bytes,
      instancesCurrent: count,
    );

void main() {
  group('checkpoint cadence', () {
    test('N interior checkpoints are evenly spaced, plus start and end', () {
      final plan = planCheckpoints(
        durationMicros: 180 * _second,
        interiorCount: 3,
        snapshotEvery: 0,
      );
      expect(plan.map((c) => c.label).toList(), [
        'start',
        'cp1',
        'cp2',
        'cp3',
        'end',
      ]);
      expect(plan.map((c) => c.offsetMicros).toList(), [
        0,
        45 * _second,
        90 * _second,
        135 * _second,
        180 * _second,
      ]);
    });

    test('interiorCount 0 yields just start and end', () {
      final plan = planCheckpoints(
        durationMicros: 60 * _second,
        interiorCount: 0,
        snapshotEvery: 1,
      );
      expect(plan.map((c) => c.label).toList(), ['start', 'end']);
    });

    test('snapshotEvery marks every Nth checkpoint by index', () {
      final plan = planCheckpoints(
        durationMicros: 120 * _second,
        interiorCount: 3,
        snapshotEvery: 2,
      );
      expect(plan.map((c) => c.takeSnapshot).toList(), [
        true, // index 0 (start)
        false, // 1
        true, // 2
        false, // 3
        true, // 4 (end)
      ]);
    });

    test('snapshotEvery 0 disables all snapshots', () {
      final plan = planCheckpoints(
        durationMicros: 120 * _second,
        interiorCount: 2,
        snapshotEvery: 0,
      );
      expect(plan.every((c) => !c.takeSnapshot), isTrue);
    });

    test('snapshotEvery 1 snapshots every checkpoint', () {
      final plan = planCheckpoints(
        durationMicros: 120 * _second,
        interiorCount: 3,
        snapshotEvery: 1,
      );
      expect(plan.every((c) => c.takeSnapshot), isTrue);
    });
  });

  group('sample cadence and the Mann-Kendall floor', () {
    test('offsets step by the interval from 0 through the duration', () {
      final offsets = sampleOffsetsMicros(
        durationMicros: 20 * _second,
        sampleIntervalMicros: 5 * _second,
      );
      expect(offsets, [
        0,
        5 * _second,
        10 * _second,
        15 * _second,
        20 * _second,
      ]);
    });

    test('the shipped defaults clear the >=12 post-settle floor', () {
      // 3m duration, 5s interval, 30s settle.
      final count = projectedPostSettleSampleCount(
        durationMicros: 180 * _second,
        sampleIntervalMicros: 5 * _second,
        settleMicros: 30 * _second,
      );
      expect(count, greaterThanOrEqualTo(kMannKendallSampleFloor));
      expect(count, 31);
      expect(
        isAssessableCadence(
          durationMicros: 180 * _second,
          sampleIntervalMicros: 5 * _second,
          settleMicros: 30 * _second,
        ),
        isTrue,
      );
    });

    test('the enforced 2m minimum still clears the floor', () {
      expect(
        projectedPostSettleSampleCount(
          durationMicros: 120 * _second,
          sampleIntervalMicros: 5 * _second,
          settleMicros: 30 * _second,
        ),
        greaterThanOrEqualTo(kMannKendallSampleFloor),
      );
    });

    test('a too-short or too-coarse cadence is flagged un-assessable', () {
      // 1m duration, 5s, 30s settle -> only 7 post-settle samples.
      expect(
        isAssessableCadence(
          durationMicros: 60 * _second,
          sampleIntervalMicros: 5 * _second,
          settleMicros: 30 * _second,
        ),
        isFalse,
      );
      // 3m but 20s interval -> 8 post-settle samples.
      expect(
        isAssessableCadence(
          durationMicros: 180 * _second,
          sampleIntervalMicros: 20 * _second,
          settleMicros: 30 * _second,
        ),
        isFalse,
      );
    });
  });

  group('captureAllocationTopN', () {
    test(
      'sums instances across isolates and ranks by retained bytes',
      () async {
        final service = _AllocFakeService({
          'isolates/1': [
            _stats('String', bytes: 5000, count: 100),
            _stats('List', bytes: 3000, count: 20),
            _stats('Uint8List', bytes: 9000, count: 5),
          ],
          'isolates/2': [
            _stats('String', bytes: 1000, count: 40),
            _stats('Timer', bytes: 200, count: 8),
          ],
        });

        final topN = await captureAllocationTopN(service, topN: 2);

        // Ranked by total bytes: Uint8List (9000), String (6000).
        expect(topN.keys.toList(), ['Uint8List', 'String']);
        expect(topN['Uint8List'], 5);
        expect(topN['String'], 140); // 100 + 40
      },
    );

    test('ignores classes with no name', () async {
      final service = _AllocFakeService({
        'isolates/1': [
          ClassHeapStats(bytesCurrent: 999, instancesCurrent: 3),
          _stats('String', bytes: 10, count: 1),
        ],
      });
      final topN = await captureAllocationTopN(service, topN: 5);
      expect(topN.keys, ['String']);
    });
  });
}
