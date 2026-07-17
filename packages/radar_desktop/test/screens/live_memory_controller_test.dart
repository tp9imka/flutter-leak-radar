import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/screens/live_memory_controller.dart';
import 'package:radar_desktop/src/seams/desktop_memory_poll.dart';

/// A poll seam driven by the test: each call returns the next scripted
/// sample, or throws the next scripted error.
class _ScriptedPoll {
  _ScriptedPoll(this._steps);

  final List<MemorySample?> _steps;
  int _i = 0;

  Future<MemorySample> call() async {
    final step = _steps[_i++];
    if (step == null) {
      throw const MemoryPollUnavailableException('scripted failure');
    }
    return step;
  }
}

void main() {
  group('LiveMemoryController', () {
    test('accumulates heap and external as two separate series', () async {
      final poll = _ScriptedPoll([
        (heapUsage: 100, externalUsage: 10),
        (heapUsage: 200, externalUsage: 20),
        (heapUsage: 300, externalUsage: 30),
      ]);
      var clock = 1000;
      final controller = LiveMemoryController(
        poll: poll.call,
        clock: () => clock,
      );
      addTearDown(controller.dispose);

      await controller.pollOnce();
      clock += 1000;
      await controller.pollOnce();
      clock += 1000;
      await controller.pollOnce();

      final heap = controller.heapSeries;
      final external = controller.externalSeries;

      // Two distinct series — never merged into one line.
      expect(heap.name, isNot(external.name));
      expect(heap.samples.map((s) => s.value), [100, 200, 300]);
      expect(external.samples.map((s) => s.value), [10, 20, 30]);
      expect(heap.gaps, isEmpty);
      expect(external.gaps, isEmpty);
      expect(controller.sampleCount, 3);
    });

    test('records a gap on RPC failure, in both series', () async {
      final poll = _ScriptedPoll([
        (heapUsage: 100, externalUsage: 10),
        null, // throw
        (heapUsage: 300, externalUsage: 30),
      ]);
      var clock = 1000;
      final controller = LiveMemoryController(
        poll: poll.call,
        clock: () => clock,
      );
      addTearDown(controller.dispose);

      await controller.pollOnce(); // t=1000 ok
      clock += 1000;
      await controller.pollOnce(); // t=2000 throws → no sample, gap opens
      clock += 1000;
      await controller.pollOnce(); // t=3000 ok → gap [1000,3000] closes

      final heap = controller.heapSeries;
      final external = controller.externalSeries;

      // The failed poll adds no sample — the honest count is 2, not 3.
      expect(heap.samples.map((s) => s.value), [100, 300]);
      expect(external.samples.map((s) => s.value), [10, 30]);

      // Both series carry exactly one gap spanning the failed interval.
      expect(heap.gaps, hasLength(1));
      expect(external.gaps, hasLength(1));
      expect(heap.gaps.single.startMicros, 1000);
      expect(heap.gaps.single.endMicros, 3000);
      expect(external.gaps.single.startMicros, 1000);
      expect(external.gaps.single.endMicros, 3000);
      // The gap permanently records why measurement stopped.
      expect(heap.gaps.single.reason, contains('scripted failure'));
    });

    test(
      'lastError reflects the current poll and clears on recovery',
      () async {
        final poll = _ScriptedPoll([
          null, // throw
          (heapUsage: 1, externalUsage: 1),
        ]);
        final controller = LiveMemoryController(
          poll: poll.call,
          clock: () => 0,
        );
        addTearDown(controller.dispose);

        await controller.pollOnce(); // fails
        expect(controller.lastError, isNotNull);
        await controller.pollOnce(); // recovers
        expect(controller.lastError, isNull);
      },
    );

    test('notifies listeners on every poll', () async {
      final poll = _ScriptedPoll([(heapUsage: 1, externalUsage: 1), null]);
      final controller = LiveMemoryController(poll: poll.call, clock: () => 0);
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.pollOnce();
      await controller.pollOnce();

      expect(notifications, 2);
    });

    test(
      'a failure with no prior sample still opens a gap at poll time',
      () async {
        final poll = _ScriptedPoll([
          null, // first poll throws
          (heapUsage: 500, externalUsage: 50),
        ]);
        var clock = 4000;
        final controller = LiveMemoryController(
          poll: poll.call,
          clock: () => clock,
        );
        addTearDown(controller.dispose);

        await controller.pollOnce(); // t=4000 throws, no prior sample
        clock += 1000;
        await controller.pollOnce(); // t=5000 ok → gap [4000,5000]

        expect(controller.heapSeries.samples.single.value, 500);
        expect(controller.heapSeries.gaps.single.startMicros, 4000);
        expect(controller.heapSeries.gaps.single.endMicros, 5000);
      },
    );
  });
}
