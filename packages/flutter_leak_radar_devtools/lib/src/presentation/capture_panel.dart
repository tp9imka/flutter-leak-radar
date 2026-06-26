import 'package:flutter/material.dart';

import '../diff/diff_controller.dart';

/// The control panel for the capture→act→capture→diff workflow.
///
/// Shows guidance text and the Capture A / Capture B / Reset buttons
/// driven by [DiffController].
class CapturePanel extends StatelessWidget {
  const CapturePanel({super.key, required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final phase = controller.phase;
        final busy =
            phase == CapturePhase.capturingA ||
            phase == CapturePhase.capturingB;
        return _CapturePanelContent(
          controller: controller,
          phase: phase,
          busy: busy,
        );
      },
    );
  }
}

class _CapturePanelContent extends StatelessWidget {
  const _CapturePanelContent({
    required this.controller,
    required this.phase,
    required this.busy,
  });

  final DiffController controller;
  final CapturePhase phase;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _guidance(phase),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: busy ? null : controller.captureA,
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('Capture A (baseline)'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (phase == CapturePhase.readyForB && !busy)
                      ? controller.captureB
                      : null,
                  icon: const Icon(Icons.compare_arrows, size: 16),
                  label: const Text('Capture B (compare)'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: (phase != CapturePhase.idle && !busy)
                      ? controller.reset
                      : null,
                  child: const Text('Reset'),
                ),
                if (busy) ...[
                  const SizedBox(width: 12),
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _guidance(CapturePhase phase) => switch (phase) {
    CapturePhase.idle =>
      '1. Press "Capture A" to take a baseline heap snapshot.',
    CapturePhase.capturingA => 'Capturing snapshot A…',
    CapturePhase.readyForB =>
      '2. Perform the action you suspect causes a leak in the app, '
          'then press "Capture B".',
    CapturePhase.capturingB => 'Capturing snapshot B…',
    CapturePhase.done =>
      'Diff complete. See the Diff tab for grew classes '
          'and the Clusters tab for leak analysis.',
  };
}
