import 'package:flutter/painting.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';

/// UI color token for a [NativeModuleKind], reusing the shared `radar_ui`
/// severity/text scale rather than introducing Android-specific colors.
Color moduleKindColor(NativeModuleKind kind) => switch (kind) {
  NativeModuleKind.app => RadarColors.info,
  NativeModuleKind.gpuDriver => RadarColors.warning,
  NativeModuleKind.engine => RadarColors.text50,
  NativeModuleKind.plugin => RadarColors.accent,
  NativeModuleKind.system => RadarColors.text25,
  NativeModuleKind.unknown => RadarColors.text25,
};

/// Short display label for a [NativeModuleKind], used in the still-live
/// table and module legend.
String moduleKindLabel(NativeModuleKind kind) => switch (kind) {
  NativeModuleKind.app => 'App',
  NativeModuleKind.gpuDriver => 'GPU driver',
  NativeModuleKind.engine => 'Engine',
  NativeModuleKind.plugin => 'Plugin',
  NativeModuleKind.system => 'Runtime',
  NativeModuleKind.unknown => '—',
};
