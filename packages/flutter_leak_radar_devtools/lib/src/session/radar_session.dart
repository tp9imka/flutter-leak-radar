import '../capture/snapshot_service.dart';
import '../connection/connection_state_notifier.dart';
import '../memory/memory_controller.dart';
import '../perf/perf_data_controller.dart';
import '../shell/radar_view.dart';
import 'session_persistence.dart';
import 'snapshot_store.dart';

/// Process-wide holder for the extension's controllers and view selection.
///
/// DevTools disposes and rebuilds the extension's Flutter tree when the user
/// switches away and back to another DevTools tab. Keeping the controllers
/// here — rather than in a `State` that dies on dispose — means captured
/// snapshots, the diff selection, and the active view survive that rebuild.
///
/// The controllers intentionally live for the whole extension session and are
/// never disposed (a deliberate, bounded "leak" appropriate for a dev tool).
class RadarSession {
  RadarSession._();

  static final RadarSession instance = RadarSession._();

  final ConnectionStateNotifier connection = ConnectionStateNotifier();

  late final MemoryController memory = MemoryController(
    service: const SnapshotService(),
    connection: connection,
  );

  final PerfDataController perf = PerfDataController();

  /// Currently selected left-rail destination; persisted across rebuilds.
  RadarView currentView = RadarView.snapshotDiff;

  SessionPersistence? _persistence;
  bool _initialized = false;
  bool _storeAttached = false;

  /// Starts connection watching once; subsequent calls are no-ops.
  void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    connection.init();
  }

  /// Attaches a durable [store]: restores any previously persisted session,
  /// then begins debounced persistence. Idempotent — later calls are no-ops.
  ///
  /// Restore happens before persistence starts so rehydration does not trigger
  /// a redundant write. The `onRestored` callback lets the host UI rebuild once
  /// restored state is applied (the iframe was rebuilt with empty state).
  Future<void> attachStore(
    SnapshotStore store, {
    void Function()? onRestored,
  }) async {
    if (_storeAttached) return;
    _storeAttached = true;
    final persistence = SessionPersistence(
      store: store,
      memory: memory,
      readView: () => currentView,
    );
    _persistence = persistence;
    final session = await persistence.load();
    if (session != null && session.bundles.isNotEmpty) {
      currentView = session.view; // set before rehydrate so the rebuild sees it
      memory.rehydrate(session);
      onRestored?.call();
    }
    persistence.start();
  }

  /// Updates the active view and schedules a debounced persist.
  void selectView(RadarView view) {
    currentView = view;
    _persistence?.schedule();
  }
}
