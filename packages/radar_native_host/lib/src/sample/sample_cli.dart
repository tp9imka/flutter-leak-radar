import 'dart:async';
import 'dart:io';

import 'package:radar_native/radar_native.dart';

import '../capture/adb_runner.dart';
import 'fd_sampler.dart';
import 'gfxinfo_sampler.dart';
import 'meminfo_sampler.dart';
import 'proc_status_sampler.dart';
import 'sample_clock.dart';
import 'sample_snapshot.dart';
import 'session_store.dart';
import 'thread_sampler.dart';

/// Exit codes, matching the `symbolize` verb contract.
const int _exitOk = 0;
const int _exitToolFailure = 1;
const int _exitUsage = 2;

/// Longest an outage backoff ever grows to, so even during a device outage the
/// loop probes at least once a minute and keeps flushing.
const Duration _maxOutageBackoff = Duration(seconds: 60);

/// Bound on a single `pidof` probe. A wedged device can leave `adb shell`
/// hanging indefinitely; without this bound one stuck probe would freeze the
/// whole overnight session — no ticks, no flushes, and an interrupt could not
/// even break in. A timed-out probe is treated as a device outage.
const Duration _probeTimeout = Duration(seconds: 10);

/// Bound on one sampling sweep. A hung `dumpsys` never throws, so the composite
/// would await forever; a timed-out sweep degrades to an unmeasured tick and
/// the loop continues.
const Duration _sampleTimeout = Duration(seconds: 20);

/// How many consecutive periodic-flush failures the loop rides through before
/// giving up.
///
/// A single flush failure is almost always transient — a brief disk-full, an
/// FS hiccup, momentary lock contention — and the in-memory builder still holds
/// the whole night, so the very next flush recovers everything. Ending the run
/// on the first blip would abandon hours of otherwise-capturable data. Only a
/// sustained run of failures signals a genuinely dead sink worth stopping for.
const int _maxConsecutiveFlushFailures = 5;

/// adb-daemon-level phrases in stderr that mean *the device is gone*, as
/// opposed to a per-command failure while the device is present (a dead pid, a
/// permission denial). Kept deliberately specific — daemon phrasing, never a
/// bare word like `not found` that a shell error could also contain.
const List<String> _deviceGoneMarkers = [
  'no devices/emulators found',
  'device offline',
  "device '",
  'device unauthorized',
  'device still authorizing',
  'error: closed',
  'cannot connect to daemon',
  'protocol fault',
  'connection reset',
];

/// Builds the default Lane A [CompositeSampler] over the five read-only
/// samplers, scoped to [serial].
NativeSampler _defaultSampler(AdbRunner adb, String? serial) =>
    CompositeSampler([
      MeminfoSampler(adb, serial: serial),
      ProcStatusSampler(adb, serial: serial),
      FdSampler(adb, serial: serial),
      ThreadSampler(adb, serial: serial),
      GfxinfoSampler(adb, serial: serial),
    ]);

