# flutter_leak_radar example

Full testbed for both the **runtime detector** and the **custom lint plugin**.
The macOS runner is committed — no `flutter create` prerequisite needed.

## Running the app

```bash
cd example && flutter run -d macos --profile
```

The home screen has three buttons:

| Button | What it opens |
|--------|---------------|
| Open Leaky Screen (patterns 1–6) | `leaky_screen.dart` — all six State-lifecycle leak shapes |
| Open Leaky Bloc Screen (pattern 7) | `leaky_bloc_screen.dart` + `leaky_cubit.dart` — bloc constructor subscription leak |
| Open Leak Radar Dashboard | Built-in `LeakRadarScreen` showing live heap findings |

Push a leaky screen, pop back, and the **navigation-triggered scan** fires automatically
(debounced 500 ms). The overlay FAB also lets you trigger a manual scan at any time.
A **periodic scan** runs every 20 seconds in the background.

## Seeing the lint rules

> ⚠️ **`flutter analyze` / `dart analyze` will NOT show these.** `custom_lint` rules don't
> surface through the CLI analyzer (it doesn't run analyzer plugins) — so `flutter analyze`
> correctly reports "No issues found" even though the leaks below are flagged. This is by
> design, not a bug. You see the rules two ways:

**1. CLI — the `custom_lint` runner:**

```bash
cd example && dart run custom_lint
```

All 7 rules fire (8 diagnostics):

| File | Rule | Pattern |
|------|------|---------|
| `leaky_screen.dart` | `undisposed_controller` | `_textController` (TextEditingController) never disposed |
| `leaky_screen.dart` | `uncancelled_subscription` | `_subscription` (StreamSubscription) never cancelled |
| `leaky_screen.dart` | `uncancelled_timer` | `_timer` (Timer.periodic) never cancelled |
| `leaky_screen.dart` | `unclosed_stream_controller` | `_streamController` never closed |
| `leaky_screen.dart` | `discarded_listen_result` | bare `_streamController.stream.listen((_) {})` |
| `leaky_screen.dart` | `missing_remove_listener` | `_notifier.addListener(_onNotifierChanged)` without `removeListener` |
| `leaky_cubit.dart` | `bloc_uncancelled_subscription` | `stream.listen(emit)` in constructor, `close()` not overridden |

**2. IDE — editor squiggles:** open `example/` in VS Code or IntelliJ and the rules show as
warning underlines in `leaky_screen.dart` / `leaky_cubit.dart` (the plugin is enabled via
`analysis_options.yaml`). If they don't appear, run `dart pub get` in `example/` and restart
the Dart analysis server (VS Code: **Dart: Restart Analysis Server**, or **Reload Window**).

## Runtime detector setup

`main.dart` wires the detector with:

- `AutoScan(onNavigation: true, period: Duration(seconds: 20))` — scans after each pop and every 20 s
- `LeakRadar.navigatorObserver` added to `MaterialApp.navigatorObservers`
- `LeakRadar.overlay(child: …)` wrapping `MaterialApp` for the floating scan FAB
- `LeakRule.maxLive('_LeakyScreenState', 1)` — flags if more than 1 instance is live
- `LeakRule.growth('LeakyCubit')` — flags any growth of LeakyCubit instances
- `LeakRadar.track(this, tag: '…')` inside `initState` of each leaky class for precise tracking
