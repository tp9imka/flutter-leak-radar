// test/fixtures/undisposed_controller/bad.dart
import 'package:flutter/widgets.dart';

class _BadState extends State<StatefulWidget> {
  // A TextEditingController owned and never disposed.
  // expect_lint: undisposed_controller
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _AlsoBadState extends State<StatefulWidget> {
  // AnimationController stored in a field but dispose() not overridden.
  // expect_lint: undisposed_controller
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: const _NeverTick(), duration: Duration.zero);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Inferred-type field: `final _c = TextEditingController()` has no explicit type
// annotation. The rule must resolve the type from the initializer's static type.
class _InferredTypeBadState extends State<StatefulWidget> {
  // expect_lint: undisposed_controller
  final _c = TextEditingController();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _NeverTick implements TickerProvider {
  const _NeverTick();
  @override
  Ticker createTicker(TickerCallback _) => throw UnimplementedError();
}
