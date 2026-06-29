// example/lib/showcase/jank_demo_screen.dart
//
// Perf · Frames / Jank demo.
//
// Produces real over-budget frames by blocking the raster thread with heavy
// synchronous work during build. The Frames tab in RadarScreen records these
// as jank frames (duration > jankThresholdMicros, default 16.67ms).
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:radar/radar.dart';

/// Triggers real jank by computing an expensive sieve inside [build],
/// then measures the resulting frame stats via [PerfRadar.frameStats].
class JankDemoScreen extends StatefulWidget {
  const JankDemoScreen({super.key});

  @override
  State<JankDemoScreen> createState() => _JankDemoScreenState();
}

class _JankDemoScreenState extends State<JankDemoScreen> {
  bool _jankEnabled = false;
  FrameStatsSnapshot _stats = const FrameStatsSnapshot(
    frameCount: 0,
    jankCount: 0,
  );
  int _framesBefore = 0;

  void _startJank() {
    _framesBefore = PerfRadar.frameStats.frameCount;
    setState(() => _jankEnabled = true);
  }

  void _stopJank() {
    final after = PerfRadar.frameStats;
    developer.log(
      'frames recorded: total=${after.frameCount} jank=${after.jankCount}',
      name: 'jank-demo',
    );
    setState(() {
      _jankEnabled = false;
      _stats = after;
    });
  }

  /// Burns ~20–40ms of CPU — reliably over-budget at 60 fps (16.67ms budget).
  void _heavyWork() {
    final limit = 80000 + Random().nextInt(20000);
    final isPrime = List<bool>.filled(limit + 1, true);
    isPrime[0] = isPrime[1] = false;
    for (var p = 2; p * p <= limit; p++) {
      if (isPrime[p]) {
        for (var i = p * p; i <= limit; i += p) {
          isPrime[i] = false;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Perform heavy work DURING BUILD to block the UI thread and produce a
    // genuinely over-budget frame. Only active while the jank toggle is on.
    if (_jankEnabled) _heavyWork();

    final jankNew = _stats.jankCount;
    final framesNew = _stats.frameCount - _framesBefore;

    return Scaffold(
      appBar: AppBar(title: const Text('Perf · Jank Demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Runs a prime sieve (~20–40ms) inside build() to produce '
              'real over-budget frames.\n\n'
              'Start → triggers repeated rebuild + heavy work → jank frames.\n'
              'Stop → freezes heavy work and shows captured stats.\n\n'
              'Open Radar → Performance → Frames to see the jank count.',
            ),
            const SizedBox(height: 24),
            _StatsRow(label: 'Frame count (session)', value: framesNew),
            _StatsRow(label: 'Jank count (session)', value: jankNew),
            const Spacer(),
            if (_jankEnabled)
              FilledButton.icon(
                key: const Key('stop_jank'),
                onPressed: _stopJank,
                icon: const Icon(Icons.stop),
                label: const Text('Stop jank'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              )
            else
              FilledButton.icon(
                key: const Key('start_jank'),
                onPressed: _startJank,
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('Start jank (blocks UI thread)'),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const RadarScreen()),
              ),
              child: const Text('Open Radar Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$value',
            style: TextStyle(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
