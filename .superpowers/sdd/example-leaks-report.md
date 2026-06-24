# example-leaks: Implementation Report

## What was done

Turned `example/` into a full testbed for both the flutter_leak_radar runtime
detector and the flutter_leak_radar_lint custom_lint plugin.

## Workspace resolution fix

Removed `example` from the root `pubspec.yaml` `workspace:` array and dropped
`resolution: workspace` from `example/pubspec.yaml`. This lets `dart run
custom_lint` bootstrap properly in the example sub-package using standalone
pub resolution with path dependencies.

## Files changed / created

| File | Change |
|------|--------|
| `pubspec.yaml` (root) | Removed `example` from workspace array |
| `example/pubspec.yaml` | Standalone resolution; added `bloc`, `flutter_lints`, `flutter_leak_radar_lint`, `custom_lint` deps |
| `example/analysis_options.yaml` | Added `analyzer.plugins: [custom_lint]`; silenced `unused_field` and built-in `cancel_subscriptions`/`close_sinks` to avoid duplicate noise |
| `example/lib/main.dart` | Full wiring: overlay, navigatorObserver, AutoScan, maxLive+growth rules, 3-button home hub |
| `example/lib/leaky_screen.dart` | Rewritten — 6 lint patterns in one State class |
| `example/lib/leaky_cubit.dart` | New — pattern 7 (bloc_uncancelled_subscription) |
| `example/lib/leaky_bloc_screen.dart` | New — screen that creates LeakyCubit, tracks it, intentionally omits close() |
| `example/README.md` | Updated — documents all 7 patterns, commands, runtime setup |

## Lint output (dart run custom_lint)

```
lib/leaky_cubit.dart:14:66   bloc_uncancelled_subscription  .listen() in constructor, close() never overridden
lib/leaky_cubit.dart:17:28   uncancelled_subscription       _sub field never cancelled (also caught by general rule)
lib/leaky_screen.dart:25:31  undisposed_controller          _textController (TextEditingController) never disposed
lib/leaky_screen.dart:28:28  uncancelled_subscription       _subscription never cancelled
lib/leaky_screen.dart:31:10  uncancelled_timer              _timer never cancelled
lib/leaky_screen.dart:34:31  unclosed_stream_controller     _streamController never closed
lib/leaky_screen.dart:54:30  discarded_listen_result        bare _streamController.stream.listen((_) {})
lib/leaky_screen.dart:57:15  missing_remove_listener        _notifier.addListener(_onNotifierChanged) without removeListener

8 warnings (all 7 rules fire; uncancelled_subscription fires twice — once on the
Cubit field via the general rule, once on the bloc constructor listen via the
bloc-specific rule).
```

`flutter analyze` reports: **No issues found.**

## Notes on pattern choices

- **missing_remove_listener** requires a named callback (tear-off), not an inline
  closure, because the rule only fires on referenceable identities.
  `ValueNotifier` is used (not `AnimationController`) because the rule suppresses
  receivers that are already covered by `undisposed_controller`.
- **discarded_listen_result** requires the `.listen()` result to be a bare
  ExpressionStatement — no assignment, no await. The call on
  `_streamController.stream` in `initState()` satisfies this exactly.
- **bloc_uncancelled_subscription** only fires for classes that extend `BlocBase`
  (`Cubit`/`Bloc`). It checks `.listen()` calls inside the constructor body.