/// Runs `radar_sample`: resolves the target pid via `adb pidof`, samples Lane A
/// columns on a fixed cadence into `session_dir/timeline.json`, and survives
/// the ways an overnight run breaks — a per-command failure, a device
/// disconnect, an app restart, an operator Ctrl-C.
///
/// ```
/// radar_sample --package com.example.app [--device SERIAL]
///   [--interval 5s] [--duration 8h] --out session_dir/ [--flush-every 60s]
/// ```
///
/// Robustness contract, honoured so every hole in the data is labelled:
/// - a single failed `adb` command → that tick's columns read *not measured*
///   (a gap), sampling continues (this is [CompositeSampler]'s throw isolation);
/// - a device disconnect → an explicit unmeasured tick per retry, a
///   backoff-growing probe loop logged to stderr, and one coalesced gap over
///   the whole outage — never a silent time-hole;
/// - a pid change after the app restarts → a `process-restart (pid X→Y)` mark
///   plus a gap tick, then sampling resumes on the new pid;
/// - a flush every `--flush-every`, so a crash loses at most one interval;
/// - SIGINT/SIGTERM → a final flush and exit 0: an interrupted overnight
///   session is still a valid session.
///
/// [adb], [clock], [buildSampler], [lock], and [interrupts] are injectable
/// seams; when omitted, real process/OS-backed implementations are used. [now]
/// stamps the session start (defaults to [DateTime.now]).
Future<int> runSample(
  List<String> args, {
  AdbRunner? adb,
  SampleClock? clock,
  NativeSampler Function(AdbRunner adb, String? serial)? buildSampler,
  SessionLock? lock,
  Stream<ProcessSignal>? interrupts,
  Map<String, String>? env,
  Duration? probeTimeout,
  Duration? sampleTimeout,
  StringSink? out,
  StringSink? err,
}) async {
  final outSink = out ?? stdout;
  final errSink = err ?? stderr;
  final effectiveEnv = env ?? Platform.environment;

  final SampleArgs parsed;
  try {
    parsed = parseSampleArgs(args, env: effectiveEnv);
  } on FormatException catch (e) {
    errSink.writeln(e.message);
    return _exitUsage;
  }

  final effectiveAdb = adb ?? const ProcessAdbRunner();
  final effectiveClock = clock ?? const SystemSampleClock();
  final effectiveProbeTimeout = probeTimeout ?? _probeTimeout;
  // An omitted --device resolves the real serial once at start, both to pin
  // sampling to that device and to record honest provenance; a failure falls
  // back to null (sole-device scoping) and 'default' in meta.
  final effectiveSerial =
      parsed.serial ??
      await _resolveSerial(effectiveAdb, effectiveProbeTimeout, errSink);
  final sampler = (buildSampler ?? _defaultSampler)(
    effectiveAdb,
    effectiveSerial,
  );
  final store = SessionStore(
    dir: parsed.outDir,
    lock: lock ?? FileSessionLock('${parsed.outDir}/.session.lock'),
  );
  final builder = TimelineBuilder(nowMicros: effectiveClock.nowMicros);
  var meta = SessionMeta(
    package: parsed.package,
    device: effectiveSerial ?? 'default',
    started: _toUtc(effectiveClock.nowMicros()),
    intervalMicros: parsed.interval.inMicroseconds,
    durationMicros: parsed.duration.inMicroseconds,
    flushEveryMicros: parsed.flushEvery.inMicroseconds,
  );

  try {
    await store.writeMeta(meta);
  } catch (error) {
    errSink.writeln(
      'radar_sample: cannot write session to ${parsed.outDir}: '
      '$error',
    );
    return _exitToolFailure;
  }

  final interrupt = _InterruptWatch(interrupts, errSink);

  var endReason = 'completed';
  try {
    await _sampleLoop(
      args: parsed,
      serial: effectiveSerial,
      adb: effectiveAdb,
      clock: effectiveClock,
      sampler: sampler,
      store: store,
      builder: builder,
      interrupt: interrupt,
      probeTimeout: effectiveProbeTimeout,
      sampleTimeout: sampleTimeout ?? _sampleTimeout,
      err: errSink,
    );
    if (interrupt.tripped) endReason = 'interrupted';
  } on _FlushGaveUpException catch (e) {
    // A handled outcome, not a crash: the loop already logged each failure and
    // the in-memory builder still holds the whole session for the strict final
    // flush below. No stack dump.
    endReason = 'error';
    errSink.writeln('radar_sample: $e — ending session');
  } catch (error, stack) {
    // The loop degrades internally; reaching here is genuinely unforeseen. The
    // session so far is still valid, so finalise it rather than lose it.
    endReason = 'error';
    errSink.writeln('radar_sample: unexpected error: $error\n$stack');
  } finally {
    await interrupt.cancel();
  }

  meta = meta.ended(_toUtc(effectiveClock.nowMicros()), endReason);
  try {
    await finalizeSession(store, builder, meta);
  } catch (error) {
    errSink.writeln('radar_sample: failed to finalise session: $error');
    return _exitToolFailure;
  }

  final timeline = builder.build();
  outSink.writeln(
    '${parsed.outDir} — ${_countSamples(timeline)} samples, '
    '${timeline.marks.length} marks, ended $endReason',
  );
  return _exitOk;
}

/// Writes the final `timeline.json` and end-stamped `meta.json` — the extracted
/// cleanup the loop, the interrupt path, and the tests all share, so an
/// interrupted session flushes exactly like a completed one.
Future<void> finalizeSession(
  SessionStore store,
  TimelineBuilder builder,
  SessionMeta meta,
) async {
  await store.flushTimeline(builder.build());
  await store.writeMeta(meta);
}

