// test/widgets/radar_stack_list_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarStackList', () {
    testWidgets('renders frame text, module, and trailing tag', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarStackList(
              frames: [
                RadarStackFrame(text: 'malloc', module: 'libc.so'),
                RadarStackFrame(
                  text: 'Foo::bar',
                  module: 'libflutter.so',
                  tag: Text('module-only'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('malloc'), findsOneWidget);
      expect(find.text('Foo::bar'), findsOneWidget);
      expect(find.text('libc.so'), findsOneWidget);
      expect(find.text('libflutter.so'), findsOneWidget);
      expect(find.text('module-only'), findsOneWidget);
    });

    testWidgets('empty frames shows a placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RadarStackList(frames: [])),
        ),
      );

      expect(find.text('no frames'), findsOneWidget);
    });
  });
}
