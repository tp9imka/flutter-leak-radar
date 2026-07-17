import 'dart:convert';
import 'dart:io';

import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_trace/radar_trace.dart';

/// A virtual [SampleClock]: [delay] advances [nowMicros] instantly, so an
/// 8-hour cadence runs in a test without waiting, and every wait is recorded in
/// [delays] for asserting backoff growth.
final class FakeClock implements SampleClock {
  /// Creates a clock starting at [_now] microseconds.
  FakeClock([this._now = 0]);
  int _now;

  /// Every [delay] duration, in order — the loop's wait sequence.
  final List<Duration> delays = [];

  /// Invoked after each [delay] with the advanced now, so a test can observe
  /// on-disk state between ticks (e.g. to prove flush cadence).
  void Function(int nowMicros)? onAfterDelay;

  @override
  int nowMicros() => _now;

  @override
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    if (duration > Duration.zero) _now += duration.inMicroseconds;
    onAfterDelay?.call(_now);
    await Future<void>.value();
  }
}

/// An [AdbRunner] answering each `pidof` probe from [responder], keyed by
/// zero-based call index, with an optional synchronous [onCall] side effect
/// (used to inject a signal mid-loop).
final class ScriptedPidAdb implements AdbRunner {
  /// Answers call `n` with `responder(n)`; fires `onCall(n)` first.
  ScriptedPidAdb(this.responder, {this.onCall});

  /// Maps a zero-based call index to the [AdbResult] to return.
  final AdbResult Function(int call) responder;

  /// Synchronous hook fired with the call index before responding.
  final void Function(int call)? onCall;

  /// Number of [run] calls so far.
  int calls = 0;

  @override
  Future<AdbResult> run(List<String> args, {String? serial, String? stdin}) {
    final call = calls++;
    onCall?.call(call);
    return Future<AdbResult>.value(responder(call));
  }
}

/// A [NativeSampler] whose reading is chosen per pid by [reading]; by default
/// every column reads measured with the pid as its value (so different pids
/// yield distinguishable samples).
final class FakeSampler implements NativeSampler {
  /// Creates a fake over [columns] (defaults to native PSS + threads).
  FakeSampler({Set<TriageColumn>? columns, this.reading})
    : columns =
          columns ?? const {TriageColumn.nativePssKb, TriageColumn.threads};

  @override
  final Set<TriageColumn> columns;

  /// Per-pid reading override; null yields all-measured `value == pid`.
  final Map<TriageColumn, SampleValue> Function(int pid)? reading;

  /// Every pid passed to [sample], in order — proves which pid was sampled.
  final List<int> sampledPids = [];

  @override
  Future<Map<TriageColumn, SampleValue>> sample(String package, int pid) async {
    sampledPids.add(pid);
    final override = reading;
    if (override != null) return override(pid);
    return {for (final column in columns) column: SampleValue.measured(pid)};
  }
}

/// A [SessionLock] with no real OS lock: it runs bodies immediately, counts
/// [guards], and can fire a one-shot [beforeNextBody] hook before the next
/// guarded body — used to simulate a concurrent flush interleaving with a mark.
final class FakeSessionLock implements SessionLock {
  /// Creates a fake lock.
  FakeSessionLock();

  /// Number of [guard] calls.
  int guards = 0;

  /// Fired once, before the next guarded body, then cleared.
  Future<void> Function()? beforeNextBody;

  @override
  Future<T> guard<T>(Future<T> Function() body) async {
    guards++;
    final hook = beforeNextBody;
    if (hook != null) {
      beforeNextBody = null;
      await hook();
    }
    return body();
  }
}

/// A successful `pidof` result naming [pid].
AdbResult pidResult(int pid) => AdbResult(0, '$pid\n', '');

/// A present-device, no-such-process result (dead pid) — empty output.
AdbResult noProcessResult() => AdbResult(1, '', '');

/// A device-gone result carrying an adb-daemon outage marker in stderr.
AdbResult deviceGoneResult() =>
    AdbResult(1, '', 'error: no devices/emulators found');

/// A never-emitting interrupt stream, so loop tests install no real handlers.
Stream<ProcessSignal> noInterrupts() => const Stream<ProcessSignal>.empty();

/// Builds a timeline with one `nativePssKb` sample per [tMicros] and no gaps.
TriageTimeline timelineWithSamples(List<int> tMicros) => TriageTimeline(
  columns: {
    TriageColumn.nativePssKb: MetricSeries(
      name: TriageColumn.nativePssKb.name,
      unit: expectedUnit(TriageColumn.nativePssKb),
      samples: [
        for (final t in tMicros) MetricSample(tMicros: t, value: t.toDouble()),
      ],
      gaps: const [],
    ),
  },
);

/// Reads and parses `timeline.json` from session directory [dir].
TriageTimeline readTimeline(String dir) => TriageTimeline.fromJson(
  _decode(File('$dir/timeline.json').readAsStringSync()),
);

/// Reads and parses `meta.json` from session directory [dir].
Map<String, Object?> readMeta(String dir) =>
    _decode(File('$dir/meta.json').readAsStringSync());

Map<String, Object?> _decode(String raw) =>
    (jsonDecode(raw) as Map).cast<String, Object?>();

/// Sample count for [column] in [timeline] (0 if the column is absent).
int sampleCount(TriageTimeline timeline, TriageColumn column) =>
    timeline.columns[column]?.samples.length ?? 0;