DateTime _toUtc(int micros) =>
    DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);

int _countSamples(TriageTimeline timeline) =>
    timeline.columns.values.fold(0, (sum, s) => sum + s.samples.length);

/// The overnight sampling loop. Extracted from [runSample] so the orchestration
/// (arg parsing, finalisation, exit codes) stays readable.
Future<void> _sampleLoop({
  required SampleArgs args,
  required String? serial,
  required AdbRunner adb,
  required SampleClock clock,
  required NativeSampler sampler,
  required SessionStore store,
  required TimelineBuilder builder,
  required _InterruptWatch interrupt,
  required Duration probeTimeout,
  required Duration sampleTimeout,
  required StringSink err,
}) async {
  final startMicros = clock.nowMicros();
  final deadlineMicros = startMicros + args.duration.inMicroseconds;
  final columns = sampler.columns;
  var lastFlushMicros = startMicros;
  int? lastPid;
  var consecutiveOutages = 0;
  var consecutiveFlushFailures = 0;

  while (!interrupt.tripped && clock.nowMicros() < deadlineMicros) {
    final nowMicros = clock.nowMicros();
    var wait = args.interval;

    final probe = await _resolvePid(adb, args.package, serial, probeTimeout);
    switch (probe) {
      case _Outage(:final reason):
        consecutiveOutages++;
        builder.add(_unmeasuredTick(nowMicros, columns, reason));
        err.writeln(
          'radar_sample: device unreachable ($reason) — retry '
          '#$consecutiveOutages, backing off',
        );
        wait = _outageBackoff(consecutiveOutages, args.interval);
      case _NoProcess(:final reason):
        consecutiveOutages = 0;
        builder.add(_unmeasuredTick(nowMicros, columns, reason));
      case _Resolved(:final pid):
        consecutiveOutages = 0;
        if (lastPid != null && pid != lastPid) {
          builder.addMark('process-restart (pid $lastPid→$pid)');
          builder.add(
            _unmeasuredTick(
              nowMicros,
              columns,
              'process restarted (pid $lastPid→$pid)',
            ),
          );
          lastPid = pid;
        } else {
          Map<TriageColumn, SampleValue> values;
          try {
            values = await sampler
                .sample(args.package, pid)
                .timeout(sampleTimeout);
          } on TimeoutException {
            values = allUnmeasured(
              columns,
              'sampling timed out after ${sampleTimeout.inSeconds}s',
            );
          }
          builder.add(NativeSampleSnapshot(tMicros: nowMicros, values: values));
          lastPid = pid;
        }
    }

    if (nowMicros - lastFlushMicros >= args.flushEvery.inMicroseconds) {
      // Ride through a transient flush failure: the in-memory builder still
      // holds everything, so the next flush recovers it. lastFlushMicros is
      // NOT advanced on failure, so the next tick retries promptly. Only a
      // sustained run of failures ends the night.
      try {
        await store.flushTimeline(builder.build());
        lastFlushMicros = nowMicros;
        consecutiveFlushFailures = 0;
      } catch (error) {
        consecutiveFlushFailures++;
        err.writeln(
          'radar_sample: periodic flush failed '
          '(#$consecutiveFlushFailures/$_maxConsecutiveFlushFailures): '
          '$error — retrying next interval',
        );
        if (consecutiveFlushFailures >= _maxConsecutiveFlushFailures) {
          throw _FlushGaveUpException(consecutiveFlushFailures);
        }
      }
    }

    await interrupt.sleepOr(clock, wait);
  }
}

/// Raised by the sampling loop once the periodic flush has failed
/// [_maxConsecutiveFlushFailures] times in a row — a handled give-up, so
/// [runSample] ends the session (`endReason: 'error'`) without a stack dump and
/// still runs the strict final flush from the intact in-memory builder.
final class _FlushGaveUpException implements Exception {
  const _FlushGaveUpException(this.failures);

  /// Consecutive flush failures at the point of giving up.
  final int failures;

  @override
  String toString() =>
      'periodic flush failed $failures times in a row; the session sink '
      'appears dead';
}

NativeSampleSnapshot _unmeasuredTick(
  int tMicros,
  Set<TriageColumn> columns,
  String reason,
) => NativeSampleSnapshot(
  tMicros: tMicros,
  values: allUnmeasured(columns, reason),
);

