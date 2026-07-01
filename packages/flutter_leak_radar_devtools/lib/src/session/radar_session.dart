import '../capture/snapshot_service.dart';
import '../connection/connection_state_notifier.dart';
import '../memory/memory_controller.dart';
import '../perf/perf_data_controller.dart';
import '../shell/radar_view.dart';

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

  bool _initialized = false;

  /// Starts connection watching once; subsequent calls are no-ops.
  void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    connection.init();
  }
}
