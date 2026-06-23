// test/fixtures/unclosed_stream_controller/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

// Good: controller closed in dispose().
class _GoodState extends State<StatefulWidget> {
  final _controller = StreamController<int>();

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: closed inside an if-block — disposedInTeardown is recursive.
class _GoodConditionalCloseState extends State<StatefulWidget> {
  final _controller = StreamController<int>();
  bool _active = true;

  @override
  void dispose() {
    if (_active) {
      _controller.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: closed inside a try-block.
class _GoodTryCloseState extends State<StatefulWidget> {
  final _controller = StreamController<int>();

  @override
  void dispose() {
    try {
      _controller.close();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: cascade form _controller..close().
class _GoodCascadeState extends State<StatefulWidget> {
  final _controller = StreamController<int>();

  @override
  void dispose() {
    _controller..close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: local-variable controller — never stored in a field; not flagged.
class _LocalControllerState extends State<StatefulWidget> {
  @override
  void initState() {
    super.initState();
    // ignore: unused_local_variable
    final controller = StreamController<int>();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: constructor-injected via field-formal (this._controller) — externally
// owned; the State must NOT close it.
class _GoodFieldFormalState extends State<StatefulWidget> {
  _GoodFieldFormalState(this._controller);
  final StreamController<int> _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: constructor-injected via named simple parameter (matching the existing
// name-based isConstructorParam suppression: param name == field name) — also
// externally owned.
class _GoodParamState extends State<StatefulWidget> {
  _GoodParamState(StreamController<String> _controller)
    : _controller = _controller;
  final StreamController<String> _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: a StreamController field in a plain Dart class (not State / BlocBase)
// is NOT flagged — the rule only applies to classes with a known teardown.
class PlainService {
  final _controller = StreamController<int>();

  void stop() {
    _controller.close();
  }
}
