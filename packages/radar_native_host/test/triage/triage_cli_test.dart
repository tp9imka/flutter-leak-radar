import 'dart:convert';
import 'dart:io';

import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

import 'triage_test_support.dart';

/// Writes a session directory with a `timeline.json` (and optional
/// `meta.json`), returning its path. Cleaned up via [addTearDown].
String _writeSession(TriageTimeline timeline, {Map<String, Object?>? meta}) {
  final dir = Directory.systemTemp.createTempSync('radar_triage_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  File(
    '${dir.path}/timeline.json',
  ).writeAsStringSync(jsonEncode(timeline.toJson()));
  if (meta != null) {
    File('${dir.path}/meta.json').writeAsStringSync(jsonEncode(meta));
  }
  return dir.path;
}

void main() {
  group('runTriage (single session)', () {
    test('md: summary first, full column table, not-measured listed', () async {
      final dir = _writeSession(
        TriageTimeline(
          columns: {TriageColumn.nativePssKb: growingSeries('native', 'kb')},
        ),
        meta: {'package': 'com.x', 'device': 'DEV1', 'endReason': 'completed'},
      );
      final out = StringBuffer();

      final code = await runTriage([dir], out: out, err: StringBuffer());

      expect(code, 0);
      final md = out.toString();
      final summaryIndex = md.indexOf('nativeMalloc');
      final tableIndex = md.indexOf('| column | verdict |');
      expect(summaryIndex, greaterThanOrEqualTo(0));
      expect(tableIndex, greaterThan(summaryIndex));
      expect(md, contains('nativePssKb | monotonicGrowth'));
      expect(md, contains('graphicsKb | not measured'));
      expect(md, contains('package: com.x'));
      expect(md, contains('ended: completed'));
    });

    test('json: verdict envelope with schemaVersion', () async {
      final dir = _writeSession(
        TriageTimeline(
          columns: {TriageColumn.nativePssKb: growingSeries('native', 'kb')},
        ),
      );
      final out = StringBuffer();

      final code = await runTriage(
        [dir, '--format', 'json'],
        out: out,
        err: StringBuffer(),
      );

      expect(code, 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['schemaVersion'], 1);
      final verdict = json['verdict'] as Map<String, Object?>;
      expect(verdict['bucket'], 'nativeMalloc');
    });

    test(
      'missing timeline.json: exit 1 (usage) naming the directory',
      () async {
        final dir = Directory.systemTemp.createTempSync('radar_triage_empty_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final err = StringBuffer();

        final code = await runTriage([dir.path], err: err);

        expect(code, 1);
        expect(err.toString(), contains('no timeline.json'));
        expect(err.toString(), contains(dir.path));
      },
    );

    test('corrupt timeline.json: exit 2 (tool failure)', () async {
      final dir = Directory.systemTemp.createTempSync('radar_triage_bad_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/timeline.json').writeAsStringSync('{ not json');
      final err = StringBuffer();

      final code = await runTriage([dir.path], err: err);

      expect(code, 2);
      expect(err.toString(), contains('corrupt'));
    });

    test('unknown --format: exit 1 (usage)', () async {
      final dir = _writeSession(const TriageTimeline());
      final err = StringBuffer();
      final code = await runTriage([dir, '--format', 'xml'], err: err);
      expect(code, 1);
      expect(err.toString(), contains('format'));
    });
  });

  group('runTriage --compare (before vs after)', () {
    test('md: one-read fix verdict — a resolved leak', () async {
      final before = _writeSession(
        TriageTimeline(
          columns: {TriageColumn.nativePssKb: growingSeries('native', 'kb')},
        ),
      );
      final after = _writeSession(
        TriageTimeline(
          columns: {TriageColumn.nativePssKb: flatSeries('native', 'kb')},
        ),
      );
      final out = StringBuffer();

      final code = await runTriage(
        [before, '--compare', after],
        out: out,
        err: StringBuffer(),
      );

      expect(code, 0);
      final md = out.toString();
      expect(md, contains('## Did the fix work?'));
      expect(md, contains('Resolved'));
      expect(md, contains('nativePssKb'));
      expect(md, contains('resolved'));
    });

    test('md: a persisting leak reads as still leaking', () async {
      final before = _writeSession(
        TriageTimeline(
          columns: {
            TriageColumn.nativePssKb: growingSeries('native', 'kb', step: 1000),
          },
        ),
      );
      final after = _writeSession(
        TriageTimeline(
          columns: {
            TriageColumn.nativePssKb: growingSeries('native', 'kb', step: 2000),
          },
        ),
      );
      final out = StringBuffer();

      final code = await runTriage(
        [before, '--compare', after],
        out: out,
        err: StringBuffer(),
      );

      expect(code, 0);
      expect(out.toString(), contains('Still leaking'));
    });

    test('a bad --compare directory: exit 1 (usage) naming it', () async {
      final before = _writeSession(const TriageTimeline());
      final err = StringBuffer();

      final code = await runTriage([
        before,
        '--compare',
        '/nonexistent/session',
      ], err: err);

      expect(code, 1);
      expect(err.toString(), contains('--compare'));
      expect(err.toString(), contains('no timeline.json'));
    });
  });
}