/// Exponential backoff for a device outage: `interval * 2^(n-1)`, capped at
/// [_maxOutageBackoff] and never below [interval].
Duration _outageBackoff(int consecutive, Duration interval) {
  final shift = (consecutive - 1).clamp(0, 20);
  final micros = interval.inMicroseconds << shift;
  if (micros <= 0 || micros > _maxOutageBackoff.inMicroseconds) {
    return _maxOutageBackoff.inMicroseconds < interval.inMicroseconds
        ? interval
        : _maxOutageBackoff;
  }
  return Duration(microseconds: micros);
}

/// The outcome of one `adb pidof` probe.
sealed class _PidProbe {
  const _PidProbe();
}

/// The pid resolved to [pid].
final class _Resolved extends _PidProbe {
  const _Resolved(this.pid);
  final int pid;
}

/// The device is present but the process is not running ([reason]) — a dead
/// pid, not an outage: the tick is unmeasured but the loop does not back off.
final class _NoProcess extends _PidProbe {
  const _NoProcess(this.reason);
  final String reason;
}

/// The device itself is unreachable ([reason]) — an outage: the tick is
/// unmeasured and the loop backs off before retrying.
final class _Outage extends _PidProbe {
  const _Outage(this.reason);
  final String reason;
}

/// Resolves the connected device's serial via `adb get-serialno` for meta
/// provenance and to pin sampling to that device.
///
/// `get-serialno` prints the serial for exactly one device and errors on none
/// or several. Any failure — no device, several devices, a launch failure, a
/// timeout, or the sentinel `unknown` — falls back to null (sole-device
/// scoping), with one honest line to [err]. Never throws.
Future<String?> _resolveSerial(
  AdbRunner adb,
  Duration probeTimeout,
  StringSink err,
) async {
  try {
    final result = await adb.run(['get-serialno']).timeout(probeTimeout);
    final serial = result.stdout.trim();
    if (result.ok && serial.isNotEmpty && serial != 'unknown') return serial;
  } catch (_) {
    // Fall through to the honest default below.
  }
  err.writeln(
    'radar_sample: could not resolve a device serial via '
    '`adb get-serialno` — recording device as "default"',
  );
  return null;
}

/// Resolves [package]'s pid via `adb shell pidof -s`, classifying the outcome.
///
/// Robust to both adb variants: modern adb propagates the shell exit code while
/// older adb always exits 0, so the pid is read from stdout regardless of exit
/// code. A device-gone daemon error (checked first) is an [_Outage]; a present
/// device with no matching process is a [_NoProcess]; a launch failure
/// ([ProcessException], e.g. `adb` absent) is an [_Outage] so the loop keeps
/// retrying rather than aborting the night.
Future<_PidProbe> _resolvePid(
  AdbRunner adb,
  String package,
  String? serial,
  Duration probeTimeout,
) async {
  AdbResult result;
  try {
    result = await adb
        .run(['shell', 'pidof', '-s', package], serial: serial)
        .timeout(probeTimeout);
  } on TimeoutException {
    return _Outage('pidof probe timed out after ${probeTimeout.inSeconds}s');
  } on ProcessException catch (e) {
    return _Outage('adb launch failed: ${e.message}');
  } catch (e) {
    return _Outage('adb error: $e');
  }

  final stderrLower = result.stderr.toLowerCase();
  if (_deviceGoneMarkers.any(stderrLower.contains)) {
    return _Outage('device unreachable: ${result.stderr.trim()}');
  }

  final pid = _firstPid(result.stdout);
  if (pid != null) return _Resolved(pid);
  return const _NoProcess('process not running (pidof returned no pid)');
}

/// The first positive integer token in [stdout] (`pidof -s` prints one pid), or
/// null when the output is empty/whitespace.
int? _firstPid(String stdout) {
  for (final token in stdout.trim().split(RegExp(r'\s+'))) {
    final value = int.tryParse(token);
    if (value != null && value > 0) return value;
  }
  return null;
}

