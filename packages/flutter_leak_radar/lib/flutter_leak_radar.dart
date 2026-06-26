// packages/flutter_leak_radar/lib/flutter_leak_radar.dart
/// On-device, zero-config memory-leak detector for Flutter.
library;

export 'src/leak_radar.dart' show LeakRadar, LeakExportFormat;
export 'src/config/leak_radar_config.dart' show LeakRadarConfig, AutoScan;
export 'src/config/graph_scan.dart' show GraphScan;
export 'src/config/leak_rule.dart' show LeakRule, LeakDetectionMode;
export 'src/config/suspect_set.dart' show SuspectSet;
export 'src/model/leak_report.dart' show LeakReport;
export 'src/model/leak_finding.dart' show LeakFinding;
export 'src/model/retaining_path.dart' show RetainingPathView, RetainingHop;
export 'src/model/leak_kind.dart' show LeakKind, LeakSeverity, LeakRadarStatus;
export 'src/util/rate_limited_logger.dart' show LeakLogLevel;
export 'src/ui/export_sheet.dart' show LeakExportSheet;
export 'src/ui/leak_radar_screen.dart' show LeakRadarScreen;
export 'src/ui/leak_radar_view.dart' show LeakRadarView;
export 'src/ui/finding_detail_screen.dart' show FindingDetailScreen;
export 'src/ui/leak_radar_overlay.dart' show LeakRadarOverlay;
export 'src/ui/settings_screen.dart' show SettingsScreen;
export 'src/triggers/navigator_observer.dart' show LeakRadarNavigatorObserver;
export 'src/engine/vm_service_status.dart';
