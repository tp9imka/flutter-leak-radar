import 'dart:convert';

import '../model/graph_analysis_result.dart';
import '../model/graph_retaining_path.dart';

/// Renders a human-readable ranked report of leak clusters.
///
/// Displays up to [top] clusters, each with count, class name, retained bytes,
/// root kind label, and representative retaining path.
String renderReport(GraphAnalysisResult result, {int top = 20}) {
  final clusters = result.clusters;
  final total = clusters.length;
  final shown = clusters.length > top ? top : clusters.length;
  final suppressed = total - shown;

  final buf = StringBuffer();
  buf.writeln(
    'Leak clusters: $total found${suppressed > 0 ? ', $suppressed suppressed by --top limit' : ''}',
  );
  buf.writeln();

  for (var i = 0; i < shown; i++) {
    final c = clusters[i];
    buf.writeln(
      '× ${c.instanceCount}  ${c.className}  (${c.retainedShallowBytes} B)  [${c.rootKind.label}]',
    );
    buf.writeln('  ${_formatPath(c.representativePath)}');
  }

  return buf.toString().trimRight();
}

String _formatPath(GraphRetainingPath path) {
  if (path.hops.isEmpty) return '(empty path)';
  return path.hops.map((h) => h.className).join(' > ');
}

/// Encodes a [GraphAnalysisResult] as a JSON string.
String renderJson(GraphAnalysisResult result) => jsonEncode(result.toJson());
