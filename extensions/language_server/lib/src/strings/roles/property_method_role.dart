import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/properties/property_references.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// Methods whose first argument is a property key.
const _propertyMethods = {
  'getProperty',
  'getRequiredProperty',
  'containsProperty',
  'getPropertyAs',
};

/// A key the environment is asked for: `'shop.name'` in
/// `environment.getProperty('shop.name')` goes to the files that define
/// it, shows its value after the call, and the editor then knows the key
/// as one the code reads. Only the first argument is the key: a
/// `defaultValue: 'x'` is the value used when nothing defines it.
final class PropertyMethodRole extends StringRole {
  /// The role, over [model].
  const PropertyMethodRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<Target>? target(StringContext string, int offset) {
    final key = _keyOf(string);
    if (key == null) {
      return null;
    }
    return Handled(
      PropertyTarget(
        key,
        model.properties.property(key, from: string.path),
        fallback: _defaultOf(string.invocation!),
      ),
    );
  }

  @override
  Iterable<String>? keysRead(StringContext string) => switch (_keyOf(string)) {
    final key? => [key],
    null => null,
  };

  @override
  Iterable<PropertyReference> references(StringContext string) =>
      switch (_keyOf(string)) {
        final key? => [
          PropertyReference(
            key,
            string.literal.end,
            nameStart: string.contentStart,
            nameEnd: string.contentEnd,
            fallback: _defaultOf(string.invocation!),
          ),
        ],
        null => const [],
      };

  static String? _keyOf(StringContext string) =>
      _propertyMethods.contains(string.method) && string.isFirstArgument
      ? string.value
      : null;

  /// The literal `defaultValue:` of [call]: what it returns when nothing
  /// defines the key.
  static String? _defaultOf(MethodInvocation call) {
    for (final argument in call.argumentList.arguments) {
      if (argument is NamedArgument && argument.name.lexeme == 'defaultValue') {
        return literalValue(argument.argumentExpression);
      }
    }
    return null;
  }
}
