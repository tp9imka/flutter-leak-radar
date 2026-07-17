import 'dart:convert';
import 'dart:io';

import 'package:radar_native/radar_native.dart';

import '../perfetto/perfetto_trace_processor_parser.dart';
import '../perfetto/trace_processor_runner.dart';
import 'build_id_reader.dart';
import 'symbol_store_builder.dart';
import 'symbolizer.dart';

/// Entry point for `dart run radar_native_host:symbolize`: parses a captured
/// `.pftrace` into a [NativeHeapProfile], build-id-matches the supplied
/// unstripped `.so` files, symbolizes every module-only frame address, and
/// writes the resulting [SymbolStore] as pretty JSON to `--out`.
///
/// ```
/// symbolize --trace <capture.pftrace> --so <libA.so> [--so <libB.so> ...]
///           [--so-dir <dir>] --out symbols.json
///           [--tp-bin <trace_processor>] [--symbolizer <llvm-symbolizer>]
///           [--readelf <llvm-readelf>]
/// ```
///
/// [runner], [reader], and [symbolizer] are injectable seams for tests; when
/// omitted, real process-backed implementations are constructed, resolving
/// each tool's binary via its explicit flag, then an environment variable
/// (read from [env], defaulting to [Platform.environment]), then — for
/// `llvm-readelf`/`llvm-symbolizer` only — a bare name on `PATH`.
/// `trace_processor` has no bare-name fallback: it is host-machine-specific,
/// so a missing `--tp-bin`/`RADAR_TP_BIN` is reported as a clear error
/// rather than guessed at.
///
/// Every failure — a missing required flag, an unresolvable tool, a genuine
/// tool-process failure ([SymbolizeToolException]/[TraceProcessorException]),
/// or a tool binary absent from `PATH` ([ProcessException]) — is reported as
/// a specific message on [err] (defaulting to [stderr]) with a non-zero
/// return, never an unhandled stack trace.
Future<int> runSymbolize(
  List<String> args, {
  TraceProcessorRunner? runner,
  BuildIdReader? reader,
  Symbolizer? symbolizer,
  Map<String, String>? env,
  StringSink? out,
  StringSink? err,
}) async {
  final outSink = out ?? stdout;
  final errSink = err ?? stderr;
  final effectiveEnv = env ?? Platform.environment;

  final _SymbolizeArgs parsed;
  try {
    parsed = _parseArgs(args);
  } on FormatException catch (e) {
    errSink.writeln(e.message);
    return 1;
  }

  if (parsed.trace == null) {
    errSink.writeln('Missing required --trace <capture.pftrace>');
    return 1;
  }
  if (parsed.out == null) {
    errSink.writeln('Missing required --out <symbols.json>');
    return 1;
  }
  final soPaths = _collectSoPaths(parsed.soPaths, parsed.soDirs);
  if (soPaths.isEmpty) {
    errSink.writeln(
      'No .so files given — pass --so <path> and/or --so-dir <dir>',
    );
    return 1;
  }

  TraceProcessorRunner effectiveRunner;
  if (runner != null) {
    effectiveRunner = runner;
  } else {
    final tpBin = parsed.tpBin ?? effectiveEnv['RADAR_TP_BIN'];
    if (tpBin == null) {
      errSink.writeln(
        'trace_processor not found — pass --tp-bin <path> or set '
        'RADAR_TP_BIN',
      );
      return 1;
    }
    effectiveRunner = ProcessTraceProcessorRunner(binaryPath: tpBin);
  }

  final effectiveReader =
      reader ??
      LlvmReadelfBuildIdReader(
        binaryPath: resolveReadelfBinary(
          explicit: parsed.readelfBin,
          env: effectiveEnv,
        ),
      );
  final effectiveSymbolizer =
      symbolizer ??
      LlvmSymbolizer(
        binaryPath: resolveSymbolizerBinary(
          explicit: parsed.symbolizerBin,
          env: effectiveEnv,
        ),
      );

  try {
    final profile = await PerfettoTraceProcessorParser(
      effectiveRunner,
    ).parseTrace(parsed.trace!, capturedAt: DateTime.now());

    final report = await SymbolStoreBuilder(
      buildIdReader: effectiveReader,
      symbolizer: effectiveSymbolizer,
    ).buildWithReport(profile, soPaths: soPaths);

    final encoder = const JsonEncoder.withIndent('  ');
    await File(
      parsed.out!,
    ).writeAsString(encoder.convert(report.store.toJson()));

    final totalBuildIds = report.matchedBuildIds + report.unmatchedBuildIds;
    final totalAddresses =
        report.resolvedAddresses + report.unresolvedAddresses;
    outSink.writeln(
      'matched ${report.matchedBuildIds}/$totalBuildIds build-ids, '
      'resolved ${report.resolvedAddresses}/$totalAddresses addresses '
      '→ ${parsed.out}',
    );
    return 0;
  } on SymbolizeToolException catch (e) {
    errSink.writeln('symbolization tool failed: ${e.message}\n${e.stderr}');
    return 2;
  } on TraceProcessorException catch (e) {
    errSink.writeln('trace_processor failed: ${e.message}\n${e.stderr}');
    return 2;
  } on ProcessException catch (e) {
    errSink.writeln(_missingToolMessage(e.executable));
    return 2;
  }
}

