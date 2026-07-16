// Shared formatting helpers for the Memory views.

import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

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

/// Classifier reused by [packageLabelOf], where project-package membership
/// never affects the result ([OriginClassifier.packageOf] only looks at
/// scheme and package segment).
const _packageOnlyClassifier = OriginClassifier(projectPackages: <String>{});

/// Ownership bucket for [libraryUri], honestly reporting `null` (unknown
/// owning library) as [RadarOrigin.unknown] rather than guessing.
///
/// [projectPackages] carries the same resolved app-package names
/// `leak_graph`'s analysis already computed for this session (see
/// `OriginClassifier`); pass the empty set when that resolution isn't
/// available and every non-framework/non-SDK package should read as
/// [RadarOrigin.dependency].
RadarOrigin originOf(Uri? libraryUri, {required Set<String> projectPackages}) {
  if (libraryUri == null) return RadarOrigin.unknown;
  final classifier = OriginClassifier(projectPackages: projectPackages);
  return switch (classifier.classify(libraryUri)) {
    ClassOrigin.project => RadarOrigin.project,
    ClassOrigin.dependency => RadarOrigin.dependency,
    ClassOrigin.flutterFramework => RadarOrigin.framework,
    ClassOrigin.dartSdk => RadarOrigin.sdk,
    ClassOrigin.unknown => RadarOrigin.unknown,
  };
}

/// Package label for [libraryUri] (e.g. `'livekit_client'`, `'dart:core'`),
/// or `null` when it can't be determined.
String? packageLabelOf(Uri? libraryUri) {
  if (libraryUri == null) return null;
  return _packageOnlyClassifier.packageOf(libraryUri);
}
