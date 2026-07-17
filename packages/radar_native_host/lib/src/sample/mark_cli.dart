import 'dart:io';

import 'sample_clock.dart';
import 'session_store.dart';

/// Exit codes — the initiative-wide contract (see `radar_ci`'s `GateExit`):
/// 0 ok / 1 usage error / 2 tool failure.
const int _exitOk = 0;
const int _exitUsage = 1;
const int _exitToolFailure = 2;

/// Runs `radar_mark`: appends a labelled [TriageMark] to a live session's
/// `timeline.json`.
///
/// ```
/// radar_mark --session session_dir/ "reconnect"
/// ```
///
/// Safe to run against a session `radar_sample` is actively flushing: the
/// append takes the same session lock and re-reads the current timeline inside
/// it, so it never clobbers snapshots a concurrent flush just wrote.
///
/// [lock] and [clock] are injectable seams. Returns 0 on success, 1 on a usage
/// error (missing `--session`/label), 2 on a tool failure (a corrupt or
/// unwritable `timeline.json`).
Future<int> runMark(
  List<String> args, {
  SessionLock? lock,
  SampleClock? clock,
  StringSink? out,
  StringSink? err,
}) async {
  final outSink = out ?? stdout;
  final errSink = err ?? stderr;

  String? session;
  String? label;

  var i = 0;
  String next(String flag) {
    if (i + 1 >= args.length) {
      errSink.writeln('$flag requires a value');
      return '';
    }
    i++;
    return args[i];
  }

  while (i < args.length) {
    final arg = args[i];
    if (arg == '--session') {
      session = next(arg);
    } else if (arg.startsWith('--')) {
      errSink.writeln('Unknown argument: $arg');
      return _exitUsage;
    } else if (label == null) {
      label = arg;
    } else {
      errSink.writeln('Unexpected extra argument: $arg');
      return _exitUsage;
    }
    i++;
  }

  if (session == null || session.isEmpty) {
    errSink.writeln('Missing required --session <session_dir>');
    return _exitUsage;
  }
  if (label == null || label.isEmpty) {
    errSink.writeln(
      'Missing required label — usage: '
      'radar_mark --session <dir> "<label>"',
    );
    return _exitUsage;
  }

  final effectiveClock = clock ?? const SystemSampleClock();
  final store = SessionStore(
    dir: session,
    lock: lock ?? FileSessionLock('$session/.session.lock'),
  );

  try {
    await store.appendMark(label, nowMicros: effectiveClock.nowMicros());
  } on FormatException catch (e) {
    errSink.writeln('radar_mark: corrupt timeline.json: ${e.message}');
    return _exitToolFailure;
  } catch (error) {
    errSink.writeln('radar_mark: failed to append mark: $error');
    return _exitToolFailure;
  }

  outSink.writeln('marked "$label" in $session');
  return _exitOk;
}
