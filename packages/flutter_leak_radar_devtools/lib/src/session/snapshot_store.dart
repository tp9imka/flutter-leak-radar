import '../capture/snapshot_bundle.dart';
import '../shell/radar_view.dart';

/// Serialisable snapshot of the Memory view's session state: the captured
/// bundles, which are selected for diffing, and the active view.
///
/// Persisted so the extension can restore itself after DevTools tears down and
/// rebuilds its iframe — e.g. when the user visits Flutter DevTools' own Memory
/// tab and returns, which disposes this extension's Dart context entirely.
final class PersistedSession {
  const PersistedSession({
    required this.bundles,
    required this.selectedIds,
    required this.view,
  });

  final List<SnapshotBundle> bundles;
  final List<int> selectedIds;
  final RadarView view;

  Map<String, Object?> toJson() => {
    'version': 1,
    'bundles': [for (final b in bundles) b.toJson()],
    'selectedIds': selectedIds,
    'view': view.name,
  };

  factory PersistedSession.fromJson(Map<String, Object?> json) {
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
