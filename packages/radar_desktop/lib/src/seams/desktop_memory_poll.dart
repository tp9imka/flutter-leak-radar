import 'package:radar_workbench/radar_workbench.dart';

/// One live memory reading of the connected isolate, in bytes.
typedef MemorySample = ({int heapUsage, int externalUsage});

/// A single live memory poll. Resolves to a [MemorySample] on success, or
/// throws to signal a not-measured interval (a gap), never a fabricated zero.
typedef MemoryPoll = Future<MemorySample> Function();

/// Thrown when a live memory poll cannot be truthfully completed — no live
/// connection, or the VM reported an absent (not-measured) field.
///
/// The live controller treats this as a measurement gap, never as a zero
/// reading (the parsed-or-unmeasured rule).
class MemoryPollUnavailableException implements Exception {
  /// Creates the exception with an optional [reason].
  const MemoryPollUnavailableException([this.reason]);

  /// Why the poll could not complete, when known.
  final String? reason;

  @override
  String toString() =>
      'MemoryPollUnavailableException: ${reason ?? 'no live memory reading'}';
}

/// Polls [connection]'s selected isolate for its Dart heap and external
/// memory usage via the `getMemoryUsage` RPC.
///
/// Throws [MemoryPollUnavailableException] when there is no live VM service /
/// isolate, or when the VM reports an absent field (vm_service surfaces a
/// missing value as `-1`). A missing field is not-measured — it must break
/// the live line as a gap rather than read as a real zero.
Future<MemorySample> desktopMemoryPoll(RadarConnection connection) async {
  final svc = connection.vmService;
  final isolateId = connection.isolateRef?.id;
  if (svc == null || isolateId == null) {
    throw const MemoryPollUnavailableException('no live isolate');
  }

  final usage = await svc.getMemoryUsage(isolateId);
  final heap = usage.heapUsage;
  final external = usage.externalUsage;
  if (heap == null || heap < 0 || external == null || external < 0) {
    throw const MemoryPollUnavailableException(
      'VM reported an absent memory field',
    );
  }
  return (heapUsage: heap, externalUsage: external);
}

/// Binds [connection] into a [MemoryPoll] closure — the live counterpart to
/// `perfCallFor`.
MemoryPoll memoryPollFor(RadarConnection connection) =>
    () => desktopMemoryPoll(connection);
