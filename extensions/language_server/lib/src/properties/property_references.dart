import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/templates.dart';

/// A place in a Dart file that reads a property: a `${key}` placeholder
/// of an annotation string, the key of `getProperty('key')` or
/// `@ConditionalOnProperty('key')`, or a field a `@ConfigurationProperties`
/// class binds.
final class PropertyReference {
  /// A reference to [key], named by the text from [nameStart] to [nameEnd]
  /// of the file, that ends at [end].
  const PropertyReference(
    this.key,
    this.end, {
    required this.nameStart,
    required this.nameEnd,
    this.fallback,
    this.derived = false,
  });

  /// The key read.
  final String key;

  /// Where the text that names the key starts: the key as written, the
  /// last part of it under a prefix (`cache` of
  /// `@ConditionalOnProperty('cache', prefix: 'shop')`), or the name of
  /// the field the key is [derived] from.
  final int nameStart;

  /// The offset just after the text that names the key.
  final int nameEnd;

  /// Whether the key is derived from a field's name (`maxBasketSize` for
  /// `shop.max-basket-size`) rather than written as text.
  final bool derived;

  /// The offset just after the reference: where its value is shown.
  final int end;

  /// The default of a placeholder (`${port:8080}`), used when no entry
  /// gives the key.
  final String? fallback;
}

/// The placeholders of the template string whose contents start at
/// [contentStart] of a file and read [contents]: the outermost ones only
/// (one in the default of another, `${a:${b}}`, is part of its value).
Iterable<PropertyReference> placeholderReferences(
  String contents,
  int contentStart,
) sync* {
  var outerEnd = -1;
  for (final part in scanTemplate(contents)) {
    if (part.start < outerEnd) {
      continue;
    }
    outerEnd = part.end;
    if (part.kind != TemplatePartKind.placeholder || part.unclosed) {
      continue;
    }
    final key = part.inner(contents);
    if (key.isEmpty) {
      continue;
    }
    final written = contents.substring(part.innerStart, part.keyEnd);
    final nameStart =
        contentStart +
        part.innerStart +
        written.length -
        written.trimLeft().length;
    yield PropertyReference(
      key,
      contentStart + part.end,
      nameStart: nameStart,
      nameEnd: nameStart + key.length,
      fallback: part.fallback(contents),
    );
  }
}

/// The fields the `@ConfigurationProperties` classes of [unit] bind: for
/// `@ConfigurationProperties('shop') class Shop { final int maxBasketSize; }`
/// the key `shop.max-basket-size`, at the end of the field's name, with the
/// field's literal initializer as its default. Static fields and fields of
/// a class type (a nested group) are left out.
Iterable<PropertyReference> configurationPropertiesFields(
  CompilationUnit unit,
) sync* {
  for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
    final prefix = _prefixOf(declaration);
    if (prefix == null) {
      continue;
    }
    for (final member
        in declaration.body.members.whereType<FieldDeclaration>()) {
      if (member.isStatic || !_isScalar(member.fields.type)) {
        continue;
      }
      for (final variable in member.fields.variables) {
        final name = variable.name.lexeme.replaceFirst(RegExp('^_+'), '');
        yield PropertyReference(
          prefix.isEmpty ? kebabCase(name) : '$prefix.${kebabCase(name)}',
          variable.name.end,
          nameStart: variable.name.offset,
          nameEnd: variable.name.end,
          fallback: literalValue(variable.initializer),
          derived: true,
        );
      }
    }
  }
}

/// The value of [expression] when it is a literal (`'http://x/'`, `10`,
/// `true`): a field's initializer or a `defaultValue:`, the default when no
/// config file sets the key.
String? literalValue(Expression? expression) => switch (expression) {
  SimpleStringLiteral(:final value) => value,
  final IntegerLiteral literal => literal.toSource(),
  final DoubleLiteral literal => literal.toSource(),
  final BooleanLiteral literal => literal.toSource(),
  _ => null,
};

/// [name] in kebab case, the canonical form of a property's name:
/// `maxBasketSize` → `max-basket-size`.
String kebabCase(String name) => name
    .replaceAllMapped(
      RegExp('(?<=[a-z0-9])([A-Z])'),
      (match) => '-${match[1]!.toLowerCase()}',
    )
    .toLowerCase();

/// The prefix of `@ConfigurationProperties('shop')` (or `prefix:`, `value:`)
/// on [declaration]; null without the annotation.
String? _prefixOf(ClassDeclaration declaration) {
  for (final annotation in declaration.metadata) {
    if (annotation.name.name.split('.').last != 'ConfigurationProperties') {
      continue;
    }
    for (final argument in [...?annotation.arguments?.arguments]) {
      final name = argument is NamedArgument ? argument.name.lexeme : null;
      final value = argument.argumentExpression;
      if ((name == null || name == 'prefix' || name == 'value') &&
          value is SimpleStringLiteral) {
        return value.value;
      }
    }
    return '';
  }
  return null;
}

/// Whether a field of [type] holds one value (a number, a string, a list
/// of them, ...) rather than a nested group of properties.
bool _isScalar(TypeAnnotation? type) {
  if (type is! NamedType) {
    return type == null;
  }
  return const {
    'String',
    'int',
    'double',
    'num',
    'bool',
    'Duration',
    'Uri',
    'DateTime',
    'List',
    'Set',
    'Object',
    'dynamic',
  }.contains(type.name.lexeme);
}

/// The profiles of the first `@ActiveProfiles(...)` on a class of [unit]
/// (`@ActiveProfiles(['test', 'local'])`, `@ActiveProfiles('test')`); null
/// when no class has one.
List<String>? activeProfilesAnnotation(CompilationUnit unit) {
  for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
    for (final annotation in declaration.metadata) {
      if (annotation.name.name.split('.').last != 'ActiveProfiles') {
        continue;
      }
      return [
        for (final argument in [...?annotation.arguments?.arguments])
          ...switch (argument.argumentExpression) {
            SimpleStringLiteral(:final value) => [value],
            ListLiteral(:final elements) => [
              for (final element in elements)
                if (element is SimpleStringLiteral) element.value,
            ],
            _ => const <String>[],
          },
      ];
    }
  }
  return null;
}
