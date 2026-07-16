import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

// ── Harness ─────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(
  home: Theme(
    data: radarDarkTheme(),
    child: Scaffold(body: SizedBox(width: 1280, height: 800, child: child)),
  ),
);

void _setDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

MemoryController _controller() => MemoryController(
  snapshotSource: FakeSnapshotSource(),
  connection: FakeRadarConnection(),
);

GraphRetainingPath _path({Uri? ownerLib, Uri? leafLib}) => GraphRetainingPath(
  hops: [
    GraphHop(
      className: 'LeakyScreenState',
      field: '_sub',
      libraryUri: ownerLib,
    ),
    GraphHop(className: 'StreamSubscription', libraryUri: leafLib),
  ],
  rootKind: RootKind.stream,
);

GraphLeakCluster _cluster(GraphRetainingPath path, {int? anchorHopIndex}) =>
    GraphLeakCluster(
      className: 'StreamSubscription',
      libraryUri: Uri.parse('dart:async'),
      instanceCount: 1,
      retainedShallowBytes: 100,
      representativePath: path,
      rootKind: RootKind.stream,
      confidence: LeakConfidence.confirmed,
      signature: 'sig',
      anchorHopIndex: anchorHopIndex,
    );

ClassRootProfile _profile(GraphRetainingPath path) => ClassRootProfile(
  className: 'StreamSubscription',
  libraryUri: Uri.parse('dart:async'),
  totalInstances: 1,
  retainedShallowBytes: 100,
  byRoot: const {RootKind.stream: 1},
  representativePath: path,
);

SnapshotBundle _snap({
  required GraphRetainingPath path,
  List<GraphLeakCluster> clusters = const [],
  List<String> appPackages = const [],
}) => SnapshotBundle(
  id: 1,
  capturedAt: DateTime(2026, 1, 1, 12),
  label: 'Snapshot 1',
  histogram: const [],
  analysisResult: GraphAnalysisResult(
    clusters: clusters,
    stats: const GraphAnalysisStats(
      totalObjects: 0,
      reachableObjects: 0,
      leakCandidates: 0,
      clusters: 0,
      suppressedByAppFilter: 0,
      warnings: [],
    ),
    classRootProfiles: [_profile(path)],
    resolvedAppPackages: appPackages,
  ),
);

