// test/fixtures/missing_remove_listener/bad.dart
import 'package:flutter/widgets.dart';

// addListener with a tear-off, no removeListener in dispose().
class _BadState extends State<StatefulWidget> {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // expect_lint: missing_remove_listener
    _notifier.addListener(_onChange);
  }

  void _onChange() {}

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// addListener with a tear-off; dispose() removes a DIFFERENT callback.
class _BadWrongCallbackState extends State<StatefulWidget> {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // expect_lint: missing_remove_listener
    _notifier.addListener(_onChange);
  }

  void _onChange() {}
  void _other() {}

  @override
  void dispose() {
    _notifier.removeListener(_other);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
