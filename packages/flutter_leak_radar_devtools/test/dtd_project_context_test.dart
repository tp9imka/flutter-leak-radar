@TestOn('browser')
library;

import 'package:flutter_leak_radar_devtools/src/session/dtd_project_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  group('DtdProjectContext', () {
    test('is a copy-only ProjectContext (no editor launch on web)', () async {
      final ctx = DtdProjectContext();
      expect(ctx, isA<ProjectContext>());
      expect(ctx.canOpenSource, isFalse);
      expect(await ctx.openSource(Uri.parse('package:my_app/x.dart')), isFalse);
    });

    test(
      'degrades to empty/none when no tooling daemon is connected',
      () async {
        final ctx = DtdProjectContext();
        // Without a DTD connection, detection must degrade honestly rather than
        // throw — an empty project set labelled "none".
        expect(await ctx.projectPackages(), isEmpty);
        expect(ctx.sourceLabel, 'none');
      },
    );

    test(
      'does not cache an empty result — retries until packages resolve',
      () async {
        var calls = 0;
        // DTD is not ready on the first call (empty), then connects.
        final ctx = DtdProjectContext(
          detect: () async {
            calls++;
            return calls == 1 ? const <String>{} : {'my_app'};
          },
        );

        expect(await ctx.projectPackages(), isEmpty);
        expect(ctx.sourceLabel, 'none');

        // Second call re-detects (empty was not cached) and now resolves.
        expect(await ctx.projectPackages(), {'my_app'});
        expect(ctx.sourceLabel, 'workspace');

        // Third call is served from the cache — detection is not re-run.
        expect(await ctx.projectPackages(), {'my_app'});
        expect(calls, 2);
      },
    );
  });
}
