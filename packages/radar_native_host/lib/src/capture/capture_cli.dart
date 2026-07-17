import 'dart:io';

import 'package:radar_native/radar_native.dart';

import '../perfetto/perfetto_trace_processor_parser.dart';
import '../perfetto/trace_processor_runner.dart';
import 'adb_runner.dart';
import 'capture_preflight.dart';
import 'native_heap_capture.dart';

/// Exit codes, matching the `symbolize`/`sample` verb contract.
const int _exitOk = 0;
const int _exitToolFailure = 1;
const int _exitUsage = 2;

/// Runs `radar_capture`: gates a heapprofd capture on the device
/// preconditions, drives the capture, and then proves the pulled trace
/// actually holds heap data — so a capture that could never succeed fails
/// *before* it wastes 30s, and a capture that silently produced nothing fails
/// loudly instead of handing back an empty `.pftrace`.
///
/// ```
/// radar_capture --package com.example.app --out capture.pftrace
///   [--device SERIAL] [--mode attach|startup] [--duration 30s]
///   [--sampling-interval 4096] [--tp-bin <trace_processor>]
/// ```
///
/// Contract, each failure naming the gate that blocked it:
/// - preflight BEFORE capture — device API level >= 29
///   ([PreflightCheck.deviceApiLevel]) and the package profileable/debuggable
///   ([PreflightCheck.packageProfileable]); a failure exits 2 without ever
///   starting the capture;
/// - the capture itself runs via [NativeHeapCapture]; an `adb`-level failure
///   ([AdbException]) exits 1;
/// - post-capture VALIDATION — the trace is parsed through the real
///   `trace_processor` seam and must contain at least one still-live
///   heap_profile allocation ([PreflightCheck.capturedHeapData]); an empty
///   trace exits 2 (a byte-size guard would not have caught it), a
///   `trace_processor` process failure exits 1.
///
/// [adb], [capture], and [validator] are injectable seams; when omitted, real
/// process-backed implementations are constructed, with `trace_processor`
/// resolved from `--tp-bin` then `RADAR_TP_BIN` (no bare-name fallback — it is
/// host-machine-specific). [now] stamps the validation checkpoint.
Future<int> runCapture(
  List<String> args, {
  AdbRunner? adb,
  NativeHeapCapture? capture,
  TraceProcessorRunner? validator,
  Map<String, String>? env,
  DateTime Function()? now,
  StringSink? out,
  StringSink? err,
}) async {
  final outSink = out ?? stdout;
  final errSink = err ?? stderr;
  final effectiveEnv = env ?? Platform.environment;

  final _CaptureArgs parsed;
  try {
    parsed = _parseArgs(args);
  } on FormatException catch (e) {
    errSink.writeln(e.message);
    return _exitUsage;
  }

  final effectiveAdb = adb ?? const ProcessAdbRunner();

  // Resolve the validator up front: a capture we could never validate is not
  // worth running.
  final TraceProcessorRunner effectiveValidator;
  if (validator != null) {
    effectiveValidator = validator;
  } else {
    final tpBin = parsed.tpBin ?? effectiveEnv['RADAR_TP_BIN'];
    if (tpBin == null) {
      errSink.writeln(
        'radar_capture: cannot validate the capture — trace_processor not '
        'found; pass --tp-bin <path> or set RADAR_TP_BIN',
      );
      return _exitUsage;
    }
    effectiveValidator = ProcessTraceProcessorRunner(binaryPath: tpBin);
  }

  // 1. Preflight BEFORE capture.
  final preflight = await CapturePreflight(
    effectiveAdb,
  ).check(parsed.package, serial: parsed.serial);
  if (!preflight.passed) {
    _reportCheck(errSink, preflight.failure!.check, preflight.failure!.message);
    return _exitUsage;
  }

  // 2. Capture.
  final effectiveCapture = capture ?? AdbHeapprofdCapture(effectiveAdb);
  final String tracePath;
  try {
    tracePath = await effectiveCapture.capture(
      CaptureRequest(
        packageId: parsed.package,
        mode: parsed.mode,
        durationMs: parsed.duration.inMilliseconds,
        samplingIntervalBytes: parsed.samplingIntervalBytes,
        serial: parsed.serial,
      ),
      outputPath: parsed.out,
    );
  } on AdbException catch (e) {
    errSink.writeln('radar_capture: capture failed — $e');
    return _exitToolFailure;
  }

  // 3. Post-capture validation via the real trace_processor seam.
  final NativeHeapProfile profile;
  try {
    profile = await PerfettoTraceProcessorParser(
      effectiveValidator,
    ).parseTrace(tracePath, capturedAt: (now ?? DateTime.now)());
  } on TraceProcessorException catch (e) {
    errSink.writeln(
      'radar_capture: could not validate $tracePath — trace_processor '
      'failed: ${e.message}',
    );
    return _exitToolFailure;
  } on ProcessException catch (e) {
    errSink.writeln(
      'radar_capture: could not validate $tracePath — ${e.message}',
    );
    return _exitToolFailure;
  }

  if (profile.callsites.isEmpty) {
    _reportCheck(
      errSink,
      PreflightCheck.capturedHeapData,
      'captured trace $tracePath contains no still-live heap_profile '
      'allocations — heapprofd produced no data (wrong process, the app never '
      'allocated under sampling, or profiling was silently denied). A byte '
      'count alone would not have caught this',
    );
    return _exitUsage;
  }

  outSink.writeln(
    '$tracePath — ${profile.callsites.length} callsites, '
    '${profile.totalStillLiveBytes} still-live bytes',
  );
  return _exitOk;
}

