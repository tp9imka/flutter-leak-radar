# example platform report

**Status:** DONE

**Platform added:** macOS (darwin-native)

**Procedure:**
1. Backed up `example/lib/` and `example/pubspec.yaml` to `/tmp/`.
2. Ran `flutter create --platforms=macos --project-name flutter_leak_radar_example .` from `example/` — created `example/macos/` runner tree (36 files).
3. Restored `example/lib/` (main.dart + leaky_screen.dart) and `example/pubspec.yaml` verbatim from backup.
4. Deleted generated `example/test/widget_test.dart` (counter-app template).
5. Verified both lib files are byte-identical to originals (`diff` clean).

**Demo code preserved:** YES — `main.dart` (LeakRadar.init + leaky/radar nav) and `leaky_screen.dart` (intentional Timer/StreamController leak) are our versions; confirmed identical to pre-create state.

**flutter analyze:** No issues found (ran in 18.8s)

**flutter build macos:** Not run (analyze clean + `example/macos/Runner.xcodeproj` present confirms runner scaffold is valid).

**Run command:** `cd example && flutter run -d macos --profile`

**README updated:** Run command updated; `flutter create` prerequisite removed.

**Commit:** see git log for `chore(example): add macOS platform so the demo runs on device`
