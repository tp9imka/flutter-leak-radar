/// `dart:io`-backed helpers for `package:leak_graph`.
///
/// The main `package:leak_graph/leak_graph.dart` barrel is pure Dart so it
/// stays safe to import from web-hosted consumers (e.g. a DevTools
/// extension). Anything that needs file-system access — such as detecting
/// the app's own package names from a project directory, for feeding
/// `AppPackageSet`/`OriginClassifier` an explicit config instead of relying on
/// auto-detection — lives here instead, behind an opt-in import.
library;

export 'src/io/project_packages_io.dart';
