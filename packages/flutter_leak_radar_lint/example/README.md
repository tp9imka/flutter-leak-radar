# flutter_leak_radar_lint example

This example is a small Flutter package whose `lib/` holds intentionally leaky
(and correctly-cleaned-up) widgets — one folder per rule — so you can see each
lint fire in your IDE and try the auto-fixes:

```
lib/
├── undisposed_controller/        # controller/FocusNode never disposed
├── uncancelled_subscription/     # StreamSubscription never cancelled
├── uncancelled_timer/            # Timer never cancelled
├── unclosed_stream_controller/   # StreamController never closed
├── missing_remove_listener/      # addListener with no removeListener
├── discarded_listen_result/      # stream.listen(...) result discarded
└── bloc_uncancelled_subscription/ # subscription in a Bloc/Cubit not cancelled
```

## Enable the plugin

```yaml
# pubspec.yaml
dev_dependencies:
  custom_lint: ^0.8.1
  flutter_leak_radar_lint: ^0.1.0
```

```yaml
# analysis_options.yaml
analyzer:
  plugins:
    - custom_lint
```

Then run `dart run custom_lint` (or just open the files in your IDE).

## What a rule catches

```dart
// FLAGGED by `undisposed_controller`: created in a State, never disposed.
class _BadState extends State<MyWidget> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) => TextField(controller: _controller);
}
```

```dart
// OK: disposed in dispose().
class _GoodState extends State<MyWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: _controller);
}
```

Most rules ship an auto-fix — invoke your IDE's quick-fix on the highlighted
field to insert the matching `dispose()` / `cancel()` / `close()` call.
