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
///
/// The featured clusters are project-anchored first — but a huge
/// dependency/framework/SDK leak (e.g. a native-heap leak in a package like
/// `livekit_client` or `flutter_webrtc`) must never be invisible just because
/// it isn't app-owned: when the single worst cluster overall isn't one of the
/// featured ones, one extra "largest overall" line names it. When there are
/// no project-anchored clusters at all, the featured slots fall back to the
/// worst clusters overall instead of leaving the view empty.
String renderMarkdownReport(
  GraphAnalysisResult result, {
  BaselineComparison? comparison,
  GateResult? gate,
  required bool github,
}) {
  final buf = StringBuffer()
    ..writeln(_verdictLine(result, gate))
    ..writeln();

  final selection = _selectHighlights(result, comparison);
  final highlights = selection.highlights;
  if (highlights.isNotEmpty) {
    buf
      ..writeln(
        selection.isFallback
            ? '### Top clusters (${highlights.length} of '
                  '${result.clusters.length}) — no project-anchored '
                  'clusters found'
            : '### Top project-anchor clusters '
                  '(${highlights.length} of ${result.clusters.length})',
      )
      ..writeln();
    for (var i = 0; i < highlights.length; i++) {
      _writeHighlight(buf, i + 1, highlights[i], result.anchorRollups);
    }
    _writeLargestOverallLine(buf, result, highlights);
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
    final violations = gate.violations;
    // A failed gate should always carry at least one violation string, but
    // a hand-built or future GateResult might not — degrade to an honest
    // fallback rather than crashing on `.first` of an empty list.
    return violations.isEmpty
        ? '❌ gate failed (no violation details available)'
        : '❌ gate failed: ${violations.first}';
  }
  if (result.clusters.isEmpty) return '✅ no leak clusters';
  final count = result.clusters.length;
  return gate != null
      ? '✅ $count clusters (gate passed)'
      : '⚠ $count clusters (no gate)';
}

/// One current cluster paired with its baseline classification, when known.
typedef _Highlight = ({GraphLeakCluster cluster, ClusterDelta? delta});

/// The featured clusters plus whether they came from the project-anchor tier
/// or the any-origin fallback tier (see [_selectHighlights]).
typedef _HighlightSelection = ({List<_Highlight> highlights, bool isFallback});

/// Picks at most 3 clusters to feature above the fold.
///
/// Project-anchored clusters are always preferred: NEW ones first (largest
/// first), then the worst (largest shallow bytes) of the rest — so a
/// reviewer always sees either what's new or what's biggest in their own
/// code, never neither. When there is NOT a single project-anchored cluster
/// in the whole run, the same NEW-or-worst ranking runs over every cluster
/// regardless of origin instead, so the featured section is never left empty
/// while [GraphAnalysisResult.clusters] is non-empty (a dependency-only run,
/// e.g. one dominated by native-heap growth in a package like
/// `flutter_webrtc`, still gets a usable 30-second view).
_HighlightSelection _selectHighlights(
  GraphAnalysisResult result,
  BaselineComparison? comparison,
) {
  final deltaBySignature = <String, ClusterDelta>{
    if (comparison != null && comparison.baselineComparable)
      for (final d in comparison.deltas) d.cluster.signature: d,
  };

  List<_Highlight> candidatesWhere(bool Function(GraphLeakCluster) keep) => [
    for (final cluster in result.clusters)
      if (keep(cluster))
        (cluster: cluster, delta: deltaBySignature[cluster.signature]),
  ];

  final projectCandidates = candidatesWhere(
    (c) => _originOf(c, result.anchorRollups) == ClassOrigin.project,
  );
  if (projectCandidates.isNotEmpty) {
    return (highlights: _topByNewOrWorst(projectCandidates), isFallback: false);
  }

  return (
    highlights: _topByNewOrWorst(candidatesWhere((_) => true)),
    isFallback: true,
  );
}

/// Sorts [candidates] NEW-first (largest first), then by shallow bytes
/// descending, and returns at most the top 3.
///
/// The final tiebreaker (signature, ascending) makes the order fully
/// deterministic even when two clusters tie on both bytes and instance
/// count — `List.sort` gives no stability guarantee, so without this the
/// featured order (and thus which 3 clusters get shown) could vary between
/// otherwise-identical runs.
List<_Highlight> _topByNewOrWorst(List<_Highlight> candidates) {
  final sorted = [...candidates]
    ..sort((a, b) {
      final aNew = a.delta?.novelty == ClusterNovelty.newCluster;
      final bNew = b.delta?.novelty == ClusterNovelty.newCluster;
      if (aNew != bNew) return aNew ? -1 : 1;
      final byBytes = b.cluster.retainedShallowBytes.compareTo(
        a.cluster.retainedShallowBytes,
      );
      if (byBytes != 0) return byBytes;
      final byInstances = b.cluster.instanceCount.compareTo(
        a.cluster.instanceCount,
      );
      if (byInstances != 0) return byInstances;
      return a.cluster.signature.compareTo(b.cluster.signature);
    });
  return sorted.take(3).toList();
}

/// Appends the single "largest overall" line when the overall-worst cluster
/// (by shallow bytes alone, any origin, ignoring novelty) isn't one of the
/// already-[highlights]ed clusters — so a huge dependency/framework/SDK leak
/// can never hide silently behind smaller featured project clusters.
void _writeLargestOverallLine(
  StringBuffer buf,
  GraphAnalysisResult result,
  List<_Highlight> highlights,
) {
  final worst = _worstOverall(result.clusters);
  if (worst == null) return;

  final featured = {for (final h in highlights) h.cluster.signature};
  if (featured.contains(worst.signature)) return;

  final origin = _originOf(worst, result.anchorRollups);
  buf.writeln(
    'largest overall: `${_escapeCode(worst.className)}` '
    '${_originLabel(origin)} — ${worst.instanceCount} instances, '
    '${_kbShallow(worst.retainedShallowBytes)} (see details)',
  );
  buf.writeln();
}

