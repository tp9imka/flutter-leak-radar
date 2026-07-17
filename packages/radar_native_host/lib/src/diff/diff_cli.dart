import 'dart:convert';
import 'dart:io';

import 'package:radar_native/radar_native.dart';

import '../perfetto/perfetto_trace_processor_parser.dart';
import '../perfetto/trace_processor_runner.dart';

/// Exit codes, matching the `symbolize`/`capture` verb contract.
const int _exitOk = 0;
const int _exitToolFailure = 1;
const int _exitUsage = 2;

/// How many callsite rows the Markdown "top growth" table shows before
/// truncating — the JSON output always carries them all.
const int _maxCallsiteRows = 25;

/// Runs `radar_diff a.pftrace b.pftrace`: parses both heapprofd traces through
/// the real `trace_processor` seam and ranks what grew in still-live bytes
/// between them — the Lane B leak signal, rolled up per module and per
/// callsite.
///
/// ```
/// radar_diff before.pftrace after.pftrace [--format json|md]
///   [--tp-bin <trace_processor>]
/// ```
///
/// `--format json` (envelope `schemaVersion: 1`) carries every module and
/// callsite diff via the C1 `toJson`s; `--format md` (the default) renders a
/// per-module still-live table plus a top-growth callsite table.
///
/// [runner] is an injectable seam; when omitted a process-backed
/// `trace_processor` is resolved from `--tp-bin` then `RADAR_TP_BIN` (no
/// bare-name fallback). A missing binary exits 2; a `trace_processor` process
/// failure exits 1.
Future<int> runDiff(
  List<String> args, {
  TraceProcessorRunner? runner,
  Map<String, String>? env,
  DateTime Function()? now,
  StringSink? out,
  StringSink? err,
}) async {
  final outSink = out ?? stdout;
  final errSink = err ?? stderr;
  final effectiveEnv = env ?? Platform.environment;

  final _DiffArgs parsed;
  try {
    parsed = _parseArgs(args);
  } on FormatException catch (e) {
    errSink.writeln(e.message);
    return _exitUsage;
  }

  final TraceProcessorRunner effectiveRunner;
  if (runner != null) {
    effectiveRunner = runner;
  } else {
    final tpBin = parsed.tpBin ?? effectiveEnv['RADAR_TP_BIN'];
    if (tpBin == null) {
      errSink.writeln(
        'radar_diff: trace_processor not found — pass --tp-bin <path> or set '
        'RADAR_TP_BIN',
      );
      return _exitUsage;
    }
    effectiveRunner = ProcessTraceProcessorRunner(binaryPath: tpBin);
  }

  final parser = PerfettoTraceProcessorParser(effectiveRunner);
  final stamp = (now ?? DateTime.now)();
  final NativeHeapProfile before;
  final NativeHeapProfile after;
  try {
    before = await parser.parseTrace(
      parsed.beforePath,
      capturedAt: stamp,
      label: _basename(parsed.beforePath),
    );
    after = await parser.parseTrace(
      parsed.afterPath,
      capturedAt: stamp,
      label: _basename(parsed.afterPath),
    );
  } on TraceProcessorException catch (e) {
    errSink.writeln('radar_diff: trace_processor failed: ${e.message}');
    return _exitToolFailure;
  } on ProcessException catch (e) {
    errSink.writeln('radar_diff: trace_processor could not run: ${e.message}');
    return _exitToolFailure;
  }

  final modules = diffModuleSummaries(before, after);
  final callsites = diffNativeProfiles(before, after, includeRemoved: true);

  outSink.write(switch (parsed.format) {
    _DiffFormat.json => _renderJson(before, after, modules, callsites),
    _DiffFormat.md => _renderMarkdown(before, after, modules, callsites),
  });
  return _exitOk;
}

String _renderJson(
  NativeHeapProfile before,
  NativeHeapProfile after,
  List<NativeModuleDiff> modules,
  List<NativeAllocationDiff> callsites,
) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert({
    'schemaVersion': 1,
    'format': 'json',
    'before': _sideJson(before),
    'after': _sideJson(after),
    'modules': [for (final m in modules) m.toJson()],
    'callsites': [for (final c in callsites) c.toJson()],
  })}\n';
}

