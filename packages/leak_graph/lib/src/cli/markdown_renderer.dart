import '../analysis/class_origin.dart';
import '../model/graph_analysis_result.dart';
import '../model/graph_leak_cluster.dart';
import '../model/graph_retaining_path.dart';
import '../model/package_rollup.dart';
import 'baseline.dart';

/// Reused only for [OriginClassifier.packageOf], which needs no project-owned
/// package set — the renderer never guesses ownership itself, it reads the
/// origin the analyzer already computed into [GraphAnalysisResult
/// .anchorRollups].
const _packageNameOf = OriginClassifier(projectPackages: {});

/// Renders the 30-second markdown/GitHub report for [result].
///
/// Line 1 is always the verdict — `✅ no leak clusters`, `❌ gate failed: ` plus
/// the first violation, `✅ N clusters (gate passed)`, or `⚠ N clusters (no
/// gate)` — so a reader never has to open anything to get the headline.
/// Immediately below it are at most 3 NEW-or-worst project-anchor clusters
/// (each anchored in the caller's own code, per [GraphAnalysisResult
/// .anchorRollups]), and everything else — the full cluster table, package
/// rollups, run stats/warnings, and clusters gone since the baseline — is
/// folded into `<details>` blocks so it never competes with the headline.
///
/// [comparison] adds NEW/grown/known badges and nearest-known hints when a
/// baseline was available; [gate] adds the pass/fail verdict. [github] turns
/// on GitHub-flavored-markdown-only syntax (the `> [!CAUTION]` gate
/// admonition) for step summaries and PR comments — plain `md` renders the
/// same content with standard markdown only.
String renderMarkdownReport(
  GraphAnalysisResult result, {
  BaselineComparison? comparison,
  GateResult? gate,
  required bool github,
}) {
  final buf = StringBuffer()
    ..writeln(_verdictLine(result, gate))
    ..writeln();

  final highlights = _selectHighlights(result, comparison);
  if (highlights.isNotEmpty) {
    buf
      ..writeln(
        '### Top project-anchor clusters '
        '(${highlights.length} of ${result.clusters.length})',
      )
      ..writeln();
    for (var i = 0; i < highlights.length; i++) {
      _writeHighlight(buf, i + 1, highlights[i], result.anchorRollups);
    }
  }

  if (gate != null && !gate.passed) {
    _writeGateDetails(buf, gate, github: github);
  }

  _writeClusterTableDetails(buf, result);
  _writeRollupDetails(buf, result);
  _writeStatsDetails(buf, result.stats);
  _writeGoneDetails(buf, comparison);

  return buf.toString().trimRight();
}

String _verdictLine(GraphAnalysisResult result, GateResult? gate) {
  if (gate != null && !gate.passed) {
    return '❌ gate failed: ${gate.violations.first}';
  }
  if (result.clusters.isEmpty) return '✅ no leak clusters';
  final count = result.clusters.length;
  return gate != null
      ? '✅ $count clusters (gate passed)'
      : '⚠ $count clusters (no gate)';
}

/// One current cluster paired with its baseline classification, when known.
typedef _Highlight = ({GraphLeakCluster cluster, ClusterDelta? delta});

/// Picks at most 3 project-anchor clusters: NEW ones first (largest first),
/// then the worst (largest shallow bytes) of the rest — so a reviewer always
/// sees either what's new or what's biggest, never neither.
List<_Highlight> _selectHighlights(
  GraphAnalysisResult result,
  BaselineComparison? comparison,
) {
  final deltaBySignature = <String, ClusterDelta>{
    if (comparison != null && comparison.baselineComparable)
      for (final d in comparison.deltas) d.cluster.signature: d,
  };

  final candidates = <_Highlight>[
    for (final cluster in result.clusters)
      if (_originOf(cluster, result.anchorRollups) == ClassOrigin.project)
        (cluster: cluster, delta: deltaBySignature[cluster.signature]),
  ];

  candidates.sort((a, b) {
    final aNew = a.delta?.novelty == ClusterNovelty.newCluster;
    final bNew = b.delta?.novelty == ClusterNovelty.newCluster;
    if (aNew != bNew) return aNew ? -1 : 1;
    final byBytes = b.cluster.retainedShallowBytes.compareTo(
      a.cluster.retainedShallowBytes,
    );
    if (byBytes != 0) return byBytes;
    return b.cluster.instanceCount.compareTo(a.cluster.instanceCount);
  });

  return candidates.take(3).toList();
}

