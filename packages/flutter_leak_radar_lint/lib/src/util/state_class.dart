// lib/src/util/state_class.dart
import 'package:analyzer/dart/ast/ast.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

const _stateChecker = TypeChecker.fromName('State', packageName: 'flutter');
const _blocBaseChecker = TypeChecker.fromName('BlocBase', packageName: 'bloc');

/// Returns true when [cls] extends Flutter's [State] class.
bool isStateSubclass(ClassDeclaration cls) {
  final element = cls.declaredFragment?.element;
  if (element == null) return false;
  return _stateChecker.isAssignableFrom(element);
}

/// Returns true when [cls] extends `bloc`'s [BlocBase] class.
bool isBlocBaseSubclass(ClassDeclaration cls) {
  final element = cls.declaredFragment?.element;
  if (element == null) return false;
  return _blocBaseChecker.isAssignableFrom(element);
}

/// Returns the name of the teardown lifecycle method for [cls], or `null`
/// when the class is not a recognised stateful base.
///
/// - Flutter [State] subclasses use `dispose`.
/// - `bloc` [BlocBase] subclasses use `close`.
String? teardownMethodName(ClassDeclaration cls) {
  if (isStateSubclass(cls)) return 'dispose';
  if (isBlocBaseSubclass(cls)) return 'close';
  return null;
}