void main() {
  group('retainingPathText', () {
    test('renders root, hop accessors, library uris, and the yours anchor', () {
      final path = _path(
        ownerLib: Uri.parse('package:my_app/screen.dart'),
        leafLib: Uri.parse('dart:async'),
      );
      final text = retainingPathText(path, anchorHopIndex: 0);

      expect(text, contains('Root: '));
      expect(text, contains('LeakyScreenState._sub'));
      expect(text, contains('StreamSubscription'));
      expect(text, contains('package:my_app/screen.dart'));
      expect(text, contains('dart:async'));
      expect(text, contains('<- yours'));
      // The marker sits on the anchored (0th) hop line, not the leaf.
      final lines = text.split('\n');
      expect(lines[1], contains('<- yours'));
      expect(lines[2], isNot(contains('<- yours')));
    });

    test('omits the yours marker when there is no anchor', () {
      final text = retainingPathText(_path());
      expect(text, isNot(contains('yours')));
    });
  });

  group('OverridableProjectContext', () {
    test('manual override wins and relabels the source to manual', () async {
      const base = _FakeProjectContext(
        packages: {'detected_pkg'},
        label: 'workspace',
      );
      const ctx = OverridableProjectContext(
        base,
        manualPackages: {'my_override'},
      );

      expect(await ctx.projectPackages(), {'my_override'});
      expect(ctx.sourceLabel, 'manual');
    });

    test('defers to the base context when no manual override is set', () async {
      const base = _FakeProjectContext(
        packages: {'detected_pkg'},
        label: 'workspace',
      );
      const ctx = OverridableProjectContext(base);
      expect(await ctx.projectPackages(), {'detected_pkg'});
      expect(ctx.sourceLabel, 'workspace');
    });
  });

  group('RetainingPathTile', () {
    testWidgets('highlights the anchor hop with a yours marker', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final path = _path(
        ownerLib: Uri.parse('package:my_app/screen.dart'),
        leafLib: Uri.parse('dart:async'),
      );
      await tester.pumpWidget(
        _wrap(
          RetainingPathTile(
            path: path,
            anchorHopIndex: 0,
            projectPackages: const {'my_app'},
          ),
        ),
      );

      expect(find.text('yours'), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('copy button places the full textual path on the clipboard', (
      tester,
    ) async {
      _setDesktopSize(tester);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final path = _path(
        ownerLib: Uri.parse('package:my_app/screen.dart'),
        leafLib: Uri.parse('dart:async'),
      );
      await tester.pumpWidget(
        _wrap(RetainingPathTile(path: path, anchorHopIndex: 0)),
      );
      await tester.tap(find.byTooltip('Copy path'));
      await tester.pump();

      expect(copied, isNotNull);
      expect(copied, contains('LeakyScreenState._sub'));
      expect(copied, contains('package:my_app/screen.dart'));
      expect(copied, contains('<- yours'));
    });

    testWidgets('open affordance only appears when onOpenSource is provided', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final path = _path(ownerLib: Uri.parse('package:my_app/screen.dart'));

      await tester.pumpWidget(
        _wrap(RetainingPathTile(path: path, projectPackages: const {'my_app'})),
      );
      expect(find.byIcon(Icons.open_in_new), findsNothing);

      Uri? opened;
      await tester.pumpWidget(
        _wrap(
          RetainingPathTile(
            path: path,
            projectPackages: const {'my_app'},
            onOpenSource: (uri) async {
              opened = uri;
              return true;
            },
          ),
        ),
      );
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);

      await tester.tap(find.byIcon(Icons.open_in_new));
      await tester.pump();
      expect(opened, Uri.parse('package:my_app/screen.dart'));
    });

    testWidgets('toasts when the source cannot be opened', (tester) async {
      _setDesktopSize(tester);
      final path = _path(ownerLib: Uri.parse('package:my_app/screen.dart'));
      await tester.pumpWidget(
        _wrap(
          RetainingPathTile(
            path: path,
            projectPackages: const {'my_app'},
            onOpenSource: (_) async => false,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.open_in_new));
      await tester.pump();
      expect(find.textContaining('Could not open source'), findsOneWidget);
    });
  });

  group('RetainingPathsView anchor wiring', () {
    testWidgets('origin:project filter keeps an sdk-declared, app-anchored '
        'class (carried A8 fix)', (tester) async {
      _setDesktopSize(tester);
      final path = _path(
        ownerLib: Uri.parse('package:my_app/screen.dart'),
        leafLib: Uri.parse('dart:async'),
      );
      final c = _controller()
        ..debugAdd(
          _snap(
            path: path,
            clusters: [_cluster(path, anchorHopIndex: 0)],
            appPackages: const ['my_app'],
          ),
        );
      await tester.pumpWidget(_wrap(RetainingPathsView(controller: c)));
      await tester.pump();

      expect(find.text('StreamSubscription'), findsWidgets);

      // Declared origin is dart:async (sdk); the app anchor makes the
      // EFFECTIVE origin project, so origin:project must retain it.
      final field = find.descendant(
        of: find.byType(RetainingPathsView),
        matching: find.byType(TextField),
      );
      await tester.enterText(field.first, 'origin:project');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('StreamSubscription'), findsWidgets);
    });

    testWidgets('shows the anchored yours marker on the representative path', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final path = _path(
        ownerLib: Uri.parse('package:my_app/screen.dart'),
        leafLib: Uri.parse('dart:async'),
      );
      final c = _controller()
        ..debugAdd(
          _snap(
            path: path,
            clusters: [_cluster(path, anchorHopIndex: 0)],
            appPackages: const ['my_app'],
          ),
        );
      await tester.pumpWidget(_wrap(RetainingPathsView(controller: c)));
      await tester.pump();

      await tester.tap(find.text('StreamSubscription').first);
      await tester.pump();

      expect(find.text('Representative retaining path'), findsOneWidget);
      expect(find.text('yours'), findsOneWidget);
    });

    testWidgets('manual override relabels the project source to manual', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final c = _controller()
        ..debugAdd(_snap(path: _path(), appPackages: const []));
      await tester.pumpWidget(_wrap(RetainingPathsView(controller: c)));
      await tester.pump();

      expect(find.textContaining('project src: none'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('projectPackagesField')),
        'my_app, my_pkg',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.textContaining('project src: manual'), findsOneWidget);
    });
  });
}

/// A [ProjectContext] with fixed packages and label, for override tests.
class _FakeProjectContext implements ProjectContext {
  const _FakeProjectContext({required this.packages, required this.label});

  final Set<String> packages;
  final String label;

  @override
  Future<Set<String>> projectPackages() async => packages;

  @override
  String get sourceLabel => label;

  @override
  bool get canOpenSource => false;

  @override
  Future<bool> openSource(Uri libraryUri) async => false;
}
