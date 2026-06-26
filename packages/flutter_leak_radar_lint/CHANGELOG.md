## 0.1.1

- Packaging fix: the published pubspec no longer carries `resolution: workspace`,
  which had prevented pub.dev's package analysis from resolving the package
  standalone (it showed "incomplete analysis" with 0 static-analysis points). No
  rule or behaviour changes — the lint rules are identical to 0.1.0.
- Added an `example/README.md` documenting enablement and what each rule catches.

## 0.1.0

Initial release.

Seven `custom_lint` rules for common Flutter/Dart memory-leak patterns:

- `undisposed_controller` — Flutter controller or `FocusNode` field not disposed
  in `dispose()`. Auto-fix available.
- `uncancelled_subscription` — `StreamSubscription` field not cancelled in
  teardown. Auto-fix available.
- `uncancelled_timer` — `Timer` field not cancelled in teardown. Auto-fix
  available.
- `unclosed_stream_controller` — `StreamController` field not closed in
  teardown. Auto-fix available.
- `missing_remove_listener` — `addListener` call without a matching
  `removeListener` in the teardown path.
- `bloc_uncancelled_subscription` — `.listen()` in a `BlocBase` constructor
  with no cancel in the subscription lifecycle.
- `discarded_listen_result` — bare `stream.listen()` call whose
  `StreamSubscription` return value is discarded.

All rules emit `WARNING` severity. Rules with auto-fixes synthesise or update
`dispose()` bodies; `close()` teardowns require manual method creation first.
