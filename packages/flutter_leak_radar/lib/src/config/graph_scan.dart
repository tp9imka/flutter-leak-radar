// lib/src/config/graph_scan.dart
import 'package:flutter/foundation.dart';

/// Controls live object-graph analysis triggered after navigation events.
///
/// Attach an instance to [LeakRadarConfig.graphScan] to enable the feature;
/// `null` (the default) disables graph analysis entirely.
@immutable
final class GraphScan {
  const GraphScan({
    this.everyNthNavigation = 5,
    this.maxGraphObjects = 500000,
    this.appPackages = const [],
    this.minClusterSize = 2,
  });

  /// How many navigation events must occur between graph scans.
  final int everyNthNavigation;

  /// Maximum number of objects the graph traversal will visit before stopping.
  final int maxGraphObjects;

  /// Package name prefixes used to identify app-owned classes in the graph.
  final List<String> appPackages;

  /// Minimum cluster size for a group of retained objects to be reported.
  final int minClusterSize;

  @override
  bool operator ==(Object other) =>
      other is GraphScan &&
      other.everyNthNavigation == everyNthNavigation &&
      other.maxGraphObjects == maxGraphObjects &&
      listEquals(other.appPackages, appPackages) &&
      other.minClusterSize == minClusterSize;

  @override
  int get hashCode => Object.hash(
    everyNthNavigation,
    maxGraphObjects,
    Object.hashAll(appPackages),
    minClusterSize,
  );
}