/// The cluster with the largest [GraphLeakCluster.retainedShallowBytes], or
/// null when [clusters] is empty. Ties keep the first one encountered.
GraphLeakCluster? _worstOverall(List<GraphLeakCluster> clusters) {
  GraphLeakCluster? worst;
  for (final cluster in clusters) {
    if (worst == null ||
        cluster.retainedShallowBytes > worst.retainedShallowBytes) {
      worst = cluster;
    }
  }
  return worst;
}

/// Formats [bytes] as whole kilobytes, still carrying the "shallow"
/// qualifier — this one summary line reads better in KB than in raw bytes,
/// but must stay just as honest about what it's measuring.
String _kbShallow(int bytes) => '${(bytes / 1024).round()} KB shallow';

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
      '**$rank. ${_escapePlain(cluster.className)}** — '
      '`${_escapeCode(package)}` ${_originLabel(origin)}',
    )
    ..writeln(
      '- ${cluster.instanceCount} instances retained, '
      '${cluster.retainedShallowBytes} B shallow',
    );

  final anchorLine = _anchorLine(cluster);
  if (anchorLine != null) {
    buf.writeln('- $anchorLine');
  }

  final delta = highlight.delta;
  if (delta != null && delta.novelty == ClusterNovelty.newCluster) {
    final nearest = delta.nearestKnownSignature;
    buf.writeln(
      nearest == null
          ? '- 🆕 new cluster'
          : '- 🆕 new cluster — nearest known: `${_escapeCode(nearest)}`',
    );
  } else if (delta != null && delta.novelty == ClusterNovelty.grown) {
    buf.writeln(
      '- 📈 grown by +${delta.instanceDelta} instances, '
      '+${delta.bytesDelta} B shallow',
    );
  }
  buf.writeln();
}

/// Describes where the caller's own code holds the leak, or null when there
/// is nothing honest to say.
///
/// When [GraphLeakCluster.anchorHopIndex] names an app-owned hop, this is the
/// field on that hop's class that leads onward to the leaked object (a
/// [GraphHop]'s `field`/`index` label the edge INTO it, so the anchor's own
/// holding field lives on the NEXT hop). When there is no anchor — the
/// leaked object IS the app class, with no internal SDK leaf underneath it —
/// this instead names the retaining root kind, since there is no field to
/// point to. A negative index can never be produced by the analyzer, but
/// [GraphLeakCluster.fromJson] accepts any int and this function is
/// reachable from a public API — rather than crash indexing
/// `hops[anchorIndex]` with a negative index, this degrades to omitting the
/// line entirely (the caller drops the bullet rather than showing it).
String? _anchorLine(GraphLeakCluster cluster) {
  final anchorIndex = cluster.anchorHopIndex;
  if (anchorIndex == null) {
    return 'your code retains this `${_escapeCode(cluster.className)}` '
        'instance directly via a ${cluster.rootKind.label} root';
  }
  if (anchorIndex < 0) return null;

  final hops = cluster.representativePath.hops;
  final anchorClassName = anchorIndex < hops.length
      ? hops[anchorIndex].className
      : cluster.className;
  final holdsAt = anchorIndex + 1 < hops.length
      ? _fieldLabel(hops[anchorIndex + 1])
      : null;

  final escapedClassName = _escapeCode(anchorClassName);
  return holdsAt == null
      ? 'your code holds this via `$escapedClassName`'
      : 'your code holds it at `$escapedClassName.${_escapeCode(holdsAt)}`';
}

String? _fieldLabel(GraphHop hop) {
  if (hop.field != null) return hop.field;
  if (hop.index != null) return '[${hop.index}]';
  return null;
}

String? _packageOf(Uri? libraryUri) =>
    libraryUri == null ? null : _packageNameOf.packageOf(libraryUri);

/// Escapes [text] for a plain (non-code-span) markdown position: a bold
/// headline or a table cell.
///
/// Class/package names come straight from the analyzed heap — an unresolved
/// VM class can render as a literal `<unknown>`, and a generic type's own
/// name can contain `<>` too. Left unescaped, GitHub's HTML sanitizer treats
/// `<...>` as a tag and silently strips it — the exact failure mode that
/// made the top suspect's name vanish above the fold. `|` is escaped
/// separately because it would otherwise open a spurious extra cell in a
/// markdown table row.
String _escapePlain(String text) =>
    text.replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('|', r'\|');

/// Escapes [text] for placement inside a single backtick code span.
///
/// A backtick can never legitimately appear in a Dart identifier, so a
/// stray one — only reachable from malformed/adversarial input, e.g. a
/// hand-built `nearestKnownSignature` — is replaced rather than allowed to
/// terminate the span early and corrupt everything that follows it.
String _escapeCode(String text) => text.replaceAll('`', "'");

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
        '| ${_escapePlain(cluster.className)} | ${_escapePlain(package)} | '
        '${_originLabel(origin)} | ${cluster.instanceCount} | '
        '${cluster.retainedShallowBytes} B shallow | '
        '${cluster.rootKind.label} | ${cluster.confidence.name} |',
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
      '| ${_escapePlain(rollup.package)} | ${_originLabel(rollup.origin)} | '
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
        '| ${_escapePlain(gone.className)} | ${_escapePlain(gone.signature)} '
        '| ${gone.instanceCount} | ${gone.retainedShallowBytes} B shallow |',
      );
    }
  }
  buf.writeln();
  buf.writeln('</details>');
  buf.writeln();
}
