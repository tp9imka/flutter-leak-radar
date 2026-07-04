import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows an error [message] as a SnackBar carrying a **Copy** action. Tapping
/// Copy puts a shareable payload — a `Radar Desktop error` header, the optional
/// [source] (which action failed), and the full message — on the clipboard, so
/// a user can paste the complete error verbatim. No-ops when [context] has no
/// [ScaffoldMessenger] (e.g. a widget test that pumps a screen bare).
void showRadarError(BuildContext context, String message, {String? source}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final payload = errorClipboardPayload(message, source: source);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 10),
        showCloseIcon: true,
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: payload)),
        ),
      ),
    );
}

/// The shareable clipboard text for an error [message]: a stable header plus
/// the optional [source] and the full message. Pure — exposed for testing and
/// reused by any inline error surface (e.g. the connect bar) that offers a
/// copy affordance.
String errorClipboardPayload(String message, {String? source}) {
  final buffer = StringBuffer('Radar Desktop');
  if (source != null && source.isNotEmpty) buffer.write(' · $source');
  buffer
    ..write('\n')
    ..write(message);
  return buffer.toString();
}
