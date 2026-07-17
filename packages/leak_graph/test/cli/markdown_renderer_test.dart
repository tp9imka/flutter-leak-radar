import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

/// Builds a cluster whose representative path is
/// `_Timer -> [anchorClassName] -> [leafClassName]`, with the anchor hop at
/// index 1 (the standard "SDK leaf retained by an app owner" shape used by
/// the analyzer). [anchorLibrary] is stamped on both [GraphLeakCluster
/// .libraryUri] and the anchor hop, matching how the real analyzer derives
/// `cluster.libraryUri` from the attribution anchor.
GraphLeakCluster _anchoredCluster({
  required String className,
  required String signature,
  required String anchorLibrary,
  String holdingField = '_sub',
  String leafClassName = '_ControllerSubscription',
  int instanceCount = 2,
  int retainedShallowBytes = 100,
  int? anchorHopIndex = 1,
}) => GraphLeakCluster(
  className: className,
  libraryUri: anchorHopIndex == null ? null : Uri.parse(anchorLibrary),
  instanceCount: instanceCount,
  retainedShallowBytes: retainedShallowBytes,
  representativePath: GraphRetainingPath(
    hops: [
      const GraphHop(className: '_Timer', field: null),
      GraphHop(
        className: className,
        field: '_callback',
        libraryUri: anchorHopIndex == null ? null : Uri.parse(anchorLibrary),
      ),
      GraphHop(className: leafClassName, field: holdingField),
    ],
    rootKind: RootKind.timer,
  ),
  rootKind: RootKind.timer,
  confidence: LeakConfidence.heuristic,
  signature: signature,
  leafClassName: leafClassName,
  anchorHopIndex: anchorHopIndex,
);

/// A cluster with no attribution anchor: the leaked object itself is the
/// (headlined) app class, directly retained by its root.
GraphLeakCluster _unanchoredCluster({
  required String className,
  required String signature,
  required String library,
  int instanceCount = 2,
  int retainedShallowBytes = 100,
}) => GraphLeakCluster(
  className: className,
  libraryUri: Uri.parse(library),
  instanceCount: instanceCount,
  retainedShallowBytes: retainedShallowBytes,
  representativePath: GraphRetainingPath(
    hops: [
      const GraphHop(className: '_Timer'),
      GraphHop(
        className: className,
        field: '_callback',
        libraryUri: Uri.parse(library),
      ),
    ],
    rootKind: RootKind.timer,
  ),
  rootKind: RootKind.timer,
  confidence: LeakConfidence.heuristic,
  signature: signature,
);

PackageRollup _rollup(
  String package,
  ClassOrigin origin, {
  int classCount = 1,
  int instanceCount = 2,
  int shallowBytes = 100,
  int clusterCount = 1,
}) => PackageRollup(
  package: package,
  origin: origin,
  classCount: classCount,
  instanceCount: instanceCount,
  shallowBytes: shallowBytes,
  clusterCount: clusterCount,
);

GraphAnalysisResult _result(
  List<GraphLeakCluster> clusters, {
  List<PackageRollup> anchorRollups = const [],
  List<PackageRollup> declaredRollups = const [],
  List<String> warnings = const [],
  AppPackageSource? appPackageSource,
}) => GraphAnalysisResult(
  clusters: clusters,
  stats: GraphAnalysisStats(
    totalObjects: 100,
    reachableObjects: 50,
    leakCandidates: clusters.length,
    clusters: clusters.length,
    suppressedByAppFilter: 0,
    warnings: warnings,
  ),
  anchorRollups: anchorRollups,
  declaredRollups: declaredRollups,
  appPackageSource: appPackageSource,
);

