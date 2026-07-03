// test/widgets/radar_module_dot_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarModuleDot', () {
    testWidgets('renders label text and colored box', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarModuleDot(color: RadarColors.info, label: 'App'),
          ),
        ),
      );

      expect(find.text('App'), findsOneWidget);

      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(RadarModuleDot),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, RadarColors.info);
    });

    testWidgets('renders no text when label is omitted', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RadarModuleDot(color: RadarColors.warning)),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(RadarModuleDot),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    });

    testWidgets('default size is 8', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RadarModuleDot(color: RadarColors.accent)),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(RadarModuleDot),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(sizedBox.width, 8.0);
      expect(sizedBox.height, 8.0);
    });
  });
}
