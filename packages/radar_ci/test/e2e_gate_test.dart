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
        final healthy = await _launchFixture('healthy_app.dart');
        if (healthy == null) {
          leaky.kill();
          return;
        }

        try {
          final results = await Future.wait([
            _runAndGate(leaky.uri, 'leaky', workDir),
            _runAndGate(healthy.uri, 'healthy', workDir),
          ]);
          final leakyResult = results[0];
          final healthyResult = results[1];

          expect(
            leakyResult.runExit,
            0,
            reason: 'leaky run should complete — ${leakyResult.diagnostics}',
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
                'healthy run should complete — ${healthyResult.diagnostics}',
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
          healthy.kill();
          await Future.wait([leaky.exited, healthy.exited]);
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }, skip: _skip);
}

/// A spawned fixture: its process, discovered VM-service URI, and a helper to
/// force-kill it and await exit.
final class _Fixture {
  _Fixture(this._process, this.uri);

  final Process _process;

  /// The discovered VM-service WebSocket URI.
  final String uri;

  /// Force-kills the fixture.
  void kill() => _process.kill(ProcessSignal.sigkill);

  /// Completes when the fixture process has exited.
  Future<int> get exited => _process.exitCode;
}

/// The outcome of driving the full pipeline over one fixture.
typedef _E2eResult = ({
  int runExit,
  int gateExit,
  String gateOut,
  String diagnostics,
});

/// Spawns [fixture] under its own VM service and discovers its service URI.
///
/// Returns null (and marks the running test skipped) when the sandbox forbids
/// spawning a subprocess — the one environment where this test cannot prove
/// anything. Fails loudly if the fixture spawns but announces no URI.
Future<_Fixture?> _launchFixture(String fixture) async {
  final fixturePath = _resolveFixture(fixture);
  final Process process;
  try {
    process = await Process.start(Platform.resolvedExecutable, [
      '--enable-vm-service=0',
      fixturePath,
    ]);
  } on ProcessException catch (error) {
    markTestSkipped('subprocess spawning unavailable: $error');
    return null;
  }

  final uri = await _discoverUri(process);
  if (uri == null) {
    process.kill(ProcessSignal.sigkill);
    fail('fixture "$fixture" printed no VM-service URI within 30s');
  }
  return _Fixture(process, uri);
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

/// Merges the spawned process's stdout+stderr and returns the first VM-service
/// WebSocket URI it announces, or null if none appears within 30 s.
Future<String?> _discoverUri(Process process) async {
  final lines = StreamController<String>();
  final subscriptions = <StreamSubscription<String>>[
    for (final stream in [process.stdout, process.stderr])
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add, onError: (_) {}),
  ];
  try {
    return await scanForVmServiceUri(
      lines.stream,
      timeout: const Duration(seconds: 30),
    );
  } finally {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(lines.close());
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