/// Writes a one-line failure naming the [check] so an operator (or a script
/// grepping the log) sees exactly which gate blocked the capture.
void _reportCheck(StringSink err, PreflightCheck check, String message) {
  err.writeln("radar_capture: check '${check.name}' failed: $message");
}

/// Parsed, validated `radar_capture` flags.
final class _CaptureArgs {
  const _CaptureArgs({
    required this.package,
    required this.out,
    required this.serial,
    required this.mode,
    required this.duration,
    required this.samplingIntervalBytes,
    required this.tpBin,
  });

  final String package;
  final String out;
  final String? serial;
  final CaptureMode mode;
  final Duration duration;
  final int samplingIntervalBytes;
  final String? tpBin;
}

_CaptureArgs _parseArgs(List<String> args) {
  String? package;
  String? out;
  String? serial;
  String? tpBin;
  var mode = CaptureMode.attach;
  var duration = const Duration(seconds: 30);
  var samplingIntervalBytes = 4096;

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
      case '--out':
        out = next(arg);
      case '--device':
        serial = next(arg);
      case '--mode':
        mode = _parseMode(next(arg));
      case '--duration':
        duration = _parseDuration(next(arg));
      case '--sampling-interval':
        samplingIntervalBytes = _parsePositiveInt(next(arg), arg);
      case '--tp-bin':
        tpBin = next(arg);
      default:
        throw FormatException('Unknown argument: $arg');
    }
    i++;
  }

  if (package == null) {
    throw const FormatException('Missing required --package <name>');
  }
  if (out == null) {
    throw const FormatException('Missing required --out <capture.pftrace>');
  }
  if (duration <= Duration.zero) {
    throw const FormatException('--duration must be positive');
  }

  return _CaptureArgs(
    package: package,
    out: out,
    serial: serial,
    mode: mode,
    duration: duration,
    samplingIntervalBytes: samplingIntervalBytes,
    tpBin: tpBin,
  );
}

CaptureMode _parseMode(String raw) => switch (raw) {
  'attach' => CaptureMode.attach,
  'startup' => CaptureMode.startup,
  _ => throw FormatException('--mode must be attach or startup, got "$raw"'),
};

int _parsePositiveInt(String raw, String flag) {
  final value = int.tryParse(raw.trim());
  if (value == null || value <= 0) {
    throw FormatException('$flag must be a positive integer, got "$raw"');
  }
  return value;
}

/// Parses a duration like `30s`, `2m`, `500ms`, or a bare seconds count.
Duration _parseDuration(String raw) {
  final match = RegExp(r'^(\d+)(ms|s|m|h)?$').firstMatch(raw.trim());
  if (match == null) {
    throw FormatException('not a duration (e.g. 30s, 2m, 500ms): "$raw"');
  }
  final value = int.parse(match.group(1)!);
  return switch (match.group(2)) {
    'ms' => Duration(milliseconds: value),
    'm' => Duration(minutes: value),
    'h' => Duration(hours: value),
    _ => Duration(seconds: value),
  };
}
