/// Host-agnostic Radar analysis workbench: models, views, controllers, and the
/// interfaces the DevTools extension and the desktop app both build on.
library;

export 'src/capture/snapshot_analyzer.dart';
export 'src/capture/snapshot_bundle.dart';
export 'src/core/radar_connection.dart';
export 'src/core/snapshot_source.dart';
export 'src/core/snapshot_exporter.dart';
export 'src/filter/filter_bar.dart';
export 'src/filter/filter_expression.dart';
export 'src/memory/class_detail_panel.dart';
export 'src/memory/class_histogram_view.dart';
export 'src/memory/diff_table.dart';
export 'src/memory/filter_target.dart';
export 'src/memory/mem_format.dart';
export 'src/memory/memory_controller.dart';
export 'src/memory/memory_view.dart';
export 'src/memory/retaining_paths_view.dart';
export 'src/memory/root_kind_ui.dart';
export 'src/memory/snapshots_view.dart';
export 'src/memory/sort_header_cell.dart';
export 'src/perf/frames_view.dart';
export 'src/perf/perf_data_controller.dart';
export 'src/perf/perf_snapshot_dto.dart';
export 'src/perf/perf_state_views.dart';
export 'src/perf/traces_view.dart';
export 'src/presentation/main_scaffold.dart';
export 'src/presentation/retaining_path_tile.dart';
export 'src/session/radar_session.dart';
export 'src/session/session_persistence.dart';
export 'src/session/snapshot_store.dart';
export 'src/shell/connection_bar.dart';
export 'src/shell/left_rail.dart';
export 'src/shell/radar_view.dart';
export 'src/stability/errors_view.dart';
export 'src/stability/stalls_view.dart';
