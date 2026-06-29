// example/lib/showcase/stability_stall_screen.dart
//
// Stability · Stalls demo.
//
// Blocks the main isolate with a busy-wait loop longer than stallThresholdMicros
// (configured to 200ms in main.dart). The stall watchdog detects the gap
// between heartbeat ticks and records a stall event in the Stability recorder.
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:radar/radar.dart';

/// Triggers a real main-isolate stall that the watchdog detects.
///
/// The stall is a deliberate busy-wait — honesty over simulation.
class StabilityStallScreen extends StatefulWidget {
  const StabilityStallScreen({super.key});

  @override
  State<StabilityStallScreen> createState() => _StabilityStallScreenState();
}

class _StabilityStallScreenState extends State<StabilityStallScreen> {
  int _stallCount = 0;

  void _triggerStall() {
    // Busy-wait for 350ms — well over the 200ms stallThresholdMicros set in
    // main.dart. The watchdog's periodic heartbeat will miss a tick and record
    // a stall event in the Stability recorder.
    const stallMs = 350;
    final start = DateTime.now();
    while (DateTime.now().difference(start).inMilliseconds < stallMs) {
      // Spin.
    }

    final snap = PerfRadar.stabilitySnapshot;
    developer.log(
      'stall injected — stallCount=${snap.stallCount}',
      name: 'stall-demo',
    );
    if (mounted) setState(() => _stallCount = snap.stallCount);
  }

  @override
  Widget build(BuildContext context) {
    final snap = PerfRadar.stabilitySnapshot;

    return Scaffold(
      appBar: AppBar(title: const Text('Stability · Stalls Demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Each tap busy-waits for 350ms on the main isolate — longer '
              'than the configured stallThresholdMicros (200ms).\n\n'
              "The stall watchdog's heartbeat misses a tick and records a "
              'stall in the Stability recorder.\n\n'
              'Open Radar → Performance → Stability to watch the stall '
              'count rise.\n\n'
              'Note: the UI freezes briefly — that is intentional.',
            ),
            const SizedBox(height: 24),
            _StatsRow(
              label: 'Stalls captured (session)',
              value: snap.stallCount,
            ),
            const Spacer(),
            FilledButton.icon(
              key: const Key('trigger_stall'),
              onPressed: _triggerStall,
              icon: const Icon(Icons.timer_off),
              label: const Text('Block main isolate 350ms'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
              ),
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
            style: const TextStyle(
              fontFamily: 'monospace',
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
