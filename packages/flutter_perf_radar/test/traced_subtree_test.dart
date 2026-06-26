import 'package:flutter/material.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_trace/radar_trace.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A parent widget that triggers rebuilds of its child via a counter in state.
class _RebuildTrigger extends StatefulWidget {
  const _RebuildTrigger({super.key, required this.child});

  final Widget child;

  @override
  State<_RebuildTrigger> createState() => _RebuildTriggerState();
}

class _RebuildTriggerState extends State<_RebuildTrigger> {
  int _tick = 0;

  void tick() => setState(() => _tick++);

  @override
  Widget build(BuildContext context) {
    // Suppress unused warning: _tick is the rebuild driver.
    return KeyedSubtree(key: ValueKey(_tick), child: widget.child);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  tearDown(() async {
    await PerfRadar.dispose();
  });

  group('TracedSubtree', () {
    testWidgets('counts N rebuilds when the widget rebuilds N times', (
      tester,
    ) async {
      // Arrange
      await PerfRadar.init(
        const PerfRadarConfig(enabled: true, stallThresholdMicros: 250000),
      );

      final triggerKey = GlobalKey<_RebuildTriggerState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _RebuildTrigger(
            key: triggerKey,
            child: const TracedSubtree(
              label: 'my_label',
              child: SizedBox.shrink(),
            ),
          ),
        ),
      );

      // Initial pump = build 1.
      // Trigger 4 more rebuilds → total 5.
      for (var i = 0; i < 4; i++) {
        triggerKey.currentState!.tick();
        await tester.pump();
      }

      // Assert — capture snapshot before dispose.
      final snap = PerfRadar.snapshot();
      // Dispose before the widget tree is torn down so the stall-watchdog
      // timer does not outlive the test.
      await PerfRadar.dispose();

      final entry = snap.stats.values.firstWhere(
        (s) => s.key.name == 'rebuild:my_label',
        orElse: () => throw StateError('rebuild:my_label not in snapshot'),
      );
      expect(entry.count, equals(5));
    });

    testWidgets('is a transparent pass-through — renders child unchanged', (
      tester,
    ) async {
      // Arrange — PerfRadar not initialised; widget must still render child.
      await tester.pumpWidget(
        const MaterialApp(
          home: TracedSubtree(
            label: 'pass_through',
            child: Text('hello radar'),
          ),
        ),
      );

      // Assert
      expect(find.text('hello radar'), findsOneWidget);
    });

    testWidgets('is a no-op when PerfRadar is disabled — child still renders', (
      tester,
    ) async {
      // Arrange: init with enabled:false → no engine, trace is a pass-through.
      await PerfRadar.init(
        const PerfRadarConfig(enabled: false, stallThresholdMicros: 250000),
      );

      final triggerKey = GlobalKey<_RebuildTriggerState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _RebuildTrigger(
            key: triggerKey,
            child: const TracedSubtree(
              label: 'disabled_label',
              child: Text('still visible'),
            ),
          ),
        ),
      );

      triggerKey.currentState!.tick();
      await tester.pump();

      // Assert: child renders, snapshot has no rebuild entry.
      expect(find.text('still visible'), findsOneWidget);
      final snap = PerfRadar.snapshot();
      final hasKey = snap.stats.keys.any(
        (k) => k.name == 'rebuild:disabled_label',
      );
      expect(hasKey, isFalse);
    });
  });

  group('RebuildCountsPanel', () {
    testWidgets('shows nothing when snapshot has no rebuild: keys', (
      tester,
    ) async {
      // Arrange: empty snapshot → no rebuild section.
      final snapshot = TraceSnapshot(stats: const {}, totalDropCount: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF0a0d0e),
            body: RebuildCountsPanel(snapshot: snapshot),
          ),
        ),
      );

      // No rebuild rows rendered.
      expect(find.byType(RebuildCountsPanel), findsOneWidget);
      expect(find.text('Rebuilds'), findsNothing);
    });

    testWidgets(
      'shows rebuild label and count when rebuild: keys are present',
      (tester) async {
        // Arrange: manually construct a snapshot with a rebuild key.
        await PerfRadar.init(
          const PerfRadarConfig(enabled: true, stallThresholdMicros: 250000),
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: TracedSubtree(
              label: 'counter_widget',
              child: SizedBox.shrink(),
            ),
          ),
        );
        await tester.pump();

        final snap = PerfRadar.snapshot();
        // Dispose before the widget tree is torn down to cancel the watchdog.
        await PerfRadar.dispose();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: const Color(0xFF0a0d0e),
              body: RebuildCountsPanel(snapshot: snap),
            ),
          ),
        );

        // The panel must show the label (without the 'rebuild:' prefix).
        expect(find.textContaining('counter_widget'), findsOneWidget);
      },
    );
  });
}
