import 'package:vm_service/vm_service.dart';

import 'run_clock.dart';

/// Opens a raw VM-service connection to a WebSocket [uri].
typedef VmServiceConnector = Future<VmService> Function(String uri);

/// Verifies an open [service] still answers — the liveness probe.
typedef VmServiceProbe = Future<void> Function(VmService service);

/// Thrown when no stable VM-service connection could be established within the
/// budget.
///
/// Maps to the run's tool-failure exit code (2) — an honest "could not attach",
/// never a leak verdict and never a silently-masked partial run.
final class VmConnectException implements Exception {
  /// Creates the exception with a human-readable [message].
  const VmConnectException(this.message);

  /// Why a stable connection could not be reached.
  final String message;

  @override
  String toString() => 'VmConnectException: $message';
}

/// Attaches to [wsUri] and returns a connection proven live *and stable*.
///
/// A freshly spawned app announces its VM-service URI the instant the service
/// binds, but on a slow or heavily-loaded host — a CI runner bringing up
/// several isolates plus their DDS instances at once — the endpoint is not
/// reliably ready at that moment: an eager attach is either refused outright,
/// or connects and is then torn down a beat later while the service finishes
/// initialising. A single connect, or a single post-connect RPC, cannot tell a
/// durable connection from one about to drop.
///
/// So this hardens the attach two ways:
///  * it retries [connect] on failure until [timeout] elapses, backing off
///    [retryBackoff] between attempts, to ride out an early connection refusal;
///    and
///  * once connected it holds the connection across a [stabilityWindow],
///    [probe]-ing every [probeInterval]; if any probe fails the connection was
///    not durable, so it is disposed and the whole attach retried.
///
/// Only a connection that answered every probe across the window is returned.
/// Throws [VmConnectException] if none is achieved within [timeout].
///
/// Time flows through [clock] so the retry and stability logic is drivable in
/// virtual time under test.
Future<VmService> connectStableVmService(
  String wsUri, {
  required VmServiceConnector connect,
  required RunClock clock,
  VmServiceProbe probe = _probeGetVm,
  Duration timeout = const Duration(seconds: 30),
  Duration retryBackoff = const Duration(milliseconds: 500),
  Duration stabilityWindow = const Duration(seconds: 2),
  Duration probeInterval = const Duration(milliseconds: 500),
  void Function(String message)? onRetry,
}) async {
  final deadlineMicros = clock.nowMicros() + timeout.inMicroseconds;
  Object? lastError;

  while (clock.nowMicros() < deadlineMicros) {
    VmService? service;
    try {
      service = await connect(wsUri);
      await _holdUntilStable(
        service,
        probe: probe,
        clock: clock,
        stabilityWindow: stabilityWindow,
        probeInterval: probeInterval,
      );
      return service;
    } catch (error) {
      lastError = error;
      if (service != null) {
        try {
          await service.dispose();
        } catch (_) {
          // The connection is already gone; nothing left to dispose.
        }
      }
      onRetry?.call('VM-service attach not yet stable ($error); retrying');
      await clock.delay(retryBackoff);
    }
  }

  throw VmConnectException(
    'could not establish a stable VM-service connection to $wsUri within '
    '${timeout.inSeconds}s: $lastError',
  );
}

/// Probes [service] once immediately, then once per [probeInterval] across
/// [stabilityWindow]. A throw from any probe propagates so the caller retries —
/// a connection that drops a beat after connecting is caught here, not mid-run.
Future<void> _holdUntilStable(
  VmService service, {
  required VmServiceProbe probe,
  required RunClock clock,
  required Duration stabilityWindow,
  required Duration probeInterval,
}) async {
  final untilMicros = clock.nowMicros() + stabilityWindow.inMicroseconds;
  await probe(service);
  while (clock.nowMicros() < untilMicros) {
    await clock.delay(probeInterval);
    await probe(service);
  }
}

Future<void> _probeGetVm(VmService service) => service.getVM();