void main() {
  group('renderMarkdownReport — verdict line', () {
    test('no clusters → success verdict, no gate needed', () {
      final report = renderMarkdownReport(_result(const []), github: false);
      expect(report.split('\n').first, '✅ no leak clusters');
    });

    test('gate failed → failure verdict names the first violation', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      const gate = GateResult(
        passed: false,
        violations: ['new clusters 1 exceeds limit 0', 'other violation'],
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        gate: gate,
        github: false,
      );
      expect(
        report.split('\n').first,
        '❌ gate failed: new clusters 1 exceeds limit 0',
      );
    });

    test('gate passed with clusters present', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      const gate = GateResult(passed: true, violations: []);
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        gate: gate,
        github: false,
      );
      expect(report.split('\n').first, '✅ 1 clusters (gate passed)');
    });

    test('no gate with clusters present', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        github: false,
      );
      expect(report.split('\n').first, '⚠ 1 clusters (no gate)');
    });
  });

  group('renderMarkdownReport — top-3 highlight rule', () {
    test(
      'shows at most 3 project-anchor clusters even with more available',
      () {
        final clusters = List.generate(
          5,
          (i) => _anchoredCluster(
            className: 'Owner$i',
            signature: 'r>Owner$i',
            anchorLibrary: 'package:my_app/o$i.dart',
            retainedShallowBytes: (5 - i) * 100,
          ),
        );
        final report = renderMarkdownReport(
          _result(
            clusters,
            anchorRollups: [_rollup('my_app', ClassOrigin.project)],
          ),
          github: false,
        );

        expect(report, contains('**1.'));
        expect(report, contains('**2.'));
        expect(report, contains('**3.'));
        expect(report, isNot(contains('**4.')));
      },
    );

    test('shows fewer than 3 lines when fewer clusters qualify', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        github: false,
      );

      expect(report, contains('**1.'));
      expect(report, isNot(contains('**2.')));
    });

    test('excludes non-project-anchor clusters from the top section', () {
      final projectCluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      final depCluster = _anchoredCluster(
        className: 'SomeVendorThing',
        signature: 'r>SomeVendorThing',
        anchorLibrary: 'package:some_vendor_pkg/x.dart',
      );
      final report = renderMarkdownReport(
        _result(
          [projectCluster, depCluster],
          anchorRollups: [
            _rollup('my_app', ClassOrigin.project),
            _rollup('some_vendor_pkg', ClassOrigin.dependency),
          ],
        ),
        github: false,
      );

      // Only one project-anchor cluster qualifies for the top section.
      expect(report, contains('**1.'));
      expect(report, isNot(contains('**2.')));
      // The dependency cluster must still appear somewhere (full table).
      expect(report, contains('SomeVendorThing'));
    });
  });

  group('renderMarkdownReport — anchor-hop line', () {
    test('names the anchor class and the field holding the leak onward', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
        holdingField: '_subs',
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        github: false,
      );

      expect(report, contains('your code holds it at `GroupCallBloc._subs`'));
    });

    test('falls back to a root-kind line when there is no anchor hop', () {
      final cluster = _unanchoredCluster(
        className: 'LeakyBloc',
        signature: 'r>LeakyBloc',
        library: 'package:my_app/leaky.dart',
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        github: false,
      );

      expect(report, contains('LeakyBloc'));
      expect(report, contains('Timer root'));
    });
  });

  group('renderMarkdownReport — nearest-known line', () {
    test('renders for a new cluster when a nearest signature was found', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      final delta = ClusterDelta(
        cluster: cluster,
        novelty: ClusterNovelty.newCluster,
        instanceDelta: 2,
        bytesDelta: 100,
        nearestKnownSignature: 'r>OldOwner',
      );
      final comparison = BaselineComparison(
        baselineComparable: true,
        deltas: [delta],
        gone: const [],
        currentTotalShallowBytes: 100,
        baselineTotalShallowBytes: 0,
        currentClusters: [cluster],
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        comparison: comparison,
        github: false,
      );

      expect(report, contains('nearest known: `r>OldOwner`'));
    });

    test('omits the nearest-known line when none was found', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      final delta = ClusterDelta(
        cluster: cluster,
        novelty: ClusterNovelty.newCluster,
        instanceDelta: 2,
        bytesDelta: 100,
        nearestKnownSignature: null,
      );
      final comparison = BaselineComparison(
        baselineComparable: true,
        deltas: [delta],
        gone: const [],
        currentTotalShallowBytes: 100,
        baselineTotalShallowBytes: 0,
        currentClusters: [cluster],
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        comparison: comparison,
        github: false,
      );

      expect(report, isNot(contains('nearest known')));
      expect(report, contains('new cluster'));
    });

    test('omits new/nearest badges for a known (unchanged) cluster', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      final delta = ClusterDelta(
        cluster: cluster,
        novelty: ClusterNovelty.known,
        instanceDelta: 0,
        bytesDelta: 0,
        nearestKnownSignature: null,
      );
      final comparison = BaselineComparison(
        baselineComparable: true,
        deltas: [delta],
        gone: const [],
        currentTotalShallowBytes: 100,
        baselineTotalShallowBytes: 100,
        currentClusters: [cluster],
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        comparison: comparison,
        github: false,
      );

      expect(report, isNot(contains('new cluster')));
      expect(report, isNot(contains('nearest known')));
    });
  });

  group('renderMarkdownReport — origin labels', () {
    test('labels yours/dependency/framework/sdk/unknown correctly', () {
      final report = renderMarkdownReport(
        _result(
          const [],
          anchorRollups: [
            _rollup('my_app', ClassOrigin.project),
            _rollup('some_pkg', ClassOrigin.dependency),
            _rollup('flutter', ClassOrigin.flutterFramework),
            _rollup('dart:async', ClassOrigin.dartSdk),
            _rollup('(unknown)', ClassOrigin.unknown),
          ],
        ),
        github: false,
      );

      expect(report, contains('[yours]'));
      expect(report, contains('[dependency]'));
      expect(report, contains('[framework]'));
      expect(report, contains('[sdk]'));
      expect(report, contains('[?]'));
    });

    test('under --all (disabled) ownership is not classified — the '
        "caller's own class reads [?], never a false [dependency]", () {
      // With app filtering disabled, empty project packages classify the
      // user's own package as `dependency`; the report must not present that
      // as fact. It reads [?] and names the detection source.
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.dependency)],
          appPackageSource: AppPackageSource.disabled,
        ),
        github: false,
      );

      expect(report, contains('App packages: disabled'));
      expect(report, contains('[?]'));
      expect(report, isNot(contains('[dependency]')));
    });

    test('names the detection source for an explicit-config run', () {
      final report = renderMarkdownReport(
        _result(const [], appPackageSource: AppPackageSource.explicitConfig),
        github: false,
      );
      expect(report, contains('App packages: explicit config'));
    });
  });

  group('renderMarkdownReport — details sections', () {
    test('wraps everything else in <details> blocks', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
          declaredRollups: [_rollup('my_app', ClassOrigin.project)],
          warnings: ['a warning'],
        ),
        github: false,
      );

      expect(report, contains('<details>'));
      expect(report, contains('</details>'));
      expect(report, contains('a warning'));
    });

    test('full cluster table lists every cluster, including non-highlighted '
        'ones', () {
      final clusters = List.generate(
        5,
        (i) => _anchoredCluster(
          className: 'Owner$i',
          signature: 'r>Owner$i',
          anchorLibrary: 'package:my_app/o$i.dart',
          retainedShallowBytes: (5 - i) * 100,
        ),
      );
      final report = renderMarkdownReport(
        _result(
          clusters,
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        github: false,
      );

      // Owner4 is never in the top-3 (smallest byte figure) but must still
      // show up in the full details table.
      expect(report, contains('Owner4'));
    });

    test('anchor rollup table precedes the declared rollup table', () {
      final report = renderMarkdownReport(
        _result(
          const [],
          anchorRollups: [_rollup('anchor_pkg', ClassOrigin.project)],
          declaredRollups: [_rollup('declared_pkg', ClassOrigin.dependency)],
        ),
        github: false,
      );

      expect(
        report.indexOf('anchor_pkg') < report.indexOf('declared_pkg'),
        isTrue,
      );
      expect(
        report.indexOf('retained via') < report.indexOf('declared by'),
        isTrue,
      );
    });

    test(
      'lists gone clusters when the baseline had ones no longer present',
      () {
        final report = renderMarkdownReport(
          _result(const []),
          comparison: const BaselineComparison(
            baselineComparable: true,
            deltas: [],
            gone: [
              BaselineCluster(
                signature: 'r>GoneOwner',
                className: 'GoneOwner',
                instanceCount: 4,
                retainedShallowBytes: 400,
              ),
            ],
            currentTotalShallowBytes: 0,
            baselineTotalShallowBytes: 400,
            currentClusters: [],
          ),
          github: false,
        );

        expect(report, contains('GoneOwner'));
      },
    );
  });

  group('renderMarkdownReport — byte figures always carry "shallow"', () {
    test('every rendered byte figure includes the shallow qualifier', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
        retainedShallowBytes: 384,
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [
            _rollup('my_app', ClassOrigin.project, shallowBytes: 384),
          ],
          declaredRollups: [
            _rollup('my_app', ClassOrigin.project, shallowBytes: 384),
          ],
        ),
        github: false,
      );

      final byteFigure = RegExp(r'\d+ B\b');
      for (final line in report.split('\n')) {
        if (byteFigure.hasMatch(line)) {
          expect(
            line.toLowerCase(),
            contains('shallow'),
            reason: 'line "$line" has an unlabeled byte figure',
          );
        }
      }
    });
  });

  group('renderMarkdownReport — github vs plain md', () {
    test('github uses a GitHub-flavored admonition for a failed gate', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      const gate = GateResult(
        passed: false,
        violations: ['new clusters 1 exceeds limit 0'],
      );
      final result = _result(
        [cluster],
        anchorRollups: [_rollup('my_app', ClassOrigin.project)],
      );

      final githubReport = renderMarkdownReport(
        result,
        gate: gate,
        github: true,
      );
      final mdReport = renderMarkdownReport(result, gate: gate, github: false);

      expect(githubReport, contains('[!CAUTION]'));
      expect(mdReport, isNot(contains('[!CAUTION]')));
      // Line 1 (the 30-second verdict) is identical either way.
      expect(githubReport.split('\n').first, mdReport.split('\n').first);
    });
  });

  group('renderMarkdownReport — largest-overall visibility', () {
    test('appends a largest-overall line when a dependency cluster out-bytes '
        'every featured project-anchor cluster', () {
      final small1 = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
        retainedShallowBytes: 300,
        instanceCount: 3,
      );
      final small2 = _anchoredCluster(
        className: 'ChatScreenState',
        signature: 'r>ChatScreenState',
        anchorLibrary: 'package:my_app/chat.dart',
        retainedShallowBytes: 200,
        instanceCount: 2,
      );
      final hugeDependency = _anchoredCluster(
        className: 'PeerConnectionObserver',
        signature: 'r>PeerConnectionObserver',
        anchorLibrary: 'package:flutter_webrtc/rtc.dart',
        retainedShallowBytes: 1024 * 500,
        instanceCount: 40,
      );
      final report = renderMarkdownReport(
        _result(
          [small1, small2, hugeDependency],
          anchorRollups: [
            _rollup('my_app', ClassOrigin.project),
            _rollup('flutter_webrtc', ClassOrigin.dependency),
          ],
        ),
        github: false,
      );

      // The huge dependency cluster is not one of the (project-anchored)
      // featured clusters ...
      expect(report, isNot(contains('**3.')));
      // ... but must still surface above the fold as the overall worst.
      expect(
        report,
        contains(
          'largest overall: `PeerConnectionObserver` [dependency] — '
          '40 instances, 500 KB shallow (see details)',
        ),
      );
      // The line must appear before the fold-line (details) content.
      expect(
        report.indexOf('largest overall') < report.indexOf('<details>'),
        isTrue,
      );
    });

    test('omits the largest-overall line when the overall-worst cluster is '
        'already featured', () {
      final smaller = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
        retainedShallowBytes: 1000,
      );
      final biggestProject = _anchoredCluster(
        className: 'ChatScreenState',
        signature: 'r>ChatScreenState',
        anchorLibrary: 'package:my_app/chat.dart',
        retainedShallowBytes: 2000,
      );
      final smallerDependency = _anchoredCluster(
        className: 'SomeVendorThing',
        signature: 'r>SomeVendorThing',
        anchorLibrary: 'package:some_vendor_pkg/x.dart',
        retainedShallowBytes: 500,
      );
      final report = renderMarkdownReport(
        _result(
          [smaller, biggestProject, smallerDependency],
          anchorRollups: [
            _rollup('my_app', ClassOrigin.project),
            _rollup('some_vendor_pkg', ClassOrigin.dependency),
          ],
        ),
        github: false,
      );

      // Both project clusters fit within the top-3 cap, including the
      // overall-worst one (ChatScreenState, 2000 bytes) — so no extra
      // line is needed even though a smaller dependency cluster exists
      // and is NOT featured.
      expect(report, contains('ChatScreenState'));
      expect(report, isNot(contains('largest overall')));
    });

    test(
      'falls back to the worst clusters overall when none are '
      'project-anchored, so the view is never empty while clusters exist',
      () {
        final biggest = _anchoredCluster(
          className: 'PeerConnectionObserver',
          signature: 'r>PeerConnectionObserver',
          anchorLibrary: 'package:flutter_webrtc/rtc.dart',
          retainedShallowBytes: 4000,
        );
        final second = _anchoredCluster(
          className: 'RoomEngine',
          signature: 'r>RoomEngine',
          anchorLibrary: 'package:livekit_client/room.dart',
          retainedShallowBytes: 3000,
        );
        final third = _anchoredCluster(
          className: 'TrackPublication',
          signature: 'r>TrackPublication',
          anchorLibrary: 'package:livekit_client/track.dart',
          retainedShallowBytes: 2000,
        );
        final smallest = _anchoredCluster(
          className: 'AudioLevelObserver',
          signature: 'r>AudioLevelObserver',
          anchorLibrary: 'package:flutter_webrtc/audio.dart',
          retainedShallowBytes: 1000,
        );
        final report = renderMarkdownReport(
          _result(
            [biggest, second, third, smallest],
            anchorRollups: [
              _rollup('flutter_webrtc', ClassOrigin.dependency),
              _rollup('livekit_client', ClassOrigin.dependency),
            ],
          ),
          github: false,
        );

        // The featured section is never empty while clusters exist, even
        // with zero project-anchored clusters.
        expect(report, contains('**1.'));
        expect(report, contains('**2.'));
        expect(report, contains('**3.'));
        expect(report, isNot(contains('**4.')));
        expect(report, contains('PeerConnectionObserver'));
        expect(report, contains('RoomEngine'));
        expect(report, contains('TrackPublication'));
        // The smallest cluster didn't make the cut, but the worst overall
        // (PeerConnectionObserver) did, so no duplicate summary line.
        expect(report, isNot(contains('largest overall')));
        // Full table still lists everything, including the excluded one.
        expect(report, contains('AudioLevelObserver'));
      },
    );
  });

  group('renderMarkdownReport — negative anchorHopIndex guard', () {
    test('never crashes on a malformed negative anchorHopIndex from JSON; '
        'degrades to omitting the anchor-hop line', () {
      final json = {
        'className': 'GroupCallBloc',
        'libraryUri': 'package:my_app/call.dart',
        'instanceCount': 2,
        'retainedShallowBytes': 100,
        'representativePath': {
          'rootKind': 'timer',
          'hops': [
            {'className': '_Timer'},
            {'className': 'GroupCallBloc', 'field': '_callback'},
          ],
        },
        'rootKind': 'timer',
        'confidence': 'heuristic',
        'signature': 'r>GroupCallBloc',
        'anchorHopIndex': -1,
      };
      final cluster = GraphLeakCluster.fromJson(json);
      expect(cluster.anchorHopIndex, -1);

      final result = _result(
        [cluster],
        anchorRollups: [_rollup('my_app', ClassOrigin.project)],
      );

      expect(
        () => renderMarkdownReport(result, github: false),
        returnsNormally,
      );

      final report = renderMarkdownReport(result, github: false);
      // The cluster itself still renders — only the anchor-hop line (which
      // has no honest meaning for a negative index) is omitted.
      expect(report, contains('GroupCallBloc'));
      expect(report, isNot(contains('your code holds')));
      expect(report, isNot(contains('your code retains')));
    });
  });

  group('renderMarkdownReport — markdown escaping', () {
    test("escapes '<'/'>' in a plain-text class name so GitHub's HTML "
        'sanitizer cannot swallow it (e.g. an unresolved VM class name)', () {
      final cluster = _anchoredCluster(
        className: '<unknown>',
        signature: 'r>unknown',
        anchorLibrary: 'package:my_app/x.dart',
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        github: false,
      );

      // The raw, unescaped form must never appear in a plain-text
      // (non-code-span) position — that's exactly what a sanitizer strips.
      expect(report, isNot(contains('**1. <unknown>**')));
      expect(report, contains('&lt;unknown&gt;'));
    });

    test('escapes a pipe in a class name so it cannot break a markdown table '
        'row', () {
      final cluster = _anchoredCluster(
        className: 'Weird|Class',
        signature: 'r>weird',
        anchorLibrary: 'package:my_app/x.dart',
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        github: false,
      );

      // The full cluster table renders this class name as a plain table
      // cell; an unescaped pipe would add a spurious cell boundary.
      expect(report, contains(r'Weird\|Class'));
    });

    test('escapes a stray backtick in a nearest-known signature so it cannot '
        'terminate the surrounding code span early', () {
      final cluster = _anchoredCluster(
        className: 'GroupCallBloc',
        signature: 'r>GroupCallBloc',
        anchorLibrary: 'package:my_app/call.dart',
      );
      final delta = ClusterDelta(
        cluster: cluster,
        novelty: ClusterNovelty.newCluster,
        instanceDelta: 2,
        bytesDelta: 100,
        nearestKnownSignature: 'sig`with`backtick',
      );
      final comparison = BaselineComparison(
        baselineComparable: true,
        deltas: [delta],
        gone: const [],
        currentTotalShallowBytes: 100,
        baselineTotalShallowBytes: 0,
        currentClusters: [cluster],
      );
      final report = renderMarkdownReport(
        _result(
          [cluster],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        comparison: comparison,
        github: false,
      );

      expect(report, isNot(contains('`sig`with`backtick`')));
      expect(report, contains("sig'with'backtick"));
    });
  });

  group('renderMarkdownReport — deterministic tie-break', () {
    test('orders identically-sized clusters by signature for reproducible '
        'output', () {
      final clusterB = _anchoredCluster(
        className: 'BOwner',
        signature: 'r>BOwner',
        anchorLibrary: 'package:my_app/b.dart',
        retainedShallowBytes: 500,
        instanceCount: 5,
      );
      final clusterA = _anchoredCluster(
        className: 'AOwner',
        signature: 'r>AOwner',
        anchorLibrary: 'package:my_app/a.dart',
        retainedShallowBytes: 500,
        instanceCount: 5,
      );
      // Deliberately inserted B-before-A so a passing test proves the sort
      // is keying on signature, not incidentally on list order.
      final report = renderMarkdownReport(
        _result(
          [clusterB, clusterA],
          anchorRollups: [_rollup('my_app', ClassOrigin.project)],
        ),
        github: false,
      );

      expect(report.indexOf('AOwner') < report.indexOf('BOwner'), isTrue);
      expect(report, contains('**1. AOwner**'));
      expect(report, contains('**2. BOwner**'));
    });
  });

  group('renderMarkdownReport — empty gate violations guard', () {
    test('never throws when a failed gate carries no violation strings', () {
      const gate = GateResult(passed: false, violations: []);

      expect(
        () =>
            renderMarkdownReport(_result(const []), gate: gate, github: false),
        returnsNormally,
      );

      final report = renderMarkdownReport(
        _result(const []),
        gate: gate,
        github: false,
      );
      expect(report.split('\n').first, contains('❌ gate failed'));
    });
  });

  group('renderMarkdownReport — gate requested but unavailable', () {
    final cluster = _anchoredCluster(
      className: 'GroupCallBloc',
      signature: 'r>GroupCallBloc',
      anchorLibrary: 'package:my_app/call.dart',
    );
    GraphAnalysisResult resultWithCluster() => _result(
      [cluster],
      anchorRollups: [_rollup('my_app', ClassOrigin.project)],
    );

    for (final github in [false, true]) {
      test('verdict line is a distinct honest variant naming the reason '
          '(github: $github), never the misleading "(no gate)" line', () {
        final report = renderMarkdownReport(
          resultWithCluster(),
          gateUnavailableReason: 'could not read baseline "missing.json"',
          github: github,
        );

        expect(
          report.split('\n').first,
          '❌ gate requested but could not be evaluated: '
          'could not read baseline "missing.json"',
        );
        // Must never look like "no gate was ever requested".
        expect(report, isNot(contains('(no gate)')));
      });
    }

    test('takes priority over "no leak clusters" — a real evaluation failure '
        'must never look like a clean success', () {
      final report = renderMarkdownReport(
        _result(const []),
        gateUnavailableReason: 'no --baseline was provided',
        github: false,
      );

      expect(
        report.split('\n').first,
        '❌ gate requested but could not be evaluated: '
        'no --baseline was provided',
      );
      expect(report, isNot(contains('no leak clusters')));
    });

    test(
      'an actually-evaluated failed gate still wins over a stray '
      'gateUnavailableReason (defensive ordering, not reachable via the CLI)',
      () {
        const gate = GateResult(
          passed: false,
          violations: ['new clusters 1 exceeds limit 0'],
        );
        final report = renderMarkdownReport(
          resultWithCluster(),
          gate: gate,
          gateUnavailableReason: 'should not surface',
          github: false,
        );

        expect(
          report.split('\n').first,
          '❌ gate failed: new clusters 1 exceeds limit 0',
        );
        expect(report, isNot(contains('should not surface')));
      },
    );
  });
}
