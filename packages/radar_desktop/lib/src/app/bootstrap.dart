import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Initializes the frameless window. macOS keeps its traffic-light buttons
/// (`TitleBarStyle.hidden` hides only the title text/bar chrome, not the
/// window buttons); a custom title bar is drawn by [DesktopWindowChrome].
///
/// No-op on non-desktop targets (e.g. the VM test host), so widget tests never
/// touch the plugin.
Future<void> bootstrapWindow() async {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.macOS &&
      defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.linux) {
    return;
  }
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1180, 760),
    minimumSize: Size(920, 600),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
    title: 'Radar Desktop',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
