// lib/src/util/build_mode.dart
import 'package:flutter/foundation.dart';

/// Compile-time gate. Active machinery is built only when this is true, so the
/// tree-shaker eliminates the engine (and `package:vm_service`) from release.
const bool kEngineEnabled = kDebugMode || kProfileMode;
