import '../filter/filter_expression.dart';

/// Adapts a class-like row (histogram entry, diff entry, root profile) to the
/// [FilterTarget] interface the composable filter evaluates against.
class ClassRow implements FilterTarget {
  const ClassRow({required this.className, required this.libraryUri});

  @override
  final String className;

  @override
  final Uri? libraryUri;
}
