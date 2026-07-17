import 'dart:async';

import '../capture/snapshot_bundle.dart';
import '../memory/memory_controller.dart';
import '../shell/radar_view.dart';
import 'snapshot_store.dart';
import 'triage_store.dart';

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
    TriageStore Function()? readTriage,
    DateTime Function()? clock,
    Duration debounce = const Duration(milliseconds: 500),
  }) : _store = store,
       _memory = memory,
       _readView = readView,
       _readTriage = readTriage ?? (() => TriageStore.empty),
       _clock = clock ?? DateTime.now,
       _debounce = debounce;

  final SnapshotStore _store;
  final MemoryController _memory;
  final RadarView Function() _readView;

  /// The in-session triage *display* store (loaded baseline + explicit ACKs)
  /// the views read. Read at each save so ACKs propagate to disk, but never
  /// mutated here — a signature stays NEW in the current view until a later
  /// session loads the promoted [_diskStore]. Injected for testability.
  final TriageStore Function() _readTriage;

  /// Source of `firstSeen` / `goneSince` timestamps.
  final DateTime Function() _clock;

  final Duration _debounce;

  /// The accumulating on-disk mirror. Initialised from the loaded session and
  /// re-folded on each save, so a signature's `firstSeen` is stamped once and
  /// pinned across the session rather than drifting to each save's clock.
  TriageStore _diskStore = TriageStore.empty;

  Timer? _timer;
  bool _started = false;

  /// The reason the loaded session was refused (newer schema), or null. Surfaced
  /// by the host; while non-null the store also suppresses writes.
  String? get restoreRefusal => _store.restoreRefusal;

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

  PersistedSession _currentSession() {
    final focused = _memory.focused;
    _diskStore = foldSessionTriage(
      diskStore: _diskStore,
      displayStore: _readTriage(),
      // Null (no focused snapshot) skips the fold — see [foldSessionTriage].
      classNameBySignature: focused == null
          ? null
          : classNamesBySignature(focused),
      now: _clock(),
    );
    return PersistedSession(
      bundles: _memory.persistableSnapshots,
      selectedIds: _memory.selectedIds,
      view: _readView(),
      triage: _diskStore,
    );
  }

  /// Reads the last persisted session, if any, and seeds the on-disk mirror
  /// from its triage store so the first save preserves loaded `firstSeen`
  /// stamps. The caller applies the rest (view, then
  /// [MemoryController.rehydrate]) before [start], keeping the rehydrate
  /// notification from triggering a re-persist.
  Future<PersistedSession?> load() async {
    final session = await _store.restore();
    _diskStore = session?.triage ?? TriageStore.empty;
    return session;
  }

  void dispose() {
    _timer?.cancel();
    if (_started) _memory.removeListener(schedule);
  }
}

/// The [focused] snapshot's leak clusters as `signature -> className` — the
/// current cluster set cross-session identity is folded against. Shared by the
/// DevTools and desktop persistence paths.
Map<String, String> classNamesBySignature(SnapshotBundle focused) => {
  for (final c in focused.analysisResult.clusters) c.signature: c.className,
};
