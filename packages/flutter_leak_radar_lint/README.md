# flutter_leak_radar_lint

A [`custom_lint`](https://pub.dev/packages/custom_lint) plugin that detects common Flutter memory-leak patterns at analysis time.

## Rules

| Rule | Severity | Description |
|---|---|---|
| `undisposed_controller` | WARNING | A Flutter controller (`TextEditingController`, `AnimationController`, etc.) is created in a `State` but never disposed in `dispose()`. |
| `uncancelled_subscription` | WARNING | A `StreamSubscription` field is never cancelled in `dispose()` / `close()`. |
| `uncancelled_timer` | WARNING | A `Timer` field is never cancelled in `dispose()` / `close()`. |
| `discarded_listen_result` | WARNING | The `StreamSubscription` returned by `.listen()` is discarded and can never be cancelled. |

## Installation

Add the plugin as a `dev_dependency` in your `pubspec.yaml`:

```yaml
dev_dependencies:
  custom_lint: ^0.8.1
  flutter_leak_radar_lint:
    path: ../flutter_leak_radar_lint   # or pub.dev version once published
```

Enable it in your `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - custom_lint
```

Run the analyzer:

```sh
dart run custom_lint
```

## Suppression

Suppress a specific lint on a line with an `// ignore` comment:

```dart
// ignore: undisposed_controller
final _controller = TextEditingController();
```

Or suppress for a whole file:

```dart
// ignore_for_file: discarded_listen_result
```

## Quick Fixes

`undisposed_controller`, `uncancelled_subscription`, and `uncancelled_timer` all ship with IDE quick-fixes that insert the missing teardown call (or synthesise a `dispose()` override) automatically.

## Known limitations / suppression

Rules scan the teardown method body **directly**. If your teardown delegates to a helper method, the lint cannot follow the call and may false-positive:

```dart
@override
void dispose() {
  _disposeAll(); // helper — lint cannot see inside
  super.dispose();
}
```

In that case, suppress the lint on the field declaration:

```dart
// ignore: uncancelled_subscription
StreamSubscription<int>? _sub;
```

Auto-fix synthesis is intentionally limited to `dispose()` (and other synchronous teardowns). When the detected teardown is `close()` — which returns `Future<void>` — no new method is synthesised because a naive sync body would be incorrect. If your class has no `close()` yet, add it manually and re-run the quick-fix to insert the cancel call into the existing method.
