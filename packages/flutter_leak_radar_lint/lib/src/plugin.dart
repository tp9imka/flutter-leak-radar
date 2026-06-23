import 'package:custom_lint_builder/custom_lint_builder.dart';

/// The custom_lint plugin for flutter_leak_radar.
///
/// [getLintRules] returns all enabled rules. custom_lint handles per-rule
/// enable/disable via the consumer's `analysis_options.yaml`
/// `custom_lint: rules:` block automatically.
class FlutterLeakRadarPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [];
}
