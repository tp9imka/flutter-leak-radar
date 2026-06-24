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
export 'src/model/graph_analysis_result.dart';
