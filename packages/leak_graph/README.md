# leak_graph

A pure-Dart library that connects to a running Dart VM via `vm_service`,
loads a heap snapshot, and builds an in-memory object graph so that
retaining paths to suspected leaked objects can be computed efficiently.
It has no Flutter dependency and can be embedded in CLI tools or integrated
with the `flutter_leak_radar` runtime package to produce human-readable
leak reports.
