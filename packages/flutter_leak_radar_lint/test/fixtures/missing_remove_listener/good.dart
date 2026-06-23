// test/fixtures/missing_remove_listener/good.dart
import 'package:flutter/widgets.dart';

// Good: matching removeListener(_onChange) in dispose().
class _GoodState extends State<StatefulWidget> {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _notifier.addListener(_onChange);
  }

  void _onChange() {}

  @override
  void dispose() {
    _notifier.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: removeListener inside an if-block in dispose() — recursive walk.
class _GoodConditionalState extends State<StatefulWidget> {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _notifier.addListener(_onChange);
  }

  void _onChange() {}

  @override
  void dispose() {
    if (_active) {
      _notifier.removeListener(_onChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: removed in deactivate() instead of dispose() — both are accepted.
class _GoodDeactivateState extends State<StatefulWidget> {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _notifier.addListener(_onChange);
  }

  void _onChange() {}

  @override
  void deactivate() {
    _notifier.removeListener(_onChange);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good (conservative skip): inline closure has no referenceable identity, so it
// is NEVER flagged even though it is never removed. False negative by design.
class _ClosureState extends State<StatefulWidget> {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _notifier.addListener(() {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good (suppressed): an AnimationController is a disposable controller already
// covered by undisposed_controller; we do NOT double-report missing
// removeListener (dispose() drops its listeners).
class _AnimControllerState extends State<StatefulWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: Duration.zero,
  );

  @override
  void initState() {
    super.initState();
    _anim.addListener(_onTick);
  }

  void _onTick() {}

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good (out of scope): a plain Dart class has no known teardown contract.
class PlainNotifierHolder {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  PlainNotifierHolder() {
    _notifier.addListener(_onChange);
  }

  void _onChange() {}
}

// Good (not a Flutter Listenable): a user-defined addListener on an unrelated
// type must not be flagged.
class _CustomBus {
  void addListener(void Function() cb) {}
}

class _UnrelatedAddListenerState extends State<StatefulWidget> {
  final _CustomBus _bus = _CustomBus();

  @override
  void initState() {
    super.initState();
    _bus.addListener(_onChange);
  }

  void _onChange() {}

  @override
  Widget build(BuildContext context) => const SizedBox();
}
