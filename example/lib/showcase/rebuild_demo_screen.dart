// example/lib/showcase/rebuild_demo_screen.dart
//
// Perf · Rebuilds demo.
//
// A ticking counter drives repeated rebuilds inside TracedSubtree so the
// Rebuilds panel in RadarScreen shows a real, climbing count.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_radar/flutter_radar.dart';

/// Counter that ticks at 4 Hz inside a [TracedSubtree] labelled
/// `demo.counter`.  Every tick forces a rebuild, incrementing the
/// `rebuild:demo.counter` span count in the Rebuilds panel.
class RebuildDemoScreen extends StatefulWidget {
  const RebuildDemoScreen({super.key});

  @override
  State<RebuildDemoScreen> createState() => _RebuildDemoScreenState();
}

class _RebuildDemoScreenState extends State<RebuildDemoScreen> {
  int _count = 0;
  bool _running = false;
  Timer? _timer;

  void _start() {
    if (_running) return;
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() => _count++);
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _running = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perf · Rebuilds Demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'A timer ticks at 4 Hz inside a TracedSubtree(label: '
              "'demo.counter').\n\n"
              'Each tick triggers a rebuild — visible as a climbing count '
              'in Radar → Performance → Rebuilds.',
            ),
            const SizedBox(height: 32),
            TracedSubtree(
              label: 'demo.counter',
              child: _CounterDisplay(count: _count),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('start_rebuilds'),
                    onPressed: _running ? null : _start,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('stop_rebuilds'),
                    onPressed: _running ? _stop : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ),
              ],
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

class _CounterDisplay extends StatelessWidget {
  const _CounterDisplay({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
