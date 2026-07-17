import '../capture/snapshot_bundle.dart';
import '../shell/radar_view.dart';
import 'triage_store.dart';

/// Current on-disk schema version for [PersistedSession].
///
/// Bumped to 2 by cross-session identity (Task A11), which adds the `triage`
/// map. A v1 payload (no triage) migrates forward by defaulting to an empty
/// [TriageStore]; a payload newer than this build is refused rather than
/// silently truncated. See [PersistedSession.fromJson].
const int kSessionSchemaVersion = 2;

/// Thrown when a persisted session was written by a newer build than can read
/// it (forward-incompatible schema). Stores must catch this and degrade (drop
/// the state) rather than crash the UI.
class UnsupportedSessionVersionException implements Exception {
  const UnsupportedSessionVersionException(this.found, this.supported);

  final int found;
  final int supported;

  @override
  String toString() =>
      'Persisted session schema v$found is newer than this build supports '
      '(v$supported). Update the tool to read this session.';
}

/// Serialisable snapshot of the Memory view's session state: the captured
/// bundles, which are selected for diffing, the active view, and the
/// cross-session leak-triage history.
///
/// Persisted so the extension can restore itself after DevTools tears down and
/// rebuilds its iframe — e.g. when the user visits Flutter DevTools' own Memory
/// tab and returns, which disposes this extension's Dart context entirely.
final class PersistedSession {
  const PersistedSession({
    required this.bundles,
    required this.selectedIds,
    required this.view,
    this.triage = TriageStore.empty,
  });

  final List<SnapshotBundle> bundles;
  final List<int> selectedIds;
  final RadarView view;

  /// Cross-session leak identity: which signatures are known/acknowledged and
  /// when they were first seen. Empty for a fresh or migrated-from-v1 session.
  final TriageStore triage;

  Map<String, Object?> toJson() => {
    'version': kSessionSchemaVersion,
    'bundles': [for (final b in bundles) b.toJson()],
    'selectedIds': selectedIds,
    'view': view.name,
    'triage': triage.toJson(),
  };

  /// Reads a persisted session, enforcing the schema [kSessionSchemaVersion].
  ///
  /// A version greater than this build supports throws
  /// [UnsupportedSessionVersionException] (never guess at a newer layout). A
  /// lower/absent version migrates forward: fields added since (the `triage`
  /// map) default to empty.
  factory PersistedSession.fromJson(Map<String, Object?> json) {
    final version = (json['version'] as num?)?.toInt() ?? 1;
    if (version > kSessionSchemaVersion) {
      throw UnsupportedSessionVersionException(version, kSessionSchemaVersion);
    }
    final triageJson = json['triage'];
    final viewName = json['view'] as String?;
    return PersistedSession(
      bundles: [
        for (final e in (json['bundles'] as List? ?? const []))
          SnapshotBundle.fromJson((e as Map).cast<String, Object?>()),
      ],
      selectedIds: [
        for (final e in (json['selectedIds'] as List? ?? const []))
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
}

/// Durable store for the Memory session, surviving the extension's iframe being
/// disposed and recreated. Implementations must degrade gracefully (no throw)
/// when their backend is unavailable.
abstract interface class SnapshotStore {
  /// Writes the current session. Called (debounced) after each mutation.
  Future<void> persist(PersistedSession session);

  /// Reads the last persisted session, or null if none / unavailable.
  Future<PersistedSession?> restore();

  /// Drops all persisted state.
  Future<void> clear();
}

/// In-memory [SnapshotStore] for tests and for runtimes with no durable backend
/// available. Holds the last persisted session in a field.
final class InMemorySnapshotStore implements SnapshotStore {
  PersistedSession? _last;

  /// Number of [persist] calls — useful for asserting debounce behaviour.
  int persistCount = 0;

  PersistedSession? get last => _last;

  @override
  Future<void> persist(PersistedSession session) async {
    _last = session;
    persistCount++;
  }

  @override
  Future<PersistedSession?> restore() async => _last;

  @override
  Future<void> clear() async => _last = null;
}
