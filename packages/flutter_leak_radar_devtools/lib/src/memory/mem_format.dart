// Shared formatting helpers for the Memory views.

/// Human-readable byte size (B / KB / MB). Preserves sign.
String fmtBytes(int bytes) {
  final abs = bytes.abs();
  if (abs < 1024) return '$bytes B';
  if (abs < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// `HH:MM:SS` wall-clock time.
String fmtTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

/// Short library label from a package/file URI (e.g. `package:app/x.dart` →
/// `app`). Returns `--` for null/empty.
String libraryLabel(Uri? uri) {
  if (uri == null) return '--';
  final s = uri.toString();
  if (s.isEmpty) return '--';
  if (s.startsWith('package:')) {
    return s.substring('package:'.length).split('/').first;
  }
  return s.contains('/') ? s.split('/').last : s;
}
