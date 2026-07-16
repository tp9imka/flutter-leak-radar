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
  });
}
