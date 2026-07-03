import 'native_module.dart';

/// UI color-kind bucket for a native mapping's owning module.
enum NativeModuleKind {
  /// The app's own AOT/dex code (`base.apk`, `libapp.so`, `.oat`/`.dex`).
  app,

  /// A vendor GPU driver library (Adreno/Mali/PowerVR/Vulkan/EGL).
  gpuDriver,

  /// The Flutter/Dart engine (`libflutter.so`).
  engine,

  /// An app-bundled third-party or plugin native library.
  plugin,

  /// Platform/AOSP system libraries (`/system`, `/apex`, `/vendor`, bionic).
  system,

  /// Deliberate honest fallback: no rule matched (e.g. `[anon:dart-code]`,
  /// `memfd:jit-cache`). Never guessed.
  unknown,
}

/// Basenames of well-known AOSP system libraries.
const Set<String> _systemLibShortNames = {
  'libc.so',
  'libc++.so',
  'libc++_shared.so',
  'libutils.so',
  'libbinder.so',
  'libart.so',
  'libui.so',
  'libgui.so',
  'libhwui.so',
};

/// Substrings (checked in a lowercased path) that identify a vendor GPU
/// driver library.
const List<String> _gpuDriverMarkers = [
  'adreno',
  'mali',
  'powervr',
  'libgles',
  'vulkan',
  '/egl/',
  'libegl',
  'libgsl',
];

/// Basenames that are the app's own AOT/dex/odex output.
const Set<String> _appShortNames = {'base.apk', 'libapp.so'};

/// File extensions that mark the app's own compiled Dart/Java code.
const List<String> _appExtensions = ['.oat', '.dex', '.odex'];

/// Best-effort classification of a mapping path into a UI color-kind.
/// Takes the FULL module path (needs '/data/app/' + '!' to tell app vs
/// plugin). Rules are checked in order; the first match wins.
NativeModuleKind moduleKind(String module) {
  final lower = module.toLowerCase();
  final shortName = moduleShortName(module);

  // Rule 1: GPU driver first — these live under /vendor, which would
  // otherwise be misread as `system` by rule 4.
  if (_gpuDriverMarkers.any(lower.contains)) return NativeModuleKind.gpuDriver;

  // Rule 2: the Flutter/Dart engine itself.
  if (shortName == 'libflutter.so') return NativeModuleKind.engine;

  // Rule 3: the app's own dex/AOT code — but not an apk-embedded `!lib.so`.
  final isAppShortName =
      _appShortNames.contains(shortName) ||
      _appExtensions.any(shortName.endsWith);
  if (isAppShortName && !module.contains('!')) return NativeModuleKind.app;

  // Rule 4: AOSP platform/system libraries.
  final isSystemPath =
      lower.startsWith('/system/') ||
      lower.startsWith('/apex/') ||
      lower.startsWith('/vendor/') ||
      lower.contains('/bionic/');
  final isSystemLib =
      _systemLibShortNames.contains(shortName) ||
      shortName.startsWith('libandroid');
  if (isSystemPath || isSystemLib) return NativeModuleKind.system;

  // Rule 5: app-bundled third-party/plugin library.
  if (lower.contains('/data/app/') || module.contains('!')) {
    return NativeModuleKind.plugin;
  }

  // Rule 6: deliberate honest fallback — do not guess.
  return NativeModuleKind.unknown;
}
