import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarSearchField', () {
    testWidgets('renders with default hint text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RadarSearchField(onChanged: (_) {})),
        ),
      );
      expect(find.byType(RadarSearchField), findsOneWidget);
      expect(find.text('filter…'), findsOneWidget);
    });

    testWidgets('calls onChanged when text is entered', (tester) async {
      String? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarSearchField(onChanged: (v) => captured = v),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'chat');
      expect(captured, 'chat');
    });

    testWidgets('renders custom hint', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarSearchField(
              onChanged: (_) {},
              hint: 'filter class / library',
            ),
          ),
        ),
      );
      expect(find.text('filter class / library'), findsOneWidget);
    });
  });
}
