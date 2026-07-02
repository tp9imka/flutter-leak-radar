import 'package:meta/meta.dart';

/// One resolved stack frame: a native function in an owning module
/// (Perfetto `stack_profile_frame` + `stack_profile_mapping`).
@immutable
final class NativeFrame {
  const NativeFrame({
    required this.function,
    required this.module,
    this.buildId,
  });

  /// Symbolized function name (or a `0x…` address when unsymbolized).
  final String function;

  /// Owning module (mapping name, e.g. `libflutter.so`).
  final String module;

  /// Build-id of [module], for symbol-store lookup (nullable if unknown).
  final String? buildId;

  Map<String, Object?> toJson() => {
    'function': function,
    'module': module,
    if (buildId != null) 'buildId': buildId,
  };

  factory NativeFrame.fromJson(Map<String, Object?> json) => NativeFrame(
    function: json['function'] as String,
    module: json['module'] as String,
    buildId: json['buildId'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is NativeFrame &&
      other.function == function &&
      other.module == module &&
      other.buildId == buildId;

  @override
  int get hashCode => Object.hash(function, module, buildId);
}