/// Maps a tool binary name (or path) that turned out to be absent from
/// `PATH` to a specific, actionable error naming the matching flag/env
/// override.
String _missingToolMessage(String executable) {
  final lower = executable.toLowerCase();
  if (lower.contains('symbolizer')) {
    return '$executable not found — install the NDK or pass --symbolizer / '
        'set RADAR_LLVM_SYMBOLIZER';
  }
  if (lower.contains('readelf')) {
    return '$executable not found — install the NDK or pass --readelf / '
        'set RADAR_READELF';
  }
  if (lower.contains('trace_processor')) {
    return '$executable not found — pass --tp-bin or set RADAR_TP_BIN';
  }
  return '$executable not found on PATH — install the required tool or '
      'pass an explicit binary path';
}

/// Every `*.so` path to symbolize: [soPaths] verbatim, plus every `*.so`
/// found (recursively) under each of [soDirs]. A `--so-dir` that does not
/// exist contributes no paths rather than throwing.
List<String> _collectSoPaths(List<String> soPaths, List<String> soDirs) {
  final result = <String>[...soPaths];
  for (final dir in soDirs) {
    final directory = Directory(dir);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.so')) {
        result.add(entity.path);
      }
    }
  }
  return result;
}

/// Parsed `symbolize` command-line flags, before required-field validation.
final class _SymbolizeArgs {
  const _SymbolizeArgs({
    required this.trace,
    required this.soPaths,
    required this.soDirs,
    required this.out,
    required this.tpBin,
    required this.readelfBin,
    required this.symbolizerBin,
  });

  final String? trace;
  final List<String> soPaths;
  final List<String> soDirs;
  final String? out;
  final String? tpBin;
  final String? readelfBin;
  final String? symbolizerBin;
}

/// Hand-rolled `--flag value` parser (this package has no `package:args`
/// dependency, and one is not worth adding for this small a surface).
/// Throws [FormatException] on an unknown flag or a flag missing its value.
_SymbolizeArgs _parseArgs(List<String> args) {
  String? trace;
  String? out;
  String? tpBin;
  String? readelfBin;
  String? symbolizerBin;
  final soPaths = <String>[];
  final soDirs = <String>[];

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
      case '--trace':
        trace = next(arg);
      case '--so':
        soPaths.add(next(arg));
      case '--so-dir':
        soDirs.add(next(arg));
      case '--out':
        out = next(arg);
      case '--tp-bin':
        tpBin = next(arg);
      case '--readelf':
        readelfBin = next(arg);
      case '--symbolizer':
        symbolizerBin = next(arg);
      default:
        throw FormatException('Unknown argument: $arg');
    }
    i++;
  }

  return _SymbolizeArgs(
    trace: trace,
    soPaths: soPaths,
    soDirs: soDirs,
    out: out,
    tpBin: tpBin,
    readelfBin: readelfBin,
    symbolizerBin: symbolizerBin,
  );
}