Map<String, Object?> _sideJson(NativeHeapProfile profile) => {
  'label': profile.label,
  'capturedAt': profile.capturedAt.toIso8601String(),
  'callsites': profile.callsites.length,
  'stillLiveBytes': profile.totalStillLiveBytes,
};

String _renderMarkdown(
  NativeHeapProfile before,
  NativeHeapProfile after,
  List<NativeModuleDiff> modules,
  List<NativeAllocationDiff> callsites,
) {
  final buffer = StringBuffer()
    ..writeln('# Native heap diff: ${before.label} → ${after.label}')
    ..writeln()
    ..writeln(
      'Still-live bytes: ${before.totalStillLiveBytes} → '
      '${after.totalStillLiveBytes} '
      '(${_signed(after.totalStillLiveBytes - before.totalStillLiveBytes)})',
    )
    ..writeln()
    ..writeln('## By module (still-live bytes)')
    ..writeln();

  if (modules.isEmpty) {
    buffer.writeln('_No module allocations in either checkpoint._');
  } else {
    buffer
      ..writeln('| module | kind | before | after | Δ bytes | status |')
      ..writeln('| --- | --- | ---: | ---: | ---: | --- |');
    for (final m in modules) {
      buffer.writeln(
        '| ${m.module} | ${m.kind.name} | ${m.beforeStillLiveBytes} | '
        '${m.afterStillLiveBytes} | ${_signed(m.deltaBytes)} | '
        '${m.status.name} |',
      );
    }
  }

  buffer
    ..writeln()
    ..writeln('## Top growth callsites')
    ..writeln();
  if (callsites.isEmpty) {
    buffer.writeln('_No callsites to compare._');
    return buffer.toString();
  }
  buffer
    ..writeln('| Δ bytes | after bytes | status | module | leaf |')
    ..writeln('| ---: | ---: | --- | --- | --- |');
  for (final c in callsites.take(_maxCallsiteRows)) {
    buffer.writeln(
      '| ${_signed(c.growthBytes)} | ${c.afterStillLiveBytes} | '
      '${c.status.name} | ${_leafModule(c)} | ${_leafFunction(c)} |',
    );
  }
  if (callsites.length > _maxCallsiteRows) {
    buffer.writeln();
    buffer.writeln(
      '_… ${callsites.length - _maxCallsiteRows} more callsites '
      '(full ranking in --format json)._',
    );
  }
  return buffer.toString();
}

/// Signed decimal, so growth reads `+N` and shrinkage `-N` at a glance.
String _signed(int value) => value >= 0 ? '+$value' : '$value';

String _leafModule(NativeAllocationDiff diff) => diff.frames.isEmpty
    ? '(no stack)'
    : moduleShortName(diff.frames.first.module);

String _leafFunction(NativeAllocationDiff diff) =>
    diff.frames.isEmpty ? '' : diff.frames.first.function;

String _basename(String path) => path.split('/').last;

/// Output format for `radar_diff`.
enum _DiffFormat { json, md }

/// Parsed `radar_diff` arguments.
final class _DiffArgs {
  const _DiffArgs({
    required this.beforePath,
    required this.afterPath,
    required this.format,
    required this.tpBin,
  });

  final String beforePath;
  final String afterPath;
  final _DiffFormat format;
  final String? tpBin;
}

_DiffArgs _parseArgs(List<String> args) {
  final positional = <String>[];
  var format = _DiffFormat.md;
  String? tpBin;

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
      case '--format':
        format = _parseFormat(next(arg));
      case '--tp-bin':
        tpBin = next(arg);
      default:
        if (arg.startsWith('--')) {
          throw FormatException('Unknown argument: $arg');
        }
        positional.add(arg);
    }
    i++;
  }

  if (positional.length != 2) {
    throw FormatException(
      'radar_diff needs exactly two trace paths '
      '(before.pftrace after.pftrace), got ${positional.length}',
    );
  }
  return _DiffArgs(
    beforePath: positional[0],
    afterPath: positional[1],
    format: format,
    tpBin: tpBin,
  );
}

_DiffFormat _parseFormat(String raw) => switch (raw) {
  'json' => _DiffFormat.json,
  'md' => _DiffFormat.md,
  _ => throw FormatException('--format must be json or md, got "$raw"'),
};