/// Merges SIGINT/SIGTERM into a single trip flag + a future the sleep races
/// against, so a Ctrl-C mid-delay wakes the loop promptly instead of waiting
/// out a 60-second backoff.
final class _InterruptWatch {
  _InterruptWatch(Stream<ProcessSignal>? injected, this._err) {
    final streams = injected != null ? [injected] : _realSignals();
    for (final stream in streams) {
      _subs.add(stream.listen(_onSignal));
    }
  }

  final StringSink _err;
  final Completer<void> _completer = Completer<void>();
  final List<StreamSubscription<ProcessSignal>> _subs = [];
  bool tripped = false;

  static List<Stream<ProcessSignal>> _realSignals() {
    final streams = <Stream<ProcessSignal>>[];
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      try {
        streams.add(signal.watch());
      } catch (_) {
        // Signal unsupported on this platform (e.g. SIGTERM on Windows).
      }
    }
    return streams;
  }

  void _onSignal(ProcessSignal signal) {
    if (tripped) return;
    tripped = true;
    _err.writeln('radar_sample: interrupted ($signal) — finalising session');
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Waits for [wait], or returns early if an interrupt trips first.
  Future<void> sleepOr(SampleClock clock, Duration wait) =>
      Future.any([clock.delay(wait), _completer.future]);

  /// Cancels signal subscriptions.
  Future<void> cancel() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
  }
}

/// Parsed, validated `radar_sample` flags.
final class SampleArgs {
  /// Creates a parsed argument set.
  const SampleArgs({
    required this.package,
    required this.serial,
    required this.interval,
    required this.duration,
    required this.outDir,
    required this.flushEvery,
  });

  /// Target package name.
  final String package;

  /// Target device serial, or null for the sole connected device.
  final String? serial;

  /// Inter-sample interval.
  final Duration interval;

  /// Total session duration.
  final Duration duration;

  /// Output session directory.
  final String outDir;

  /// Flush cadence.
  final Duration flushEvery;
}

/// Parses `radar_sample` flags, applying defaults and `--device`'s
/// `ANDROID_SERIAL` env fallback.
///
/// Throws [FormatException] with an actionable message on an unknown flag, a
/// flag missing its value, a bad duration, or a missing `--package`/`--out`.
SampleArgs parseSampleArgs(
  List<String> args, {
  Map<String, String> env = const {},
}) {
  String? package;
  String? serial;
  String? outDir;
  var interval = const Duration(seconds: 5);
  var duration = const Duration(hours: 8);
  var flushEvery = const Duration(seconds: 60);

  var i = 0;
  String next(String flag) {
    if (i + 1 >= args.length) {
      throw FormatException('$flag requires a value');
    }
    i++;
    return args[i];
  }

  while (i < args.length) {
    final arg = args[i];
    switch (arg) {
      case '--package':
        package = next(arg);
      case '--device':
        serial = next(arg);
      case '--interval':
        interval = _parseDuration(next(arg));
      case '--duration':
        duration = _parseDuration(next(arg));
      case '--out':
        outDir = next(arg);
      case '--flush-every':
        flushEvery = _parseDuration(next(arg));
      default:
        throw FormatException('Unknown argument: $arg');
    }
    i++;
  }

  if (package == null) {
    throw const FormatException('Missing required --package <name>');
  }
  if (outDir == null) {
    throw const FormatException('Missing required --out <session_dir>');
  }
  if (interval <= Duration.zero) {
    throw const FormatException('--interval must be positive');
  }
  if (flushEvery <= Duration.zero) {
    throw const FormatException('--flush-every must be positive');
  }

  return SampleArgs(
    package: package,
    serial: serial ?? env['ANDROID_SERIAL'],
    interval: interval,
    duration: duration,
    outDir: outDir,
    flushEvery: flushEvery,
  );
}

/// Parses a duration like `5s`, `60s`, `8h`, `500ms`, or a bare seconds count.
///
/// Throws [FormatException] on anything else, including a negative value.
Duration _parseDuration(String raw) {
  final match = RegExp(r'^(\d+)(ms|s|m|h)?$').firstMatch(raw.trim());
  if (match == null) {
    throw FormatException('not a duration (e.g. 5s, 8h, 500ms): "$raw"');
  }
  final value = int.parse(match.group(1)!);
  return switch (match.group(2)) {
    'ms' => Duration(milliseconds: value),
    'm' => Duration(minutes: value),
    'h' => Duration(hours: value),
    _ => Duration(seconds: value),
  };
}
