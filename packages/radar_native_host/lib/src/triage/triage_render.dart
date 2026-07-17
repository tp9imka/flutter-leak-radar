import 'package:radar_native/radar_native.dart';
import 'package:radar_trace/radar_trace.dart';

/// Where a session came from — the provenance shown atop a triage report so
/// the reader can weigh the verdict (an `interrupted` session is thinner
/// evidence than a `completed` one).
final class SessionProvenance {
  /// Creates a provenance stamp.
  const SessionProvenance({this.package, this.device, this.endReason});

  /// Reads the fields a report shows out of a raw `meta.json` map, tolerating
  /// any missing/typed-wrong field (provenance is best-effort context, never a
  /// gate).
  factory SessionProvenance.fromMetaJson(Map<String, Object?> json) =>
      SessionProvenance(
        package: json['package'] as String?,
        device: json['device'] as String?,
        endReason: json['endReason'] as String?,
      );

  /// Sampled package, if recorded.
  final String? package;

  /// Target device serial (or `'default'`), if recorded.
  final String? device;

  /// How the session ended (`completed`/`interrupted`/`error`), if recorded.
  final String? endReason;

  /// A one-line `key: value · …` summary, or null when nothing is known.
  String? get line {
    final parts = [
      if (package != null) 'package: $package',
      if (device != null) 'device: $device',
      if (endReason != null) 'ended: $endReason',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// One session's triaged result: the raw [timeline], the router [verdict] over
/// it, a display [label], and optional [provenance]. The render functions take
/// this so they never touch the filesystem — a test builds one directly.
final class TriageSession {
  /// Creates a session result.
  const TriageSession({
    required this.label,
    required this.timeline,
    required this.verdict,
    this.provenance,
  });

  /// Display label (typically the session directory name).
  final String label;

  /// The sampled timeline.
  final TriageTimeline timeline;

  /// The router verdict over [timeline].
  final TriageVerdict verdict;

  /// Optional provenance from the session's `meta.json`.
  final SessionProvenance? provenance;

  /// The assessed column → assessment map (columns absent here were never
  /// measured in this session).
  Map<TriageColumn, SeriesAssessment> get byColumn => {
    for (final a in verdict.assessments) a.column: a.assessment,
  };
}

/// Renders a single session's triage report as Markdown: the router summary
/// FIRST (the one-line answer), then a per-column verdict table over *every*
/// column — including the ones never measured, listed explicitly so an absent
/// signal is never mistaken for a flat one.
String renderTriageMarkdown(TriageSession session) {
  final buffer = StringBuffer()
    ..writeln('# Native triage: ${session.label}')
    ..writeln()
    ..writeln(
      '**${_bucketLabel(session.verdict.bucket)}** — '
      '${session.verdict.summary}',
    )
    ..writeln();

  final provenance = session.provenance?.line;
  if (provenance != null) buffer.writeln('_${provenance}_\n');

  buffer.write(renderColumnTable(session));
  return buffer.toString();
}

/// Renders the per-column verdict table for [session] — one row per
/// [TriageColumn], every never-measured column listed explicitly (so an absent
/// signal is never mistaken for a flat one), followed by a "Not measured"
/// footer when any column was never sampled.
///
/// The heading- and summary-free table body, shared by [renderTriageMarkdown]
/// and `radar_ci report`'s native section so both surfaces render the same
/// column rows.
String renderColumnTable(TriageSession session) {
  final byColumn = session.byColumn;
  final buffer = StringBuffer()
    ..writeln('| column | verdict | slope | detail |')
    ..writeln('| --- | --- | ---: | --- |');
  final notMeasured = <TriageColumn>[];
  for (final column in TriageColumn.values) {
    final assessment = byColumn[column];
    if (assessment == null) {
      notMeasured.add(column);
      buffer.writeln('| ${column.name} | not measured | — | never sampled |');
      continue;
    }
    buffer.writeln(
      '| ${column.name} | ${assessment.verdict.name} | '
      '${_slope(column, assessment)} | ${_escape(assessment.detail)} |',
    );
  }

  if (notMeasured.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(
        'Not measured (never sampled): '
        '${notMeasured.map((c) => c.name).join(', ')}.',
      );
  }
  return buffer.toString();
}

/// The JSON form of a single session's triage: the C1 [TriageVerdict.toJson]
/// under a versioned envelope carrying the session label + provenance.
Map<String, Object?> renderTriageJson(TriageSession session) => {
  'schemaVersion': 1,
  'session': session.label,
  if (session.provenance?.package != null)
    'package': session.provenance!.package,
  if (session.provenance?.endReason != null)
    'endReason': session.provenance!.endReason,
  'verdict': session.verdict.toJson(),
};

/// How one column's signal changed from the before-fix session to the
/// after-fix session — the before-vs-after loop's per-column outcome.
enum FixTransition {
  /// Grew before, no longer grows after — the fix landed.
  resolved,

  /// Grew before and still grows after — not fixed.
  persists,

  /// Bounded (plateau) before but grows after — a genuine regression against a
  /// clean baseline.
  regressed,

  /// Grows after, but the before side was noisy/insufficient (not a bounded
  /// plateau) — real growth, but can't be called a regression against an
  /// unassessable baseline.
  newlyGrowing,

  /// Measured on both sides, growing on neither — stable.
  stable,

  /// Grew before, but after is noisy/insufficient — can't confirm either way.
  inconclusive,

  /// Present before, absent after — no honest comparison possible.
  measuredBeforeOnly,

  /// Absent before, present after — no honest comparison possible.
  measuredAfterOnly,

  /// Absent on both sides — nothing to compare.
  notMeasured,
}

/// One column compared across two sessions. [before]/[after] are null when the
/// column was never measured on that side — the asymmetry a compare must stay
/// honest about rather than reading a missing side as zero.
final class ColumnComparison {
  /// Creates a comparison for [column].
  const ColumnComparison({
    required this.column,
    required this.before,
    required this.after,
  });

  /// The compared column.
  final TriageColumn column;

  /// The before-session assessment, or null when never measured there.
  final SeriesAssessment? before;

  /// The after-session assessment, or null when never measured there.
  final SeriesAssessment? after;

  /// The before→after outcome for this column.
  FixTransition get transition {
    final b = before;
    final a = after;
    if (b == null && a == null) return FixTransition.notMeasured;
    if (b == null) return FixTransition.measuredAfterOnly;
    if (a == null) return FixTransition.measuredBeforeOnly;

    final grewBefore = _grows(b);
    final growsAfter = _grows(a);
    if (grewBefore && growsAfter) return FixTransition.persists;
    if (growsAfter) {
      // After grows and before did not. Calling it a regression asserts the
      // before side was a clean baseline, so it needs a *bounded* (plateau)
      // before — the mirror of the resolved guard below. A noisy/insufficient
      // before could not vouch for "was clean", so it routes to the honest
      // newly-growing outcome instead of a false regression.
      return b.verdict == SeriesVerdict.plateau
          ? FixTransition.regressed
          : FixTransition.newlyGrowing;
    }
    if (grewBefore) {
      // A noisy/insufficient after cannot certify a fix — only a bounded
      // (plateau) after does.
      return a.verdict == SeriesVerdict.plateau
          ? FixTransition.resolved
          : FixTransition.inconclusive;
    }
    return FixTransition.stable;
  }

  /// The after-minus-before slope, only when *both* sides carry a real slope —
  /// never fabricated across a not-measured side.
  double? get slopeDelta {
    final b = before?.slopePerHour;
    final a = after?.slopePerHour;
    if (b == null || a == null) return null;
    return a - b;
  }

  static bool _grows(SeriesAssessment a) =>
      a.verdict == SeriesVerdict.monotonicGrowth && (a.slopePerHour ?? 0) > 0;
}

/// Pairs every column across [before] and [after] into a [ColumnComparison],
/// leaving each side null where that session never measured it. Ordered by
/// [TriageColumn] declaration order.
List<ColumnComparison> compareColumns(
  TriageSession before,
  TriageSession after,
) {
  final b = before.byColumn;
  final a = after.byColumn;
  return [
    for (final column in TriageColumn.values)
      if (b.containsKey(column) || a.containsKey(column))
        ColumnComparison(column: column, before: b[column], after: a[column]),
  ];
}

/// Renders the before-vs-after compare as Markdown: both router summaries, a
/// one-read "did the fix work?" verdict, a per-column outcome list, and the
/// full A-vs-B table. The outcome list never fabricates a delta across a
/// not-measured side.
String renderCompareMarkdown(TriageSession before, TriageSession after) {
  final comparisons = compareColumns(before, after);
  final buffer = StringBuffer()
    ..writeln('# Triage compare: ${before.label} → ${after.label}')
    ..writeln()
    ..writeln('**Before:** ${before.verdict.summary}')
    ..writeln()
    ..writeln('**After:** ${after.verdict.summary}')
    ..writeln()
    ..writeln('## Did the fix work?')
    ..writeln()
    ..writeln(_headline(before, after, comparisons))
    ..writeln();

  final outcomes = [
    for (final c in comparisons)
      if (_isNoteworthy(c.transition)) c,
  ];
  if (outcomes.isEmpty) {
    buffer.writeln('- No growing column on either side.');
  } else {
    for (final c in outcomes) {
      buffer.writeln('- ${_outcomeLine(c)}');
    }
  }

  buffer
    ..writeln()
    ..writeln('## Per-column: before vs after')
    ..writeln()
    ..writeln(
      '| column | before | before slope | after | after slope | '
      'Δ slope |',
    )
    ..writeln('| --- | --- | ---: | --- | ---: | ---: |');
  for (final c in comparisons) {
    buffer.writeln(
      '| ${c.column.name} | ${_verdictCell(c.before)} | '
      '${_slopeCell(c.column, c.before)} | ${_verdictCell(c.after)} | '
      '${_slopeCell(c.column, c.after)} | ${_deltaCell(c)} |',
    );
  }
  return buffer.toString();
}

/// The JSON form of a compare: both verdicts plus the per-column outcomes,
/// each carrying its honest transition and a delta only where both sides were
/// measured.
Map<String, Object?> renderCompareJson(
  TriageSession before,
  TriageSession after,
) => {
  'schemaVersion': 1,
  'before': {'session': before.label, 'verdict': before.verdict.toJson()},
  'after': {'session': after.label, 'verdict': after.verdict.toJson()},
  'columns': [
    for (final c in compareColumns(before, after))
      {
        'column': c.column.name,
        'transition': c.transition.name,
        'beforeVerdict': c.before?.verdict.name,
        'afterVerdict': c.after?.verdict.name,
        'beforeSlopePerHour': c.before?.slopePerHour,
        'afterSlopePerHour': c.after?.slopePerHour,
        'slopeDelta': c.slopeDelta,
      },
  ],
};

/// The one-read fix verdict comparing the two router buckets.
String _headline(
  TriageSession before,
  TriageSession after,
  List<ColumnComparison> comparisons,
) {
  final regressed = comparisons
      .where((c) => c.transition == FixTransition.regressed)
      .map((c) => c.column.name)
      .toList();
  final persists = comparisons
      .where((c) => c.transition == FixTransition.persists)
      .map((c) => c.column.name)
      .toList();
  final newlyGrowing = comparisons
      .where((c) => c.transition == FixTransition.newlyGrowing)
      .map((c) => c.column.name)
      .toList();

  if (persists.isNotEmpty) {
    return 'Still leaking: ${persists.join(', ')} '
        'grow in both sessions. The fix did NOT resolve it.${_caveat(comparisons)}';
  }
  if (regressed.isNotEmpty) {
    return 'Regression: ${regressed.join(', ')} '
        'now grow(s) where the before session was clean.${_caveat(comparisons)}';
  }
  if (newlyGrowing.isNotEmpty) {
    return 'New growth: ${newlyGrowing.join(', ')} grow(s) in the after '
        'session, but the before side was inconclusive there — can\'t tell a '
        'regression from a pre-existing leak the before run could not '
        'assess.${_caveat(comparisons)}';
  }
  if (before.verdict.bucket != TriageBucket.none &&
      after.verdict.bucket == TriageBucket.none) {
    return 'Resolved: the before session flagged '
        '${before.verdict.bucket.name}, the after session shows no growth. '
        'The fix appears to have worked.${_caveat(comparisons)}';
  }
  if (before.verdict.bucket == TriageBucket.none &&
      after.verdict.bucket == TriageBucket.none) {
    return 'Neither session shows monotonic growth.${_caveat(comparisons)}';
  }
  return 'No growing column persists into the after session, but confirm the '
      'columns marked inconclusive/only-measured-once below before calling it '
      'fixed.${_caveat(comparisons)}';
}

/// A trailing caveat naming every column that grew in the before session but
/// could not be confirmed in the after one — a before-only measurement or an
/// unbounded after. Without it a headline could read "resolved" while a real
/// growing signal simply went un-remeasured. Empty when nothing is unconfirmed.
String _caveat(List<ColumnComparison> comparisons) {
  final unconfirmed = [
    for (final c in comparisons)
      if ((c.transition == FixTransition.measuredBeforeOnly &&
              c.before != null &&
              ColumnComparison._grows(c.before!)) ||
          c.transition == FixTransition.inconclusive)
        c.column.name,
  ];
  if (unconfirmed.isEmpty) return '';
  return ' Caveat: ${unconfirmed.join(', ')} grew before but '
      'could not be confirmed after (not re-measured, or the after series was '
      'not bounded) — not proven fixed.';
}

bool _isNoteworthy(FixTransition t) =>
    t == FixTransition.resolved ||
    t == FixTransition.persists ||
    t == FixTransition.regressed ||
    t == FixTransition.newlyGrowing ||
    t == FixTransition.inconclusive ||
    t == FixTransition.measuredBeforeOnly ||
    t == FixTransition.measuredAfterOnly;

String _outcomeLine(ColumnComparison c) {
  final name = c.column.name;
  switch (c.transition) {
    case FixTransition.resolved:
      return '$name: ${_slopeText(c.column, c.before)} → '
          '${c.after!.verdict.name} — resolved';
    case FixTransition.persists:
      final delta = c.slopeDelta;
      final deltaText = delta == null ? '' : ' (Δ ${_signedRate(delta)})';
      return '$name: ${_slopeText(c.column, c.before)} → '
          '${_slopeText(c.column, c.after)}$deltaText — still leaking';
    case FixTransition.regressed:
      return '$name: not growing → ${_slopeText(c.column, c.after)} — '
          'regression';
    case FixTransition.newlyGrowing:
      return '$name: ${c.before!.verdict.name} before → '
          '${_slopeText(c.column, c.after)} — newly growing '
          '(before not a clean baseline)';
    case FixTransition.inconclusive:
      return '$name: ${_slopeText(c.column, c.before)} → '
          '${c.after!.verdict.name} — inconclusive (after not bounded)';
    case FixTransition.measuredBeforeOnly:
      return '$name: measured in $_beforeWord only — no after comparison';
    case FixTransition.measuredAfterOnly:
      return '$name: measured in $_afterWord only — no before comparison';
    case FixTransition.stable:
    case FixTransition.notMeasured:
      return name;
  }
}

const String _beforeWord = 'the before session';
const String _afterWord = 'the after session';

String _verdictCell(SeriesAssessment? a) =>
    a == null ? 'not measured' : a.verdict.name;

String _slopeCell(TriageColumn column, SeriesAssessment? a) =>
    a == null ? '—' : _slope(column, a);

String _slope(TriageColumn column, SeriesAssessment a) {
  final slope = a.slopePerHour;
  if (slope == null) return '—';
  return '${_signedRate(slope)} ${expectedUnit(column)}/h';
}

String _slopeText(TriageColumn column, SeriesAssessment? a) {
  if (a?.slopePerHour == null) return 'not growing';
  return '${_signedRate(a!.slopePerHour!)} ${expectedUnit(column)}/h';
}

String _deltaCell(ColumnComparison c) {
  final delta = c.slopeDelta;
  if (delta == null) {
    // Honest asymmetry: one side was not measured — no delta exists.
    return c.before == null || c.after == null ? 'n/a' : '—';
  }
  return _signedRate(delta);
}

/// A signed per-hour rate, magnitude-scaled for readability.
String _signedRate(double value) {
  final magnitude = value.abs();
  final String text;
  if (magnitude >= 100) {
    text = value.toStringAsFixed(0);
  } else if (magnitude >= 10) {
    text = value.toStringAsFixed(1);
  } else {
    text = value.toStringAsFixed(2);
  }
  return value >= 0 ? '+$text' : text;
}

String _bucketLabel(TriageBucket bucket) =>
    bucket == TriageBucket.none ? 'no leak bucket' : bucket.name;

/// Escapes the pipe so a detail string can't break the Markdown table.
String _escape(String detail) => detail.replaceAll('|', r'\|');
