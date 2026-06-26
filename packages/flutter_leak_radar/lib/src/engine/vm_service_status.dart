// lib/src/engine/vm_service_status.dart

/// Typed status of the VM-service connection.
///
/// Sealed — exhaustive switch is enforced by the compiler.
sealed class VmServiceStatus {
  const VmServiceStatus();
}

/// The probe holds a live VM-service connection.
final class VmConnected extends VmServiceStatus {
  const VmConnected();
}

/// No VM-service URI available — profile/release build or service not started.
final class VmNoServiceUri extends VmServiceStatus {
  const VmNoServiceUri();
}

/// Covers DDS-refused (SocketException on connect) and other socket failures.
final class VmSocketError extends VmServiceStatus {
  const VmSocketError({required this.message});

  final String message;
}

/// VM service disabled — e.g. the probe was disposed or never started.
final class VmDisabled extends VmServiceStatus {
  const VmDisabled();
}

/// Used when the reason cannot be determined — honest degradation.
final class VmUnknown extends VmServiceStatus {
  const VmUnknown({this.message});

  final String? message;
}
