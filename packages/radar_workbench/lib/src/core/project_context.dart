/// The seam between a host (DevTools / desktop) and the workbench for the
/// developer's project identity: which packages are "yours" and how to open a
/// source library in an editor.
///
/// Kept alongside [RadarConnection] so both hosts wire it the same way. Views
/// use [projectPackages] to classify a hop's origin (the "yours" highlight),
/// show [sourceLabel] verbatim (honesty: never claim a detection that didn't
/// happen), and call [openSource] to jump to a file on hosts that can.
library;

/// Host-provided project identity for origin attribution and source opening.
abstract interface class ProjectContext {
  /// The project-owned package names (e.g. `{'my_app'}`). May be empty when
  /// the host could not resolve any — treated as "unknown", never guessed.
  Future<Set<String>> projectPackages();

  /// How [projectPackages] was resolved, shown verbatim in the UI:
  /// `'workspace'` | `'pubspec.lock'` | `'manual'` | `'none'`.
  String get sourceLabel;

  /// Whether [openSource] can actually launch an editor on this host. Drives
  /// whether the UI offers an open affordance at all — DevTools (copy-only)
  /// leaves this `false` so no dead "open" button appears.
  bool get canOpenSource => false;

  /// Opens [libraryUri]'s source in the developer's editor, returning whether
  /// it launched. Defaults to `false` (unsupported) — only desktop overrides.
  Future<bool> openSource(Uri libraryUri) => Future.value(false);
}

/// The no-op default: no project packages, nothing to open. Used by hosts and
/// tests that have no project identity to offer.
class NoProjectContext implements ProjectContext {
  const NoProjectContext();

  @override
  Future<Set<String>> projectPackages() async => const {};

  @override
  String get sourceLabel => 'none';

  @override
  bool get canOpenSource => false;

  @override
  Future<bool> openSource(Uri libraryUri) => Future.value(false);
}

/// Wraps a [base] context with a user-supplied manual override.
///
/// When [manualPackages] is non-empty it TRUMPS detection: [projectPackages]
/// returns it and [sourceLabel] reads `'manual'`. Otherwise both defer to
/// [base]. [openSource] always delegates to [base] — an override changes only
/// which packages count as "yours", not how files open.
class OverridableProjectContext implements ProjectContext {
  const OverridableProjectContext(this.base, {this.manualPackages = const {}});

  final ProjectContext base;
  final Set<String> manualPackages;

  @override
  Future<Set<String>> projectPackages() async =>
      manualPackages.isNotEmpty ? manualPackages : base.projectPackages();

  @override
  String get sourceLabel =>
      manualPackages.isNotEmpty ? 'manual' : base.sourceLabel;

  @override
  bool get canOpenSource => base.canOpenSource;

  @override
  Future<bool> openSource(Uri libraryUri) => base.openSource(libraryUri);
}