void _writeHighlight(
  StringBuffer buf,
  int rank,
  _Highlight highlight,
  List<PackageRollup> anchorRollups,
) {
  final cluster = highlight.cluster;
  final package = _packageOf(cluster.libraryUri) ?? '(unknown)';
  final origin = _originOf(cluster, anchorRollups);
  buf
    ..writeln(
      '**$rank. ${cluster.className}** — `$package` '
      '${_originLabel(origin)}',
    )
    ..writeln(
      '- ${cluster.instanceCount} instances retained, '
      '${cluster.retainedShallowBytes} B shallow',
    )
    ..writeln('- ${_anchorLine(cluster)}');

  final delta = highlight.delta;
  if (delta != null && delta.novelty == ClusterNovelty.newCluster) {
    final nearest = delta.nearestKnownSignature;
    buf.writeln(
      nearest == null
          ? '- 🆕 new cluster'
          : '- 🆕 new cluster — nearest known: `$nearest`',
    );
  } else if (delta != null && delta.novelty == ClusterNovelty.grown) {
    buf.writeln(
      '- 📈 grown by +${delta.instanceDelta} instances, '
      '+${delta.bytesDelta} B shallow',
    );
  }
  buf.writeln();
}

/// Describes where the caller's own code holds the leak.
///
/// When [GraphLeakCluster.anchorHopIndex] names an app-owned hop, this is the
/// field on that hop's class that leads onward to the leaked object (a
/// [GraphHop]'s `field`/`index` label the edge INTO it, so the anchor's own
/// holding field lives on the NEXT hop). When there is no anchor — the
/// leaked object IS the app class, with no internal SDK leaf underneath it —
/// this instead names the retaining root kind, since there is no field to
/// point to.
String _anchorLine(GraphLeakCluster cluster) {
  final anchorIndex = cluster.anchorHopIndex;
  if (anchorIndex == null) {
    return 'your code retains this `${cluster.className}` instance '
        'directly via a ${cluster.rootKind.label} root';
  }

  final hops = cluster.representativePath.hops;
  final anchorClassName = anchorIndex < hops.length
      ? hops[anchorIndex].className
      : cluster.className;
  final holdsAt = anchorIndex + 1 < hops.length
      ? _fieldLabel(hops[anchorIndex + 1])
      : null;

  return holdsAt == null
      ? 'your code holds this via `$anchorClassName`'
      : 'your code holds it at `$anchorClassName.$holdsAt`';
}

String? _fieldLabel(GraphHop hop) {
  if (hop.field != null) return hop.field;
  if (hop.index != null) return '[${hop.index}]';
  return null;
}

String? _packageOf(Uri? libraryUri) =>
    libraryUri == null ? null : _packageNameOf.packageOf(libraryUri);

/// The origin the analyzer already computed for [cluster]'s anchor package.
///
/// Looked up from [anchorRollups] rather than re-classified here: rollups are
/// built from the SAME resolved project-package set as [cluster], so this
/// never has to guess. A package absent from the rollups (only possible for
/// a cluster built outside a real analysis run) is reported as
/// [ClassOrigin.unknown] rather than assumed.
ClassOrigin _originOf(
  GraphLeakCluster cluster,
  List<PackageRollup> anchorRollups,
) {
  final package = _packageOf(cluster.libraryUri);
  if (package == null) return ClassOrigin.unknown;
  for (final rollup in anchorRollups) {
    if (rollup.package == package) return rollup.origin;
  }
  return ClassOrigin.unknown;
}

String _originLabel(ClassOrigin origin) => switch (origin) {
  ClassOrigin.project => '[yours]',
  ClassOrigin.dependency => '[dependency]',
  ClassOrigin.flutterFramework => '[framework]',
  ClassOrigin.dartSdk => '[sdk]',
  ClassOrigin.unknown => '[?]',
};

void _writeGateDetails(
  StringBuffer buf,
  GateResult gate, {
  required bool github,
}) {
  if (github) {
    buf.writeln('> [!CAUTION]');
    buf.writeln('> Gate failed:');
    for (final violation in gate.violations) {
      buf.writeln('> - $violation');
    }
  } else {
    buf.writeln('**Gate violations:**');
    for (final violation in gate.violations) {
      buf.writeln('- $violation');
    }
  }
  buf.writeln();
}

