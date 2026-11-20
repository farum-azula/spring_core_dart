import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_roles.dart';
import 'package:dart_spring_language_server/src/symbols/symbol_resolver.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// A string literal: what its role ([StringRoles]) finds there.
final class StringSymbols implements SymbolResolver {
  /// Strings read by [roles].
  const StringSymbols(this.roles);

  /// The roles a string can have.
  final StringRoles roles;

  @override
  Handled<Target>? resolve(DartFile file, AstNode node, int offset) =>
      node is SimpleStringLiteral
      ? Handled(roles.targetAt(StringContext.of(file, node), offset))
      : null;
}
