import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/app/error_toast.dart';

void main() {
  group('errorClipboardPayload', () {
    test('prefixes a Radar Desktop header and includes the message', () {
      final payload = errorClipboardPayload('Import failed: boom');
      expect(payload, 'Radar Desktop\nImport failed: boom');
    });

    test('includes the source when provided', () {
      final payload = errorClipboardPayload(
        'Capture failed: nope',
        source: 'Capture / import',
      );
      expect(payload, 'Radar Desktop · Capture / import\nCapture failed: nope');
    });

    test('omits an empty source', () {
      expect(errorClipboardPayload('x', source: ''), 'Radar Desktop\nx');
    });
  });

  group('showRadarError', () {
    testWidgets('shows a SnackBar with a Copy action', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      showRadarError(ctx, 'Import failed: boom', source: 'Dumps');
      await tester.pump();

      expect(find.text('Import failed: boom'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Copy'), findsOneWidget);
    });

    testWidgets('no-ops without a ScaffoldMessenger', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Must not throw when there is no messenger in the tree.
      showRadarError(ctx, 'anything');
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
