import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../app/error_toast.dart';
import '../seams/vm_service_uri_connection.dart';

/// A thin bar for entering a target app's `ws://` VM service URI and
/// connecting/disconnecting.
///
/// Delegates the connected-state status display (vm/isolate identity) to
/// [ConnectionBar]; this widget adds the URI input and the connect/
/// disconnect action around it.
class ConnectBar extends StatefulWidget {
  const ConnectBar({super.key, required this.connection, this.onScanDevice});

  /// The live connection this bar drives and observes.
  final VmServiceUriConnection connection;

  /// Scans the connected Android device's `adb logcat` for a running
  /// Flutter VM service and `adb forward`s it, returning a ready-to-connect
  /// `ws://…/ws` URI, or null if no VM-service line was found.
  ///
  /// Null hides the "Scan device" button entirely — e.g. when this host
  /// has no resolved `adb`.
  final Future<String?> Function()? onScanDevice;

  @override
  State<ConnectBar> createState() => _ConnectBarState();
}

class _ConnectBarState extends State<ConnectBar> {
  final TextEditingController _uriController = TextEditingController();
  bool _scanning = false;
  String? _scanNote;

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

  Future<void> _scanDevice() async {
    final onScanDevice = widget.onScanDevice;
    if (onScanDevice == null || _scanning) return;
    setState(() {
      _scanning = true;
      _scanNote = null;
    });

    String? result;
    Object? error;
    try {
      result = await onScanDevice();
    } catch (e) {
      error = e;
    }
    if (!mounted) return;

    setState(() {
      _scanning = false;
      _scanNote = switch ((result, error)) {
        (final uri?, _) when uri.isNotEmpty => null,
        (_, final e?) => 'Scan failed: $e',
        _ => 'No running debug/profile app found on the device',
      };
    });
    if (result != null && result.isNotEmpty) {
      _uriController.text = result;
      _uriController.selection = TextSelection.collapsed(offset: result.length);
    }
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
            onScan: widget.onScanDevice == null
                ? null
                : () => unawaited(_scanDevice()),
            scanning: _scanning,
            scanNote: _scanNote,
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
    this.onScan,
    this.scanning = false,
    this.scanNote,
  });

  final TextEditingController uriController;
  final String? lastError;
  final VoidCallback onConnect;

  /// Non-null when [ConnectBar.onScanDevice] was supplied; tapping
  /// triggers a fresh `adb logcat` scan. Null hides the scan button and
  /// spinner entirely, leaving this bar's layout unchanged.
  final VoidCallback? onScan;

  /// True while a scan triggered by [onScan] is in flight.
  final bool scanning;

  /// Inline note from the most recent scan (no app found, or an error);
  /// null once a scan fills the field or before any scan has run.
  final String? scanNote;

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
              if (onScan != null) ...[
                if (scanning)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 3),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.search_rounded, size: 16),
                    tooltip: 'Scan device for a running app',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: RadarColors.text60,
                    onPressed: onScan,
                  ),
                const SizedBox(width: 8),
              ],
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
          if (scanNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                scanNote!,
                style: RadarTypography.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      lastError!,
                      style: RadarTypography.caption.copyWith(
                        color: RadarColors.critical,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    tooltip: 'Copy error',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: RadarColors.critical,
                    onPressed: () => Clipboard.setData(
                      ClipboardData(
                        text: errorClipboardPayload(
                          lastError!,
                          source: 'Connect',
                        ),
                      ),
                    ),
                  ),
                ],
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
