import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// Finds what is at a syntax node of a Dart file, for go to definition and
/// hovers: the strings (through their roles), the injection points, the
/// getters generated for beans.
///
/// The resolvers are asked in order (`symbolResolvers`); the first that
/// handles the node answers.
abstract interface class SymbolResolver {
  /// The target at [offset] of [file], where [node] is the innermost node;
  /// `null` when [node] is not this resolver's.
  Handled<Target>? resolve(DartFile file, AstNode node, int offset);
}
