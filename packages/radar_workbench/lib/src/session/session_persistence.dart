import 'dart:async';

import '../memory/memory_controller.dart';
import '../shell/radar_view.dart';
import 'snapshot_store.dart';

/// Wires the [MemoryController] (and the active view) to a [SnapshotStore],
/// debouncing writes and loading persisted state on startup.
///
/// Keeps [RadarSession] and the controller free of persistence-timing concerns
/// and is unit-testable with an [InMemorySnapshotStore].
class SessionPersistence {
  SessionPersistence({
    required SnapshotStore store,
    required MemoryController memory,
    required RadarView Function() readView,
    Duration debounce = const Duration(milliseconds: 500),
  }) : _store = store,
       _memory = memory,
       _readView = readView,
       _debounce = debounce;

  final SnapshotStore _store;
  final MemoryController _memory;
  final RadarView Function() _readView;
  final Duration _debounce;

  Timer? _timer;
  bool _started = false;

  /// Begins observing controller mutations to schedule debounced writes.
  void start() {
    if (_started) return;
    _started = true;
    _memory.addListener(schedule);
  }

  /// Schedules a debounced persist. Also call this on view changes, which the
  /// controller does not surface.
  void schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(flush()));
  }

  /// Persists the current session immediately, bypassing the debounce.
  Future<void> flush() async {
    _timer?.cancel();
    await _store.persist(_currentSession());
  }

  PersistedSession _currentSession() => PersistedSession(
    bundles: _memory.persistableSnapshots,
    selectedIds: _memory.selectedIds,
    view: _readView(),
  );

  /// Reads the last persisted session, if any. The caller applies it (setting
  /// the view, then [MemoryController.rehydrate]) so restore happens before
  /// [start], keeping the rehydrate notification from triggering a re-persist.
  Future<PersistedSession?> load() => _store.restore();

  void dispose() {
    _timer?.cancel();
    if (_started) _memory.removeListener(schedule);
  }
}
