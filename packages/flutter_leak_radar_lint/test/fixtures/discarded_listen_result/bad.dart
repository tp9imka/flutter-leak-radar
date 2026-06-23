// test/fixtures/discarded_listen_result/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _BadState extends State<StatefulWidget> {
  @override
  void initState() {
    super.initState();
    // .listen() return value is discarded — subscription leaks.
    Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
