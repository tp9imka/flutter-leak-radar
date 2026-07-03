// test/widgets/radar_expandable_row_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  group('RadarExpandableRow', () {
    testWidgets('hides child initially when collapsed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarExpandableRow(
              header: Text('mod'),
              child: Text('callsite'),
            ),
          ),
        ),
      );

      expect(find.text('mod'), findsOneWidget);
      expect(find.text('callsite'), findsNothing);
    });

    testWidgets('tap expands and reveals child', (tester) async {
      bool? expanded;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarExpandableRow(
              header: const Text('mod'),
              child: const Text('callsite'),
              onExpansionChanged: (value) => expanded = value,
            ),
          ),
        ),
      );

      await tester.tap(find.text('mod'));
      await tester.pumpAndSettle();

      expect(find.text('callsite'), findsOneWidget);
      expect(expanded, isTrue);
    });

    testWidgets('tap again collapses and hides child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarExpandableRow(
              header: Text('mod'),
              initiallyExpanded: true,
              child: Text('callsite'),
            ),
          ),
        ),
      );

      expect(find.text('callsite'), findsOneWidget);

      await tester.tap(find.text('mod'));
      await tester.pumpAndSettle();

      expect(find.text('callsite'), findsNothing);
    });

    testWidgets('initiallyExpanded shows child immediately', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarExpandableRow(
              header: Text('mod'),
              initiallyExpanded: true,
              child: Text('callsite'),
            ),
          ),
        ),
      );

      expect(find.text('callsite'), findsOneWidget);
    });

    testWidgets('chevron rotates 0.25 turns when expanded', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarExpandableRow(
              header: Text('mod'),
              child: Text('callsite'),
            ),
          ),
        ),
      );

      final collapsed = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation),
      );
      expect(collapsed.turns, 0.0);

      await tester.tap(find.text('mod'));
      await tester.pumpAndSettle();

      final expanded = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation),
      );
      expect(expanded.turns, 0.25);
    });

    testWidgets('snaps instantly when animations are disabled', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: RadarExpandableRow(
                header: Text('mod'),
                child: Text('callsite'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('mod'));
      // A single frame is enough: rotation duration is zero under
      // reduced motion, so there's no animation to settle.
      await tester.pump();

      expect(find.text('callsite'), findsOneWidget);
    });

    testWidgets('chevron animation duration is zero under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: RadarExpandableRow(
                header: Text('mod'),
                child: Text('callsite'),
              ),
            ),
          ),
        ),
      );

      final rotation = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation),
      );
      expect(rotation.duration, Duration.zero);
    });

    testWidgets('chevron animation duration is non-zero by default', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarExpandableRow(
              header: Text('mod'),
              child: Text('callsite'),
            ),
          ),
        ),
      );

      final rotation = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation),
      );
      expect(rotation.duration, const Duration(milliseconds: 150));
    });

    testWidgets('exposes button semantics on the header', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarExpandableRow(
              header: Text('mod'),
              child: Text('callsite'),
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(GestureDetector)),
        containsSemantics(isButton: true),
      );

      handle.dispose();
    });
  });
}
