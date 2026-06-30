// example/lib/showcase/perf_tracing_screen.dart
//
// Perf · Tracing demo.
//
// Runs Radar.trace (sync) and Radar.traceAsync (async) in a tight loop so
// the Spans tab of RadarScreen shows real p50/p95/p99 and counts.
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_radar/flutter_radar.dart';

/// Runs 50 iterations each of a sync and async span, then shows results.
class PerfTracingScreen extends StatefulWidget {
  const PerfTracingScreen({super.key});

  @override
  State<PerfTracingScreen> createState() => _PerfTracingScreenState();
}

class _PerfTracingScreenState extends State<PerfTracingScreen> {
  bool _running = false;
  int _syncRuns = 0;
  int _asyncRuns = 0;
  String _status = 'Tap "Run trace demo" to generate span data.';

  static const int _iterations = 50;
  static const String _syncName = 'demo.sync';
  static const String _asyncName = 'demo.async';
  static const String _category = 'demo';

  Future<void> _runDemo() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Running…';
      _syncRuns = 0;
      _asyncRuns = 0;
    });

    // Sync spans: prime-number sieve over a range that takes a few µs each.
    for (var i = 0; i < _iterations; i++) {
      Radar.trace(_syncName, () {
        _sieve(5000 + Random().nextInt(3000));
      }, category: _category);
      setState(() => _syncRuns = i + 1);
      // Yield to the event loop between batches to keep the UI responsive.
      if (i % 10 == 9) await Future<void>.delayed(Duration.zero);
    }

    // Async spans: each awaits a short realistic delay (1–5ms).
    for (var i = 0; i < _iterations; i++) {
      await Radar.traceAsync(_asyncName, () async {
        final ms = 1 + Random().nextInt(4);
        await Future<void>.delayed(Duration(milliseconds: ms));
      }, category: _category);
      setState(() => _asyncRuns = i + 1);
    }

    // Snapshot to confirm spans were recorded.
    // stats is Map<TraceKey, SpanKeyStatsSnapshot>; look up by name match
    // so we don't need to import TraceKey directly.
    final snap = PerfRadar.snapshot();
    final syncStats = snap.stats.entries
        .where((e) => e.key.name == _syncName)
        .map((e) => e.value)
        .firstOrNull;
    final asyncStats = snap.stats.entries
        .where((e) => e.key.name == _asyncName)
        .map((e) => e.value)
        .firstOrNull;
    final syncP50 = syncStats?.histogram.percentile(0.50);
    final syncP99 = syncStats?.histogram.percentile(0.99);
    final asyncP50 = asyncStats?.histogram.percentile(0.50);

    developer.log(
      'demo.sync: count=${syncStats?.count} '
      'p50=${syncP50?.round()}µs '
      'p99=${syncP99?.round()}µs',
      name: 'perf-tracing-demo',
    );
    developer.log(
      'demo.async: count=${asyncStats?.count} '
      'p50=${asyncP50?.round()}µs',
      name: 'perf-tracing-demo',
    );

    if (mounted) {
      setState(() {
        _running = false;
        _status =
            'Done!\n'
            'demo.sync  count=${syncStats?.count ?? 0}  '
            'p50=${syncP50?.round() ?? 0}µs  '
            'p99=${syncP99?.round() ?? 0}µs\n'
            'demo.async count=${asyncStats?.count ?? 0}  '
            'p50=${asyncP50?.round() ?? 0}µs\n\n'
            'Open Radar → Performance → Spans to see the full histogram.';
      });
    }
  }

  /// Burns a small, variable amount of CPU to produce realistic span durations.
  void _sieve(int limit) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Perf · Tracing Demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Calls Radar.trace('demo.sync') and "
              "Radar.traceAsync('demo.async') 50 times each.\n\n"
              'After running, open Radar → Performance → Spans to see '
              'p50 / p95 / p99 and call counts.',
            ),
            const SizedBox(height: 24),
            if (_running) ...[
              LinearProgressIndicator(
                value: (_syncRuns + _asyncRuns) / (_iterations * 2),
              ),
              const SizedBox(height: 8),
              Text('Sync: $_syncRuns / $_iterations'),
              Text('Async: $_asyncRuns / $_iterations'),
            ],
            const SizedBox(height: 16),
            Text(
              _status,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              key: const Key('run_trace_demo'),
              onPressed: _running ? null : _runDemo,
              icon: const Icon(Icons.play_arrow),
              label: Text(_running ? 'Running…' : 'Run trace demo'),
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
