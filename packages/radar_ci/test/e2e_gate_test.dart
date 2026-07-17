@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:radar_ci/radar_ci.dart';
import 'package:radar_ci/radar_ci_io.dart';
import 'package:test/test.dart';

/// Opt-in guard: this e2e spawns real subprocesses and samples them for ~3 min,
/// so a bare `dart test` skips it. Set `RADAR_E2E=1` to run it — the CI
/// memory-selftest job does, and can also select it with `-t e2e`.
final bool _e2eEnabled = Platform.environment['RADAR_E2E'] == '1';

/// Skip reason surfaced when the guard is off — honest and actionable.
final Object _skip = _e2eEnabled
    ? false
    : 'opt-in: set RADAR_E2E=1 to run the hermetic planted-leak e2e';

/// A full, in-spec `run` window sized for the SHIPPED gate/report CLI, which
/// assess with radar_trace's field-proven defaults (30 s settle + 2 min
/// minSpan). A 3 min run at 2 s cadence leaves ~2.5 min of post-settle span and
/// ~76 assessed samples — clearing every floor — so `radar_ci gate`/`report`
/// certify the leak with NO test-only assess options and NO `--allow-short`.
/// This is the tool used exactly as a real user's CI would.
const List<String> _runWindowFlags = [
  '--duration', '3m',
  '--sample-interval', '2s',
  // The verdict gate needs only the memory series; skip heap snapshots so the
  // run stays hermetic (no sibling .data/.analysis.json files) and fast.
  '--snapshot-every', '0',
  // Explicit so the run does not scan the CWD for project packages.
  '--project-packages', 'radar_ci_fixture',
];

