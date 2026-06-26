import 'package:flutter/material.dart';

import '../connection/connection_state_notifier.dart';

/// Shows VM/isolate connection state as a compact banner above the main UI.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.notifier});

  final ConnectionStateNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        final state = notifier.state;
        return switch (state.phase) {
          ExtensionConnectionPhase.connecting => const _Banner(
            color: Colors.orange,
            icon: Icons.hourglass_empty,
            message: 'Connecting to VM service…',
          ),
          ExtensionConnectionPhase.disconnected => const _Banner(
            color: Colors.red,
            icon: Icons.link_off,
            message: 'Disconnected. Attach DevTools to a running app.',
          ),
          ExtensionConnectionPhase.connected => _Banner(
            color: Colors.green,
            icon: Icons.link,
            message:
                'Connected — VM: ${state.vmName ?? "?"}'
                ' / Isolate: ${state.isolateName ?? "?"}',
          ),
        };
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(message, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
