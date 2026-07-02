import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  test(
    'fromBytes on garbage completes without throwing and yields empty analysis',
    () async {
      const analyzer = SnapshotAnalyzer();
      final bundle = await analyzer.fromBytes(
        Uint8List.fromList([0, 1, 2, 3, 4]),
        label: 'garbage',
      );
      expect(bundle.label, 'garbage');
      expect(bundle.analysisResult.clusters, isEmpty);
      expect(bundle.histogram, isEmpty);
    },
  );
}
