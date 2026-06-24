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
(debounced 500 ms). The overlay badge also lets you trigger a manual scan at any time.
A **periodic scan** runs every 8 seconds in the background.

### What you'll see

The detector reports leaks two complementary ways:

- **Precise tracking — flags on a single navigation.** Each leaky class calls
  `LeakRadar.track(this, …)` on create and `LeakRadar.markDisposed(this)` in `dispose()`.
  Because the screen deliberately leaves a `Timer`/subscription running, the object stays
  alive after it should have been freed — so it surfaces as a **critical "not GCed" finding
  after just one push-and-pop**. (The demo tunes this to 1 GC cycle + 1 s grace so it
  appears within a scan or two; production defaults to 3 cycles / 2 s.)
- **Heap growth — needs repeated navigation.** `LeakRule.maxLive('_LeakyScreenState', 1)`
  and `LeakRule.growth('LeakyCubit')` are count-based: a single retained instance sits at
  the threshold and won't trip. **Open a leaky screen and pop back 2–3 times** to watch the
  instance count climb and growth-based findings appear.

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

- `AutoScan(onNavigation: true, period: Duration(seconds: 8))` — scans after each pop and every 8 s
- `gcCyclesForPreciseLeak: 1`, `disposalGrace: Duration(seconds: 1)` — fast precise reporting for the demo
- `LeakRadar.navigatorObserver` added to `MaterialApp.navigatorObservers`
- `LeakRadar.overlay(child: …)` wrapping `MaterialApp` for the floating scan badge
- `LeakRule.maxLive('_LeakyScreenState', 1)` — flags if more than 1 instance is live (needs repeated visits)
- `LeakRule.growth('LeakyCubit')` — flags growth of LeakyCubit instances (needs repeated visits)
- `LeakRadar.track(this, tag: '…')` in `initState` + `LeakRadar.markDisposed(this)` in `dispose()` — the precise path that flags a single retained instance
