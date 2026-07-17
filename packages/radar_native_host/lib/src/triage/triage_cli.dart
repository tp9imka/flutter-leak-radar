import 'dart:convert';
import 'dart:io';

import 'package:radar_native/radar_native.dart';
import 'package:radar_trace/radar_trace.dart';

import 'triage_render.dart';

/// Exit codes — the initiative-wide contract (see `radar_ci`'s `GateExit`):
/// 0 ok / 1 usage error / 2 tool failure.
const int _exitOk = 0;
const int _exitUsage = 1;
const int _exitToolFailure = 2;

/// Runs `radar_triage session_dir/`: loads the session's `timeline.json`,
/// runs the C1 router over it, and renders the verdict — the router summary
/// first, then a per-column verdict table.
///
/// ```
/// radar_triage session_dir/ [--format json|md]
/// radar_triage before_dir/ --compare after_dir/ [--format json|md]
/// ```
///
/// With `--compare`, renders the before-vs-after loop: both router summaries,
/// a one-read "did the fix work?" verdict, and a per-column A-vs-B table —
/// staying honest when a column was measured in one session but not the other
/// (never fabricating a delta across the missing side).
///
/// Exit 1 on a usage error or a session directory with no `timeline.json`
/// (naming the directory); exit 2 on a corrupt `timeline.json`; exit 0 on
/// success. [options] tunes the underlying [triage] assessment.
Future<int> runTriage(
  List<String> args, {
  AssessOptions? options,
  StringSink? out,
  StringSink? err,
}) async {
  final outSink = out ?? stdout;
  final errSink = err ?? stderr;
  final effectiveOptions = options ?? const AssessOptions();

  final _TriageArgs parsed;
  try {
    parsed = _parseArgs(args);
  } on FormatException catch (e) {
    errSink.writeln(e.message);
    return _exitUsage;
  }

  final sessionResult = _loadSession(parsed.sessionDir, effectiveOptions);
  switch (sessionResult) {
    case _LoadFailure(:final message, :final usage):
      errSink.writeln('radar_triage: $message');
      return usage ? _exitUsage : _exitToolFailure;
    case _LoadSuccess(:final session):
      if (parsed.compareDir == null) {
        _emit(
          outSink,
          parsed.format,
          () => renderTriageMarkdown(session),
          () => renderTriageJson(session),
        );
        return _exitOk;
      }
      final otherResult = _loadSession(parsed.compareDir!, effectiveOptions);
      switch (otherResult) {
        case _LoadFailure(:final message, :final usage):
          errSink.writeln('radar_triage: --compare $message');
          return usage ? _exitUsage : _exitToolFailure;
        case _LoadSuccess(session: final other):
          _emit(
            outSink,
            parsed.format,
            () => renderCompareMarkdown(session, other),
            () => renderCompareJson(session, other),
          );
          return _exitOk;
      }
  }
}

/// Writes the chosen format, pretty-printing JSON.
void _emit(
  StringSink out,
  _TriageFormat format,
  String Function() md,
  Map<String, Object?> Function() json,
) {
  switch (format) {
    case _TriageFormat.md:
      out.write(md());
    case _TriageFormat.json:
      out.writeln(const JsonEncoder.withIndent('  ').convert(json()));
  }
}

/// Loads a session directory into a [TriageSession], or reports why it could
/// not: a missing `timeline.json` is a usage error (wrong directory), a
/// corrupt one is a tool failure.
_LoadResult _loadSession(String dir, AssessOptions options) {
  final timelineFile = File('$dir/timeline.json');
  if (!timelineFile.existsSync()) {
    return _LoadFailure(
      'no timeline.json in "$dir" — point at a radar_sample session '
      'directory',
      usage: true,
    );
  }
  try {
    final decoded = jsonDecode(timelineFile.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      return _LoadFailure(
        'timeline.json in "$dir" is not a JSON object',
        usage: false,
      );
    }
    final timeline = TriageTimeline.fromJson(decoded);
    return _LoadSuccess(
      TriageSession(
        label: _basename(dir),
        timeline: timeline,
        verdict: triage(timeline, options),
        provenance: _readProvenance(dir),
      ),
    );
  } on FormatException catch (e) {
    return _LoadFailure(
      'corrupt timeline.json in "$dir": ${e.message}',
      usage: false,
    );
  } catch (e) {
    return _LoadFailure(
      'could not read timeline.json in "$dir": $e',
      usage: false,
    );
  }
}

/// Best-effort provenance from `meta.json`; never fails the report.
SessionProvenance? _readProvenance(String dir) {
  final file = File('$dir/meta.json');
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) return null;
    return SessionProvenance.fromMetaJson(decoded);
  } catch (_) {
    return null;
  }
}

String _basename(String path) {
  final trimmed = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  return trimmed.split('/').last;
}

/// The outcome of loading a session directory.
sealed class _LoadResult {
  const _LoadResult();
}

final class _LoadSuccess extends _LoadResult {
  const _LoadSuccess(this.session);
  final TriageSession session;
}

final class _LoadFailure extends _LoadResult {
  const _LoadFailure(this.message, {required this.usage});
  final String message;

  /// True when the failure is a usage error (exit 1), false for a tool
  /// failure (exit 2).
  final bool usage;
}

/// Output format for `radar_triage`.
enum _TriageFormat { json, md }

/// Parsed `radar_triage` arguments.
final class _TriageArgs {
  const _TriageArgs({
    required this.sessionDir,
    required this.compareDir,
    required this.format,
  });

  final String sessionDir;
  final String? compareDir;
  final _TriageFormat format;
}

_TriageArgs _parseArgs(List<String> args) {
  final positional = <String>[];
  String? compareDir;
  var format = _TriageFormat.md;

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
      case '--compare':
        compareDir = next(arg);
      case '--format':
        format = _parseFormat(next(arg));
      default:
        if (arg.startsWith('--')) {
          throw FormatException('Unknown argument: $arg');
        }
        positional.add(arg);
    }
    i++;
  }

  if (positional.length != 1) {
    throw FormatException(
      'radar_triage needs exactly one session directory, got '
      '${positional.length}',
    );
  }
  return _TriageArgs(
    sessionDir: positional.single,
    compareDir: compareDir,
    format: format,
  );
}

_TriageFormat _parseFormat(String raw) => switch (raw) {
  'json' => _TriageFormat.json,
  'md' => _TriageFormat.md,
  _ => throw FormatException('--format must be json or md, got "$raw"'),
};
