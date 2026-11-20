import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/properties/property_references.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// Annotations whose first argument names a property.
const _annotations = {'ConditionalOnProperty', 'ConditionalOnBooleanProperty'};

/// The key of `@ConditionalOnProperty('shop.cache')` (or
/// `@ConditionalOnBooleanProperty`, or one of the list of
/// `@ConditionalOnProperty.names([...])`), under its `prefix:` when it has
/// one: it goes to the property's definitions, shows its value after the
/// string, completes with the known keys, and the editor then knows the
/// key as one the code reads. `havingValue: 'redis'` and the prefix itself
/// are no keys.
final class ConditionalPropertyRole extends StringRole {
  /// The role, over [model].
  const ConditionalPropertyRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<Target>? target(StringContext string, int offset) {
    final key = _keyOf(string);
    if (key == null) {
      return null;
    }
    return Handled(
      PropertyTarget(key, model.properties.property(key, from: string.path)),
    );
  }

  @override
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) {
    if (_keyOf(string) == null || request.inTemplate) {
      return null;
    }
    return Handled(
      CompletionResult(request.wordRange, [
        for (final key in model.schemas.knownKeys(string.path))
          Completion(key, detail: 'property'),
      ]),
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
          ),
        ],
        null => const [],
      };

  /// The key [string] names: the annotation's first argument, or an
  /// element of the list that is; with the annotation's `prefix:` before
  /// it.
  static String? _keyOf(StringContext string) {
    final annotation = string.annotation;
    if (annotation == null || !_annotations.contains(string.annotationType)) {
      return null;
    }
    final arguments = annotation.arguments?.arguments;
    final first = arguments == null || arguments.isEmpty
        ? null
        : arguments.first;
    final literal = string.literal;
    final named =
        first == literal ||
        (first is ListLiteral && first.elements.contains(literal));
    if (!named) {
      return null;
    }
    final prefix = [
      for (final argument in arguments!)
        if (argument is NamedArgument && argument.name.lexeme == 'prefix')
          if (argument.argumentExpression case SimpleStringLiteral(
            :final value,
          ))
            value,
    ].firstOrNull;
    return prefix == null || prefix.isEmpty
        ? string.value
        : '$prefix.${string.value}';
  }
}
