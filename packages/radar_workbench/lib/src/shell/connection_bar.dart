import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../core/radar_connection.dart';

/// Fixed-height top bar showing VM service connection status and
/// basic isolate identity.
///
/// Observes [RadarConnection] and rebuilds only when the
/// connection phase or identifiers change.
class ConnectionBar extends StatelessWidget {
  const ConnectionBar({super.key, required this.connection});

  final RadarConnection connection;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final state = connection.state;
        final connected = state.phase == RadarConnectionPhase.connected;
        return _ConnectionBarContent(state: state, connected: connected);
      },
    );
  }
}

class _ConnectionBarContent extends StatelessWidget {
  const _ConnectionBarContent({required this.state, required this.connected});

  final RadarConnectionState state;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RadarColors.bgPanel,
        border: Border(
          bottom: BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _ConnectionChip(connected: connected),
              const SizedBox(width: 12),
              Expanded(child: _IsolateIdentity(state: state)),
              _HeapStats(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final borderColor = connected ? RadarColors.accent : RadarColors.critical;
    final label = connected ? 'connected' : 'disconnected';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (connected) ...[
          const RadarLivePulseDot(size: 7),
          const SizedBox(width: 6),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: RadarColors.bgInput,
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            border: Border.all(
              color: borderColor,
              width: RadarDensity.hairline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(
              label,
              style: RadarTypography.monoLabel.copyWith(color: borderColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _IsolateIdentity extends StatelessWidget {
  const _IsolateIdentity({required this.state});

  final RadarConnectionState state;

  @override
  Widget build(BuildContext context) {
    if (state.isolateName == null && state.vmName == null) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.isolateName != null)
          Text(
            state.isolateName!,
            style: RadarTypography.monoBody,
            overflow: TextOverflow.ellipsis,
          ),
        if (state.isolateName != null && state.vmName != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('·', style: RadarTypography.monoLabel),
          ),
        if (state.vmName != null)
          Text(
            state.vmName!,
            style: RadarTypography.monoLabel,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// Right-aligned heap + uptime display.
///
/// Heap size and uptime require active polling which is not yet wired;
/// both display `--` as the honest "not yet measured" state.
class _HeapStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatPair(label: 'heap', value: '--'),
        const SizedBox(width: 16),
        _StatPair(label: 'uptime', value: '--'),
      ],
    );
  }
}

class _StatPair extends StatelessWidget {
  const _StatPair({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: RadarTypography.monoLabel),
        Text(
          value,
          style: RadarTypography.monoBody.copyWith(color: RadarColors.text60),
        ),
      ],
    );
  }
}