void _writeClusterTableDetails(StringBuffer buf, GraphAnalysisResult result) {
  buf.writeln('<details>');
  buf.writeln('<summary>All ${result.clusters.length} leak clusters</summary>');
  buf.writeln();
  if (result.clusters.isEmpty) {
    buf.writeln('No clusters were reported.');
  } else {
    buf.writeln(
      '| Class | Package | Origin | Instances | Shallow Bytes | Root | '
      'Confidence |',
    );
    buf.writeln('|---|---|---|---|---|---|---|');
    for (final cluster in result.clusters) {
      final package = _packageOf(cluster.libraryUri) ?? '(unknown)';
      final origin = _originOf(cluster, result.anchorRollups);
      buf.writeln(
        '| ${cluster.className} | $package | ${_originLabel(origin)} | '
        '${cluster.instanceCount} | ${cluster.retainedShallowBytes} B '
        'shallow | ${cluster.rootKind.label} | ${cluster.confidence.name} |',
      );
    }
  }
  buf.writeln();
  buf.writeln('</details>');
  buf.writeln();
}

void _writeRollupDetails(StringBuffer buf, GraphAnalysisResult result) {
  buf.writeln('<details>');
  buf.writeln('<summary>Package rollups</summary>');
  buf.writeln();
  buf.writeln('**retained via (anchor rollup)**');
  buf.writeln();
  _writeRollupTable(buf, result.anchorRollups);
  buf.writeln();
  buf.writeln('**declared by (declared rollup)**');
  buf.writeln();
  _writeRollupTable(buf, result.declaredRollups);
  buf.writeln();
  buf.writeln('</details>');
  buf.writeln();
}

void _writeRollupTable(StringBuffer buf, List<PackageRollup> rollups) {
  if (rollups.isEmpty) {
    buf.writeln('None.');
    return;
  }
  buf.writeln(
    '| Package | Origin | Classes | Instances (raw) | '
    'Shallow Bytes | Clusters |',
  );
  buf.writeln('|---|---|---|---|---|---|');
  for (final rollup in rollups) {
    buf.writeln(
      '| ${rollup.package} | ${_originLabel(rollup.origin)} | '
      '${rollup.classCount} | ${rollup.instanceCount} | '
      '${rollup.shallowBytes} B shallow | ${rollup.clusterCount} |',
    );
  }
}

void _writeStatsDetails(StringBuffer buf, GraphAnalysisStats stats) {
  buf.writeln('<details>');
  buf.writeln('<summary>Run stats &amp; warnings</summary>');
  buf.writeln();
  buf.writeln('- Total objects: ${stats.totalObjects}');
  buf.writeln('- Reachable objects: ${stats.reachableObjects}');
  buf.writeln('- Leak candidates: ${stats.leakCandidates}');
  buf.writeln('- Clusters: ${stats.clusters}');
  buf.writeln('- Suppressed by app filter: ${stats.suppressedByAppFilter}');
  buf.writeln('- Suppressed by live tree: ${stats.suppressedByLiveTree}');
  if (stats.warnings.isNotEmpty) {
    buf.writeln('- Warnings:');
    for (final warning in stats.warnings) {
      buf.writeln('  - $warning');
    }
  }
  buf.writeln();
  buf.writeln('</details>');
  buf.writeln();
}

void _writeGoneDetails(StringBuffer buf, BaselineComparison? comparison) {
  if (comparison == null || !comparison.baselineComparable) return;

  buf.writeln('<details>');
  buf.writeln(
    '<summary>Clusters gone since the baseline '
    '(${comparison.gone.length})</summary>',
  );
  buf.writeln();
  if (comparison.gone.isEmpty) {
    buf.writeln('No clusters disappeared since the baseline.');
  } else {
    buf.writeln(
      '| Class | Signature | Last known instances | '
      'Last known shallow bytes |',
    );
    buf.writeln('|---|---|---|---|');
    for (final gone in comparison.gone) {
      buf.writeln(
        '| ${gone.className} | ${gone.signature} | ${gone.instanceCount} | '
        '${gone.retainedShallowBytes} B shallow |',
      );
    }
  }
  buf.writeln();
  buf.writeln('</details>');
  buf.writeln();
}
