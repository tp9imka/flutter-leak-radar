import 'package:flutter/foundation.dart';

import '../core/project_context.dart';
import '../core/radar_connection.dart';
import '../core/snapshot_exporter.dart';
import '../memory/memory_controller.dart';
import '../perf/perf_data_controller.dart';
import '../shell/radar_view.dart';
import 'session_persistence.dart';
import 'snapshot_store.dart';
import 'triage_store.dart';

/// Process-wide holder for the workbench's controllers and view selection.
///
/// DevTools disposes and rebuilds the extension's Flutter tree on tab switches;
/// the desktop app keeps one session for the window's lifetime. Holding the
/// controllers here — not in a `State` — means captured snapshots, the diff
/// selection, and the active view survive rebuilds.
///
/// The host builds the concrete [connection]/[memory]/[perf]/[exporter] (over
/// serviceManager, a ws:// client, files, etc.) and calls [install] before the
/// UI reads [instance].
class RadarSession {
  RadarSession({
    required this.connection,
    required this.memory,
    required this.perf,
    required this.exporter,
    this.projectContext = const NoProjectContext(),
    VoidCallback? onInit,
  }) : _onInit = onInit;

  final RadarConnection connection;
  final MemoryController memory;
  final PerfDataController perf;
  final SnapshotExporter exporter;

  /// Host project identity for the retaining-paths "yours" attribution and
  /// (desktop) source opening. Defaults to [NoProjectContext].
  final ProjectContext projectContext;

  final VoidCallback? _onInit;

  static RadarSession? _instance;

  /// The installed session. Throws if the host has not called [install].
  static RadarSession get instance =>
      _instance ??
      (throw StateError(
        'RadarSession not installed. Call RadarSession.install().',
      ));

  /// Installs [session] as the process-wide instance.
  static void install(RadarSession session) => _instance = session;

  @visibleForTesting
  static void debugReset() => _instance = null;

  /// Currently selected left-rail destination; persisted across rebuilds.
  RadarView currentView = RadarView.snapshotDiff;

  /// Cross-session leak-triage baseline for this session: the store loaded from
  /// disk plus any explicit ACKs made during the session. The clusters view
  /// compares the current cluster set against this to derive NEW/KNOWN/ACK/GONE.
  /// The disk copy additionally folds current signatures in as KNOWN on save
  /// (see [SessionPersistence]); this in-session field is left un-promoted so
  /// signatures stay NEW for the whole current session.
  TriageStore triage = TriageStore.empty;

  SessionPersistence? _persistence;
  bool _initialized = false;
  bool _storeAttached = false;

  /// Runs the host's one-time init (e.g. connection watching) once.
  void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _onInit?.call();
  }

  /// Attaches a durable [store]: restores any previously persisted session,
  /// then begins debounced persistence. Idempotent.
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
      readTriage: () => triage,
    );
    _persistence = persistence;
    final session = await persistence.load();
    if (session != null) {
      // Seed the triage baseline even when there are no bundles to rehydrate —
      // cross-session identity is independent of whether snapshots restored.
      triage = session.triage;
      if (session.bundles.isNotEmpty) {
        currentView = session.view;
        memory.rehydrate(session);
        onRestored?.call();
      }
    }
    persistence.start();
  }

  /// Updates the active view and schedules a debounced persist.
  void selectView(RadarView view) {
    currentView = view;
    _persistence?.schedule();
  }

  /// Applies an explicit triage change (an ACK from the clusters view) to the
  /// in-session baseline and schedules a debounced persist so it survives.
  void updateTriage(TriageStore next) {
    triage = next;
    _persistence?.schedule();
  }
}
