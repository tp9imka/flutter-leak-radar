import 'dart:async';

import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../seams/vm_service_uri_connection.dart';

/// A thin bar for entering a target app's `ws://` VM service URI and
/// connecting/disconnecting.
///
/// Delegates the connected-state status display (vm/isolate identity) to
/// [ConnectionBar]; this widget adds the URI input and the connect/
/// disconnect action around it.
class ConnectBar extends StatefulWidget {
  const ConnectBar({super.key, required this.connection});

  /// The live connection this bar drives and observes.
  final VmServiceUriConnection connection;

  @override
  State<ConnectBar> createState() => _ConnectBarState();
}

class _ConnectBarState extends State<ConnectBar> {
  final TextEditingController _uriController = TextEditingController();

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final uri = _uriController.text.trim();
    if (uri.isEmpty) return;
    await widget.connection.connect(uri);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.connection,
      builder: (context, _) {
        return switch (widget.connection.state.phase) {
          RadarConnectionPhase.disconnected => _DisconnectedBar(
            uriController: _uriController,
            lastError: widget.connection.lastError,
            onConnect: () => unawaited(_connect()),
          ),
          RadarConnectionPhase.connecting => const _ConnectingBar(),
          RadarConnectionPhase.connected => _ConnectedBar(
            connection: widget.connection,
          ),
        };
      },
    );
  }
}

/// Panel fill + bottom hairline shared by all three phases, matching
/// [ConnectionBar]'s own chrome.
class _Bar extends StatelessWidget {
  const _Bar({required this.child});

  final Widget child;

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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: child,
      ),
    );
  }
}

class _DisconnectedBar extends StatelessWidget {
  const _DisconnectedBar({
    required this.uriController,
    required this.lastError,
    required this.onConnect,
  });

  final TextEditingController uriController;
  final String? lastError;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return _Bar(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: uriController,
                  style: RadarTypography.monoInput,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'ws://127.0.0.1:PORT/AUTH=/ws',
                  ),
                  onSubmitted: (_) => onConnect(),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: uriController,
                builder: (context, value, _) => FilledButton(
                  onPressed: value.text.trim().isEmpty ? null : onConnect,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: RadarTypography.monoBody.copyWith(fontSize: 12),
                  ),
                  child: const Text('Connect'),
                ),
              ),
            ],
          ),
          if (lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                lastError!,
                style: RadarTypography.caption.copyWith(
                  color: RadarColors.critical,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _ConnectingBar extends StatelessWidget {
  const _ConnectingBar();

  @override
  Widget build(BuildContext context) {
    return _Bar(
      child: Row(
        children: [
          const Expanded(child: RadarLinearProgress()),
          const SizedBox(width: 12),
          Text('Connecting…', style: RadarTypography.monoLabel),
        ],
      ),
    );
  }
}

class _ConnectedBar extends StatelessWidget {
  const _ConnectedBar({required this.connection});

  final VmServiceUriConnection connection;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RadarColors.bgPanel,
      child: Row(
        children: [
          Expanded(child: ConnectionBar(connection: connection)),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton(
              onPressed: () => unawaited(connection.disconnect()),
              style: OutlinedButton.styleFrom(
                foregroundColor: RadarColors.text60,
                side: const BorderSide(
                  color: RadarColors.hairline08,
                  width: RadarDensity.hairline,
                ),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: RadarTypography.monoBody.copyWith(fontSize: 12),
              ),
              child: const Text('Disconnect'),
            ),
          ),
        ],
      ),
    );
  }
}
