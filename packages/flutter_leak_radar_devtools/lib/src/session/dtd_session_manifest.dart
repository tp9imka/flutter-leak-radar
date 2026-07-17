import 'package:radar_workbench/radar_workbench.dart';

/// Pure (DTD-free, so VM-testable) build/parse of the DevTools session
/// manifest: version, the bundle *ids* (contents live in sibling files), the
/// diff selection, the view, and the cross-session triage store.

/// The manifest JSON for [session].
Map<String, Object?> buildSessionManifest(PersistedSession session) => {
  'version': kSessionSchemaVersion,
  'bundleIds': [for (final b in session.bundles) b.id],
  'selectedIds': session.selectedIds,
  'view': session.view.name,
  'triage': session.triage.toJson(),
};

/// Parsed manifest metadata; bundle contents are loaded separately.
typedef SessionManifest = ({
  List<int> bundleIds,
  List<int> selectedIds,
  RadarView view,
  TriageStore triage,
});

/// Parses a decoded [manifest], enforcing the schema version it declares
/// (previously written but never read): a session from a newer build throws
/// [UnsupportedSessionVersionException] rather than being silently truncated.
SessionManifest parseSessionManifest(Map<String, Object?> manifest) {
  final version = (manifest['version'] as num?)?.toInt() ?? 1;
  if (version > kSessionSchemaVersion) {
    throw UnsupportedSessionVersionException(version, kSessionSchemaVersion);
  }
  final triageJson = manifest['triage'];
  final viewName = manifest['view'] as String?;
  return (
    bundleIds: [
      for (final e in (manifest['bundleIds'] as List? ?? const []))
        (e as num).toInt(),
    ],
    selectedIds: [
      for (final e in (manifest['selectedIds'] as List? ?? const []))
        (e as num).toInt(),
    ],
    view: RadarView.values.firstWhere(
      (v) => v.name == viewName,
      orElse: () => RadarView.snapshotDiff,
    ),
    triage: triageJson == null
        ? TriageStore.empty
        : TriageStore.fromJson((triageJson as Map).cast<String, Object?>()),
  );
}
