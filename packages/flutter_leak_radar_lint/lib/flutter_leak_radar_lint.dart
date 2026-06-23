import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'src/plugin.dart';

/// Entry point discovered by the custom_lint runner via reflection.
/// The function name and signature are fixed — do not rename.
PluginBase createPlugin() => FlutterLeakRadarPlugin();
