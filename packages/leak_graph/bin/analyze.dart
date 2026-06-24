import 'dart:io';

import 'package:leak_graph/leak_graph.dart';
import 'package:leak_graph/src/cli/cli_args.dart';

Future<void> main(List<String> argv) async {
  CliConfig config;
  try {
    config = parseCliArgs(argv);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(2);
  }

  HeapGraphView graph;
  try {
    graph = await loadHeapGraph(File(config.dumpPath));
  } on FileSystemException catch (e) {
    stderr.writeln('Error reading heap snapshot: ${e.message} — ${e.path}');
    exit(2);
  }

  final result = GraphLeakAnalyzer().analyze(
    graph,
    GraphAnalysisOptions(
      appPackages: config.appPackages,
      disableAppFilter: config.all,
      minClusterSize: config.minCluster,
      confirmWithReachability: config.confirm,
    ),
  );

  print(renderReport(result, top: config.top));

  final jsonOut = config.jsonOut;
  if (jsonOut != null) {
    await File(jsonOut).writeAsString(renderJson(result));
  }
}
