// test/fixtures/undisposed_controller/good.dart
import 'package:flutter/widgets.dart';

// Good: controller is disposed in dispose().
class _GoodState extends State<StatefulWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: late field never initialized (not owned).
class _GoodLateState extends State<StatefulWidget> {
  late TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: controller passed in via constructor (not owned here).
class _GoodParamState extends State<StatefulWidget> {
  _GoodParamState(this._controller);
  final TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: controller disposed inside an if-block in dispose().
class _GoodIfBlockState extends State<StatefulWidget> {
  final _controller = TextEditingController();
  bool _active = true;

  @override
  void dispose() {
    if (_active) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: field formal parameter (this._controller) — externally owned, should NOT be flagged
// even though there is no dispose() override.
class _GoodFieldFormalParamState extends State<StatefulWidget> {
  _GoodFieldFormalParamState(this._controller);
  final TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
