import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import 'src/app/bootstrap.dart';
import 'src/shell/desktop_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrapWindow();
  runApp(const RadarDesktopApp());
}

class RadarDesktopApp extends StatelessWidget {
  const RadarDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Radar Desktop',
      theme: radarDarkTheme(),
      home: const DesktopShell(),
    );
  }
}
