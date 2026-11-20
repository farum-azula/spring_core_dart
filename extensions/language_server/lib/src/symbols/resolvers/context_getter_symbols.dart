import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/index/bean_index.dart';
import 'package:dart_spring_language_server/src/symbols/symbol_resolver.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// `context.basket`: the getter spring_boot_starter_flutter generates for
/// a `@BuildContextAccess` bean goes to the bean.
final class ContextGetterSymbols implements SymbolResolver {
  /// Getters of the beans of [beans].
  const ContextGetterSymbols(this.beans);

  /// The beans of the workspace.
  final BeanIndex beans;

  @override
  Handled<Target>? resolve(DartFile file, AstNode node, int offset) {
    if (node is! SimpleIdentifier || !_isMemberName(node)) {
      return null;
    }
    final found = beans.beansWithContextGetter(node.name);
    return found.isEmpty
        ? null
        : Handled(
            BeanTarget(found, '`context.${node.name}` (@BuildContextAccess)'),
          );
  }

  // `x.name` or `x?.name`: [node] is the member, not the target.
  static bool _isMemberName(SimpleIdentifier node) => switch (node.parent) {
    PrefixedIdentifier(:final identifier) => identical(identifier, node),
    PropertyAccess(:final propertyName) => identical(propertyName, node),
    _ => false,
  };
}
