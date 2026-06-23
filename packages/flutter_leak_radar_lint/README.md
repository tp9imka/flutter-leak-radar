# flutter_leak_radar_lint

[![pub.dev](https://img.shields.io/pub/v/flutter_leak_radar_lint.svg)](https://pub.dev/packages/flutter_leak_radar_lint)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A [`custom_lint`](https://pub.dev/packages/custom_lint) plugin that detects
common Flutter/Dart memory-leak patterns at analysis time — in your IDE and in
CI — before they reach a running app.

---

## Rules

| Rule | Severity | Auto-fix | Description |
|---|---|---|---|
| `undisposed_controller` | WARNING | Yes | A Flutter controller or `FocusNode` field is created in a `State` but never disposed in `dispose()`. |
| `uncancelled_subscription` | WARNING | Yes | A `StreamSubscription` field is never cancelled in `dispose()` or `close()`. |
| `uncancelled_timer` | WARNING | Yes | A `Timer` field is never cancelled in `dispose()` or `close()`. |
| `unclosed_stream_controller` | WARNING | Yes | A `StreamController` field is never closed in `dispose()` or `close()`. |
| `missing_remove_listener` | WARNING | No | `addListener` is called without a matching `removeListener` in the teardown. |
| `bloc_uncancelled_subscription` | WARNING | No | A `.listen()` call inside a `BlocBase` constructor produces a subscription that is never cancelled. |
| `discarded_listen_result` | WARNING | No | The `StreamSubscription` returned by a bare `stream.listen()` call is discarded and can never be cancelled. |

---

## Installation

Add the plugin as a dev dependency:

```yaml
# pubspec.yaml
dev_dependencies:
  custom_lint: ^0.8.1
  flutter_leak_radar_lint: ^0.1.0
```

Enable it in your analysis options:

```yaml
# analysis_options.yaml
analyzer:
  plugins:
    - custom_lint
```

Run the analyzer:

```sh
dart run custom_lint
```

Your IDE (VS Code with the Dart extension, IntelliJ / Android Studio) will also
show findings inline as warnings once the plugin is enabled.

---

## Auto-fixes

`undisposed_controller`, `uncancelled_subscription`, `uncancelled_timer`, and
`unclosed_stream_controller` ship with IDE quick-fixes. The fix inserts the
missing teardown call into the existing `dispose()` method, or synthesises a
`dispose()` override if the class does not have one yet.

Auto-fix synthesis is limited to `dispose()` and other synchronous teardowns.
When the detected teardown is `close()` — which returns `Future<void>` — no
new method is synthesised because a naive synchronous body would be incorrect.
Add the `close()` method manually, then re-run the quick-fix to insert the
cancel call into the existing body.

---

## Suppression

Suppress a rule on a single line:

```dart
// ignore: undisposed_controller
final _controller = TextEditingController();
```

Suppress a rule for an entire file:

```dart
// ignore_for_file: discarded_listen_result
```

---

## Known limitations

Rules scan teardown method bodies **directly**. If teardown delegates to a
private helper method, the lint cannot follow the call and may produce a false
positive:

```dart
@override
void dispose() {
  _disposeAll(); // helper — lint cannot see inside this call
  super.dispose();
}
```

Suppress the false positive on the field declaration:

```dart
// ignore: uncancelled_subscription
StreamSubscription<int>? _sub;
```

---

## Runtime companion

Pair this plugin with
[`flutter_leak_radar`](../flutter_leak_radar/) to catch leaks that slip through
static analysis at runtime — with a visual overlay, heap-growth tracking, and
shareable reports.

---

## License

MIT — see [LICENSE](../../LICENSE).
