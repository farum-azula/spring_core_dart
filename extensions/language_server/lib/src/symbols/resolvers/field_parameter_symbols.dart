import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/symbols/injection_points.dart';
import 'package:dart_spring_language_server/src/symbols/resolvers/injected_type_symbols.dart';
import 'package:dart_spring_language_server/src/symbols/symbol_resolver.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// `this.repository` in a constructor: the beans of the field's type
/// (unless the parameter takes a `@Value`).
final class FieldParameterSymbols implements SymbolResolver {
  /// Field parameters whose beans [types] lists.
  const FieldParameterSymbols(this.types);

  /// Lists the beans of a type.
  final InjectedTypeSymbols types;

  @override
  Handled<Target>? resolve(DartFile file, AstNode node, int offset) {
    if (node is! FieldFormalParameter ||
        offset < node.name.offset ||
        offset > node.name.end) {
      return null;
    }
    final field = InjectionPoints.fieldType(node);
    final type = field == null ? null : InjectionPoints.beanType(field);
    if (type == null || InjectionPoints.hasAnnotation(node.metadata, 'Value')) {
      return const Handled(null);
    }
    return Handled(
      types.beansOf(
        type,
        InjectionPoints.qualifierOf(node.metadata),
        file.path,
      ),
    );
  }
}