void main() {
  group('hermetic planted-leak e2e gate', () {
    late Directory workDir;
    late bool ownsWorkDir;

    setUp(() async {
      // Persist artifacts when RADAR_E2E_OUT is set (the CI job reports on and
      // uploads them); otherwise a throwaway temp dir cleaned in tearDown.
      final outEnv = Platform.environment['RADAR_E2E_OUT'];
      if (outEnv != null && outEnv.isNotEmpty) {
        workDir = Directory(outEnv);
        await workDir.create(recursive: true);
        ownsWorkDir = false;
      } else {
        workDir = await Directory.systemTemp.createTemp('radar_ci_e2e_');
        ownsWorkDir = true;
      }
    });

    tearDown(() async {
      if (ownsWorkDir && await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
    });

    test(
      'planted leak FAILS the gate (exit 3); steady state PASSES (exit 0)',
      () async {
        // Launch both fixtures first, then drive the run+gate for each
        // concurrently, so the whole e2e costs ~one 3 min window, not two.
        final leaky = await _launchFixture('leaky_app.dart');
        if (leaky == null) return; // spawning unavailable — marked skipped

        // Once leaky is spawned, the finally must kill it on ANY failure path —
        // including a throw from the healthy launch (e.g. a URI timeout), which
        // would otherwise orphan leaky until its 6 min self-destruct.
        _Fixture? healthy;
        try {
          healthy = await _launchFixture('healthy_app.dart');
          if (healthy == null) return; // spawning unavailable — marked skipped

          final results = await Future.wait([
            _runAndGate(leaky.uri, 'leaky', workDir),
            _runAndGate(healthy.uri, 'healthy', workDir),
          ]);
          final leakyResult = results[0];
          final healthyResult = results[1];

          // Surface each fixture's fate — dialed URI, liveness, captured output
          // — to stdout (→ CI log) and, when persisting, to a file the CI step
          // folds into the job summary. A green run logs it too; a red one is
          // then self-diagnosing without a re-run.
          final leakyDiag = leaky.diagnose('leaky');
          final healthyDiag = healthy.diagnose('healthy');
          final fixtureReport = '$leakyDiag\n$healthyDiag\n';
          stdout.write('\n$fixtureReport');
          await _persistFixtureDiagnostics(workDir, ownsWorkDir, fixtureReport);

          expect(
            leakyResult.runExit,
            0,
            reason:
                'leaky run should complete — ${leakyResult.diagnostics}\n'
                '$leakyDiag',
          );
          expect(
            leakyResult.gateExit,
            GateExit.gateFailed,
            reason:
                'a planted monotonic leak must fail the gate\n'
                '${leakyResult.gateOut}',
          );
          expect(leakyResult.gateOut, contains('monotonicGrowth'));
          expect(leakyResult.gateOut, contains('GATE FAILED'));

          expect(
            healthyResult.runExit,
            0,
            reason:
                'healthy run should complete — ${healthyResult.diagnostics}\n'
                '$healthyDiag',
          );
          expect(
            healthyResult.gateExit,
            GateExit.ok,
            reason:
                'steady-state control must not certify growth\n'
                '${healthyResult.gateOut}',
          );
          expect(healthyResult.gateOut, contains('GATE PASSED'));
        } finally {
          leaky.kill();
          healthy?.kill();
          await leaky.exited;
          if (healthy != null) await healthy.exited;
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }, skip: _skip);
}

/// A spawned fixture: its process, the VM-service URI it announced, the merged
/// stdout+stderr it has produced (drained for its whole life so its pipe never
/// blocks and its fate stays inspectable), and its exit code once it exits.
final class _Fixture {
  _Fixture(this._process, this.uri, this._output, this._subscriptions) {
    _process.exitCode.then((code) => _exitCode = code).ignore();
  }

  final Process _process;
  final StringBuffer _output;
  final List<StreamSubscription<String>> _subscriptions;
  int? _exitCode;

  /// The discovered VM-service WebSocket URI the run actually dials.
  final String uri;

  /// Force-kills the fixture and stops draining its output.
  void kill() {
    _process.kill(ProcessSignal.sigkill);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }

  /// Completes when the fixture process has exited.
  Future<int> get exited => _process.exitCode;

  /// A self-diagnosing dump: the dialed URI, whether the process is still alive
  /// (or the code it exited with), and everything it printed. Turns a future CI
  /// failure from a mystery into a readable report without needing a re-run.
  String diagnose(String stem) {
    final exit = _exitCode;
    final liveness = exit == null ? 'ALIVE' : 'EXITED (code $exit)';
    final body = _output.toString().trim();
    return '── fixture "$stem" ──\n'
        '  dialed URI : $uri\n'
        '  process    : $liveness\n'
        '  output     :${body.isEmpty ? ' (none captured)' : '\n${_indent(body)}'}';
  }
}

String _indent(String text) =>
    text.split('\n').map((line) => '    $line').join('\n');

/// The outcome of driving the full pipeline over one fixture.
typedef _E2eResult = ({
  int runExit,
  int gateExit,
  String gateOut,
  String diagnostics,
});

/// Spawns [fixture] under its own *in-process* VM service and returns a handle
/// once it announces its service URI.
///
/// Spawned with `--no-dds`: the announced URI is the raw in-VM service, whose
/// lifetime is the fixture process itself. There is no separate DDS process to
/// exit and leave the announced port refusing connections while the fixture
/// lives on — the failure mode seen on CI, where every attach to a live
/// fixture's port was refused for the whole window. Its stdout+stderr are
/// drained for the fixture's whole life (never cancelled until [_Fixture.kill])
/// so the OS pipe never fills and blocks the child, and so a failure is
/// self-diagnosing.
///
/// Returns null (and marks the running test skipped) when the sandbox forbids
/// spawning a subprocess — the one environment where this test cannot prove
/// anything. Fails loudly, dumping any captured output, if the fixture spawns
/// but announces no URI.
Future<_Fixture?> _launchFixture(String fixture) async {
  final fixturePath = _resolveFixture(fixture);
  final Process process;
  try {
    process = await Process.start(Platform.resolvedExecutable, [
      '--enable-vm-service=0',
      '--no-dds',
      '--disable-service-auth-codes',
      fixturePath,
    ]);
  } on ProcessException catch (error) {
    markTestSkipped('subprocess spawning unavailable: $error');
    return null;
  }

  final output = StringBuffer();
  final lines = StreamController<String>();
  final subscriptions = <StreamSubscription<String>>[
    for (final stream in [process.stdout, process.stderr])
      stream.transform(utf8.decoder).transform(const LineSplitter()).listen((
        line,
      ) {
        output.writeln(line);
        if (!lines.isClosed) lines.add(line);
      }, onError: (_) {}),
  ];

  final uri = await scanForVmServiceUri(
    lines.stream,
    timeout: const Duration(seconds: 30),
  );
  // The scanner is done; keep the stdout+stderr drain alive for the fixture's
  // whole life (cancelled only by kill) so its pipe never fills — further lines
  // now accrue in [output] for diagnostics only.
  unawaited(lines.close());

  if (uri == null) {
    final dump = output.toString().trim();
    process.kill(ProcessSignal.sigkill);
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    fail(
      'fixture "$fixture" printed no VM-service URI within 30s\n'
      '${dump.isEmpty ? '(no output captured)' : dump}',
    );
  }
  return _Fixture(process, uri, output, subscriptions);
}

/// Drives the real `run` and `gate` command functions against [uri], writing
/// `<stem>.run.json` into [outDir], and returns the exit codes and gate output.
Future<_E2eResult> _runAndGate(
  String uri,
  String stem,
  Directory outDir,
) async {
  final runJsonPath = '${outDir.path}/$stem.run.json';
  final runExit = await runVerb([
    '--vm-uri',
    uri,
    ..._runWindowFlags,
    '--out',
    runJsonPath,
  ]);

  final gateOut = StringBuffer();
  final gateErr = StringBuffer();
  final gateExit = await runGate([runJsonPath], out: gateOut, err: gateErr);

  return (
    runExit: runExit,
    gateExit: gateExit,
    gateOut: gateOut.toString(),
    diagnostics: 'gate stderr: $gateErr',
  );
}

/// Writes the fixture [report] beside the run artifacts so the CI job can fold
/// it into the step summary and upload it. A no-op for an [ephemeral] temp dir
/// (a local `dart test` run) whose stdout already carries the same report.
Future<void> _persistFixtureDiagnostics(
  Directory outDir,
  bool ephemeral,
  String report,
) async {
  if (ephemeral) return;
  try {
    await File('${outDir.path}/fixtures.diagnostics.log').writeAsString(report);
  } catch (_) {
    // Best-effort: stdout already carries the identical report.
  }
}

/// Resolves a fixture under `test_fixtures/`, tolerating a CWD of either the
/// package root (the normal `dart test` case) or the repo root.
String _resolveFixture(String name) {
  for (final candidate in [
    'test_fixtures/$name',
    'packages/radar_ci/test_fixtures/$name',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  fail(
    'fixture "$name" not found from CWD ${Directory.current.path} — '
    'run from the radar_ci package or the repo root',
  );
}
