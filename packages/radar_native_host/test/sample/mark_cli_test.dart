import 'dart:io';

import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

import 'overnight_test_support.dart';

/// A [SampleClock] whose [nowMicros] is fixed, so a mark's timestamp is
/// deterministic; [delay] is unused by the mark verb.
final class FixedClock implements SampleClock {
  const FixedClock(this._now);
  final int _now;

  @override
  int nowMicros() => _now;

  @override
  Future<void> delay(Duration duration) async {}
}

void main() {
  late Directory tempDir;
  late String dir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mark_cli_test_');
    dir = tempDir.path;
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<int> mark(
    List<String> args, {
    int nowMicros = 42,
    StringSink? out,
    StringSink? err,
  }) => runMark(
    args,
    lock: FakeSessionLock(),
    clock: FixedClock(nowMicros),
    out: out ?? StringBuffer(),
    err: err ?? StringBuffer(),
  );

  test('appends a mark at the clock timestamp and exits 0', () async {
    await SessionStore(
      dir: dir,
      lock: FakeSessionLock(),
    ).flushTimeline(timelineWithSamples([100]));

    final out = StringBuffer();
    final code = await mark(
      ['--session', dir, 'reconnect'],
      nowMicros: 777,
      out: out,
    );

    expect(code, 0);
    final timeline = readTimeline(dir);
    expect(timeline.marks.single.label, 'reconnect');
    expect(timeline.marks.single.tMicros, 777);
    expect(sampleCount(timeline, TriageColumn.nativePssKb), 1);
    expect(out.toString(), contains('marked "reconnect"'));
  });

  test('creates the timeline when marking a fresh session', () async {
    final code = await mark(['--session', dir, 'start']);
    expect(code, 0);
    expect(readTimeline(dir).marks.single.label, 'start');
  });

  test('missing --session returns exit 1 (usage)', () async {
    final err = StringBuffer();
    final code = await mark(['reconnect'], err: err);
    expect(code, 1);
    expect(err.toString(), contains('--session'));
  });

  test('missing label returns exit 1 (usage)', () async {
    final err = StringBuffer();
    final code = await mark(['--session', dir], err: err);
    expect(code, 1);
    expect(err.toString(), contains('label'));
  });

  test('an unknown flag returns exit 1 (usage)', () async {
    final err = StringBuffer();
    final code = await mark(['--session', dir, '--bogus', 'x'], err: err);
    expect(code, 1);
    expect(err.toString(), contains('Unknown argument'));
  });

  test('a corrupt timeline.json returns exit 2 (tool failure)', () async {
    File('$dir/timeline.json').writeAsStringSync('{ not json');
    final err = StringBuffer();
    final code = await mark(['--session', dir, 'x'], err: err);
    expect(code, 2);
    expect(err.toString(), contains('timeline.json'));
  });
}
