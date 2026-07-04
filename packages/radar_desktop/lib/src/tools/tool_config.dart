/// User-set external tool paths, persisted as JSON. Immutable — use
/// [withPath] to derive an updated copy rather than mutating in place.
final class ToolConfig {
  const ToolConfig(this.pathByToolId);

  /// Keyed by `ExternalTool.id` (e.g. `'trace_processor'`), valued by the
  /// absolute path the user located it at.
  final Map<String, String> pathByToolId;

  /// Parses a config previously written by [toJson]. Tolerant of a
  /// missing or malformed `pathByToolId` (returns an empty config), and
  /// drops any entry whose value isn't a string, so a corrupted or
  /// hand-edited file degrades gracefully instead of throwing.
  factory ToolConfig.fromJson(Map<String, Object?> json) {
    final raw = json['pathByToolId'];
    if (raw is! Map<String, Object?>) return const ToolConfig({});
    return ToolConfig({
      for (final entry in raw.entries)
        if (entry.value is String) entry.key: entry.value as String,
    });
  }

  Map<String, Object?> toJson() => {'pathByToolId': pathByToolId};

  /// Returns a new config with [toolId] pointing at [path], leaving
  /// every other entry unchanged.
  ToolConfig withPath(String toolId, String path) =>
      ToolConfig({...pathByToolId, toolId: path});
}
