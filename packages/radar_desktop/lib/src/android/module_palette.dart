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

/// Whether a stack frame's [function] is a resolved symbol name rather than
/// a raw `0x…` address — never guessed beyond what the symbol store
/// resolved. Shared by the still-live table's callsite rows
/// (`android_native_module_row.dart`) and the callsite detail screen
/// (`android_detail_screen.dart`).
bool isFrameSymbolized(String function) =>
    function.isNotEmpty && !function.startsWith('0x');
