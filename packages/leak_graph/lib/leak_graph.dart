/// Pure-Dart heap-graph analysis library.
///
/// Loads VM heap snapshots via [vm_service] and builds an in-memory object
/// graph for retaining-path analysis. Use this package to detect which objects
/// are keeping a suspected leak alive and why.
///
/// Exports are added incrementally as each phase of the implementation lands.
library;

export 'src/model/root_kind.dart';
export 'src/model/graph_retaining_path.dart';
export 'src/model/graph_leak_cluster.dart';
export 'src/model/class_root_profile.dart';
export 'src/model/class_path_distribution.dart';
export 'src/model/graph_analysis_result.dart';
export 'src/model/package_rollup.dart';
export 'src/graph/heap_graph_view.dart';
export 'src/graph/vm_snapshot_adapter.dart';
export 'src/graph/snapshot_loader.dart';
export 'src/analysis/shortest_retaining_paths.dart';
export 'src/analysis/root_classifier.dart';
export 'src/analysis/app_package_set.dart';
export 'src/analysis/class_origin.dart';
export 'src/analysis/pubspec_name.dart';
export 'src/analysis/clustering.dart';
export 'src/analysis/graph_leak_analyzer.dart';
export 'src/analysis/live_tree.dart';
export 'src/cli/report_renderer.dart';
export 'src/cli/markdown_renderer.dart';
export 'src/cli/baseline.dart';
export 'src/analysis/histogram_diff.dart';
