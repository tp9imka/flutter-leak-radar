import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/ui/retaining_path_tile.dart';
import 'package:flutter_leak_radar/src/model/retaining_path.dart';

void main() {
  group('RetainingPathTile', () {
    testWidgets('shows spinner while fetching', (tester) async {
      final completer = Completer<RetainingPathView?>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainingPathTile(
              className: 'HomeBloc',
              onFetch: () => completer.future,
            ),
          ),
        ),
      );

      // Expand the tile.
      await tester.tap(find.byType(ExpansionTile));
      await tester.pump();

      // Spinner should be visible while future is pending.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders path hops after fetch completes', (tester) async {
      final path = RetainingPathView(
        gcRootType: 'IsolateField',
        elements: [
          const RetainingHop(objectType: 'AppState', field: '_blocs'),
          const RetainingHop(objectType: 'HomeBloc'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainingPathTile(
              className: 'HomeBloc',
              onFetch: () async => path,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      expect(find.text('GC root: IsolateField'), findsOneWidget);
      expect(find.textContaining('AppState'), findsOneWidget);
      expect(find.textContaining('_blocs'), findsOneWidget);
    });

    testWidgets('shows unavailable message when fetch returns null',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainingPathTile(
              className: 'HomeBloc',
              onFetch: () async => null,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      expect(find.text('Retaining path unavailable'), findsOneWidget);
    });

    testWidgets('does not fetch again on second expand', (tester) async {
      var fetchCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainingPathTile(
              className: 'HomeBloc',
              onFetch: () async {
                fetchCount++;
                return null;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile)); // collapse
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile)); // re-expand
      await tester.pumpAndSettle();

      expect(fetchCount, 1); // fetched only once
    });
  });
}
