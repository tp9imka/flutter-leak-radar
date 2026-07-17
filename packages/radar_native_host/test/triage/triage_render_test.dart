import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

import 'triage_test_support.dart';

TriageSession _session(String label, TriageTimeline timeline) =>
    TriageSession(label: label, timeline: timeline, verdict: triage(timeline));

void main() {
  group('renderTriageMarkdown (single session)', () {
    test('puts the router summary before the column table and lists '
        'never-measured columns', () {
      final timeline = TriageTimeline(
        columns: {
          TriageColumn.nativePssKb: growingSeries('native', 'kb'),
          TriageColumn.threads: shortSeries('threads', 'count'),
        },
      );
      final session = _session('overnight', timeline);

      final md = renderTriageMarkdown(session);
      final summaryIndex = md.indexOf(session.verdict.summary);
      final tableIndex = md.indexOf('| column | verdict |');
      expect(summaryIndex, greaterThanOrEqualTo(0));
      expect(tableIndex, greaterThan(summaryIndex));

      // Every column appears; the ones never sampled read "not measured".
      expect(md, contains('nativePssKb | monotonicGrowth'));
      expect(md, contains('threads | insufficientData'));
      expect(md, contains('graphicsKb | not measured'));
      expect(md, contains('Not measured (never sampled)'));
      expect(md, contains('graphicsKb'));
    });
  });

  group('compareColumns (honest asymmetry)', () {
    test('a column measured in before but not after yields no delta', () {
      final before = _session(
        'before',
        TriageTimeline(
          columns: {
            TriageColumn.nativePssKb: growingSeries('native', 'kb'),
            TriageColumn.fdTotal: growingSeries(
              'fd',
              'count',
              base: 100,
              step: 2,
            ),
          },
        ),
      );
      final after = _session(
        'after',
        TriageTimeline(
          columns: {
            // fdTotal is absent here — measured in before only.
            TriageColumn.nativePssKb: flatSeries('native', 'kb'),
          },
        ),
      );

      final comparisons = compareColumns(before, after);
      final fd = comparisons.firstWhere(
        (c) => c.column == TriageColumn.fdTotal,
      );

      expect(fd.transition, FixTransition.measuredBeforeOnly);
      expect(fd.before, isNotNull);
      expect(fd.after, isNull);
      expect(fd.slopeDelta, isNull); // never fabricated across a missing side
    });
  });

  group('renderCompareMarkdown (before vs after)', () {
    test('a resolved leak + an honest measured-in-before-only column', () {
      final before = _session(
        'before',
        TriageTimeline(
          columns: {
            TriageColumn.nativePssKb: growingSeries('native', 'kb'),
            TriageColumn.fdTotal: growingSeries(
              'fd',
              'count',
              base: 100,
              step: 2,
            ),
          },
        ),
      );
      final after = _session(
        'after',
        TriageTimeline(
          columns: {TriageColumn.nativePssKb: flatSeries('native', 'kb')},
        ),
      );

      final md = renderCompareMarkdown(before, after);

      expect(md, contains('## Did the fix work?'));
      expect(md, contains('nativePssKb'));
      expect(md, contains('resolved'));
      // Honest asymmetry — never a fabricated delta.
      expect(md, contains('measured in the before session only'));
      expect(md, contains('n/a'));
      // fdTotal grew before but was not re-measured — the headline must not
      // claim a clean fix without flagging it.
      expect(md, contains('Caveat'));
      expect(md, contains('not proven fixed'));
      // Both router summaries present.
      expect(md, contains('**Before:**'));
      expect(md, contains('**After:**'));
    });

    test(
      'a leak that persists is called out as still leaking with a delta',
      () {
        final before = _session(
          'before',
          TriageTimeline(
            columns: {
              TriageColumn.nativePssKb: growingSeries(
                'native',
                'kb',
                step: 1000,
              ),
            },
          ),
        );
        final after = _session(
          'after',
          TriageTimeline(
            columns: {
              TriageColumn.nativePssKb: growingSeries(
                'native',
                'kb',
                step: 2000,
              ),
            },
          ),
        );

        final comparisons = compareColumns(before, after);
        final pss = comparisons.firstWhere(
          (c) => c.column == TriageColumn.nativePssKb,
        );
        expect(pss.transition, FixTransition.persists);
        expect(pss.slopeDelta, isNotNull);

        final md = renderCompareMarkdown(before, after);
        expect(md, contains('Still leaking'));
        expect(md, contains('still leaking'));
      },
    );

    test('a regression (clean before, growing after) is surfaced', () {
      final before = _session(
        'before',
        TriageTimeline(
          columns: {TriageColumn.codeKb: flatSeries('code', 'kb')},
        ),
      );
      final after = _session(
        'after',
        TriageTimeline(
          columns: {TriageColumn.codeKb: growingSeries('code', 'kb')},
        ),
      );

      final comparisons = compareColumns(before, after);
      final code = comparisons.firstWhere(
        (c) => c.column == TriageColumn.codeKb,
      );
      expect(code.transition, FixTransition.regressed);

      final md = renderCompareMarkdown(before, after);
      expect(md, contains('Regression'));
    });

    test('growing after an UNASSESSABLE before is newly-growing, never a '
        'false regression', () {
      // Insufficient-data before + growing after. Claiming "regression" would
      // assert a clean before baseline that was actually unmeasurable — the
      // mirror of over-claiming "resolved" on an unbounded after.
      final before = _session(
        'before',
        TriageTimeline(
          columns: {TriageColumn.codeKb: shortSeries('code', 'kb')},
        ),
      );
      final after = _session(
        'after',
        TriageTimeline(
          columns: {TriageColumn.codeKb: growingSeries('code', 'kb')},
        ),
      );

      final comparisons = compareColumns(before, after);
      final code = comparisons.firstWhere(
        (c) => c.column == TriageColumn.codeKb,
      );
      expect(code.before!.verdict, SeriesVerdict.insufficientData);
      expect(code.transition, FixTransition.newlyGrowing);

      final md = renderCompareMarkdown(before, after);
      expect(md, contains('New growth'));
      expect(md, contains('newly growing'));
      expect(md, isNot(contains('Regression')));
    });
  });

  group('renderCompareJson', () {
    test(
      'carries the honest transition and null delta for a one-sided column',
      () {
        final before = _session(
          'before',
          TriageTimeline(
            columns: {
              TriageColumn.fdTotal: growingSeries(
                'fd',
                'count',
                base: 100,
                step: 2,
              ),
            },
          ),
        );
        final after = _session('after', const TriageTimeline());

        final json = renderCompareJson(before, after);
        final columns = (json['columns'] as List).cast<Map<String, Object?>>();
        final fd = columns.firstWhere((c) => c['column'] == 'fdTotal');
        expect(fd['transition'], 'measuredBeforeOnly');
        expect(fd['afterVerdict'], isNull);
        expect(fd['slopeDelta'], isNull);
      },
    );
  });
}
