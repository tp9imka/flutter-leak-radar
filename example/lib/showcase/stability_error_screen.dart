// example/lib/showcase/stability_error_screen.dart
//
// Stability · Errors demo.
//
// Throws an error from a button callback. Flutter's framework catches it via
// FlutterError.onError / PlatformDispatcher.onError, which PerfRadar hooks.
// The Stability tab's error count climbs without crashing the app.
import 'package:flutter/material.dart';
import 'package:flutter_radar/flutter_radar.dart';

/// Demonstrates error capture by the Radar stability recorder.
///
/// The error is triggered inside a widget callback so Flutter's error handler
/// intercepts it — the app does NOT crash.
class StabilityErrorScreen extends StatefulWidget {
  const StabilityErrorScreen({super.key});

  @override
  State<StabilityErrorScreen> createState() => _StabilityErrorScreenState();
}

class _StabilityErrorScreenState extends State<StabilityErrorScreen> {
  int _errorCount = 0;

  void _triggerError() {
    // Report the error through FlutterError so it goes through the framework's
    // error handler — this is what Radar's stability recorder hooks into.
    // We do NOT rethrow into the native layer so the app remains alive.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(
          'Demo error #${_errorCount + 1} — intentional, '
          'captured by Radar stability recorder',
        ),
        library: 'radar-showcase',
        context: ErrorDescription(
          'Triggered via the Stability Errors demo button',
        ),
      ),
    );
    final snap = PerfRadar.stabilitySnapshot;
    setState(() => _errorCount = snap.errorCount);
  }

  @override
  Widget build(BuildContext context) {
    final snap = PerfRadar.stabilitySnapshot;

    return Scaffold(
      appBar: AppBar(title: const Text('Stability · Errors Demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Each tap calls FlutterError.reportError() — the same path '
              'real unhandled errors take.\n\n'
              'Radar hooks FlutterError.onError and captures each one in '
              'the Stability recorder without crashing the app.\n\n'
              'Open Radar → Performance → Stability to watch the error '
              'count rise.',
            ),
            const SizedBox(height: 24),
            _StatsRow(
              label: 'Errors captured (session)',
              value: snap.errorCount,
            ),
            const Spacer(),
            FilledButton.icon(
              key: const Key('trigger_error'),
              onPressed: _triggerError,
              icon: const Icon(Icons.bug_report),
              label: const Text('Trigger FlutterError'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
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
            style: TextStyle(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
