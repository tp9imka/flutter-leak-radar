# pub.dev Publish Prep Report

**Branch**: `feat/publish-prep`
**Date**: 2026-06-24
**Status**: Complete — all deliverables done, both packages analyze clean, dartdoc 0 warnings/0 errors.

---

## Commits

| SHA | Subject |
|---|---|
| `1e146f2` | `docs: add READMEs, CHANGELOGs, pubspec metadata, dartdoc comments, and MIT LICENSE` |

---

## Files Created

| File | Notes |
|---|---|
| `LICENSE` | MIT, owner `tp9imka`, year 2026 (see note below) |
| `packages/flutter_leak_radar/README.md` | New — install, quickstart, config reference, manual tracking, export, DevTools comparison |
| `packages/flutter_leak_radar/CHANGELOG.md` | Initial `## 0.0.1` entry |
| `packages/flutter_leak_radar/LICENSE` | Copy of root MIT LICENSE |
| `packages/flutter_leak_radar_lint/CHANGELOG.md` | Initial `## 0.1.0` entry |
| `packages/flutter_leak_radar_lint/LICENSE` | Copy of root MIT LICENSE |

## Files Updated

| File | Changes |
|---|---|
| `README.md` | Rewritten as monorepo overview with quick-start, package table, docs pointer |
| `packages/flutter_leak_radar/pubspec.yaml` | `<owner>` → `tp9imka`; added `homepage`, `issue_tracker`, `topics`; description refined to pub.dev length range |
| `packages/flutter_leak_radar_lint/pubspec.yaml` | `<owner>` → `tp9imka`; removed `publish_to: none`; added `homepage`, `issue_tracker`, `topics`; description refined |
| `packages/flutter_leak_radar_lint/README.md` | Rewritten — all 7 rules with auto-fix column, integration steps, suppression, known limitations |
| `packages/flutter_leak_radar/lib/src/leak_radar.dart` | `///` docs on `init`, `scan`, `track`, `markDisposed`, `reports`, `latest`, `status`, `dispose`, `LeakExportFormat` enum values |
| `packages/flutter_leak_radar/lib/src/config/leak_radar_config.dart` | `///` docs on `AutoScan`, `LeakRadarConfig`, all fields |
| `packages/flutter_leak_radar/lib/src/config/leak_rule.dart` | `///` docs on `LeakRule`, all factories, all fields |
| `packages/flutter_leak_radar/lib/src/config/suspect_set.dart` | `///` docs on `SuspectSet`, all constructors, `rules` field |
| `packages/flutter_leak_radar/lib/src/model/leak_kind.dart` | `///` docs on all three enums and every value |
| `packages/flutter_leak_radar/lib/src/model/leak_finding.dart` | `///` docs on `LeakFinding`, all fields, `withRetainingPath` |
| `packages/flutter_leak_radar/lib/src/model/leak_report.dart` | `///` docs on `LeakReport`, all fields, `hasLeaks`, `worstSeverity` |
| `packages/flutter_leak_radar/lib/src/model/retaining_path.dart` | `///` docs on `RetainingHop`, `RetainingPathView`, all fields |
| `packages/flutter_leak_radar/lib/src/triggers/navigator_observer.dart` | Fixed unresolved `[NavigatorState.widget.observers]` dartdoc reference |

---

## Analyze Results

```
flutter analyze packages/flutter_leak_radar
  → No issues found!

dart analyze packages/flutter_leak_radar_lint
  → No issues found!
```

---

## dartdoc

Run from `packages/flutter_leak_radar/` via `dart doc .`:

```
Found 0 warnings and 0 errors.
Documented 1 public library in ~13s
```

Generated output at `packages/flutter_leak_radar/doc/api/` (not committed — add to .gitignore if needed).

Note: `dart doc` was not run on `flutter_leak_radar_lint` — it is an analyzer plugin package with no public Dart API surface intended for dartdoc consumers.

pana was not run (`dart pub global activate pana` was not performed per task constraints).

---

## LICENSE Note

The MIT license uses `tp9imka` as the copyright owner (matching the GitHub username in the repository URL). This is a placeholder — **the actual owner should confirm the correct legal name before publishing to pub.dev**.

To update: edit `LICENSE` at the repo root and re-copy to `packages/flutter_leak_radar/LICENSE` and `packages/flutter_leak_radar_lint/LICENSE`.

---

## Pre-publish Checklist Remaining

Before running `dart pub publish` on either package:

- [ ] Confirm LICENSE owner name is correct
- [ ] Run `dart pub publish --dry-run` on both packages to catch any remaining pub.dev score issues
- [ ] Optionally run `dart pub global activate pana && pana .` in each package for a full score report
- [ ] Ensure `packages/flutter_leak_radar/doc/api/` is in `.gitignore`
- [ ] Tag the release (e.g. `flutter_leak_radar-v0.0.1`) if using GitHub releases
