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
    this.nested = false,
    this.subtree = false,
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

  /// Whether the reference is a placeholder in the default of another
  /// (`b` of `${a:${b}}`): a key the code reads, whose value is part of the
  /// outer placeholder's rather than shown on its own.
  final bool nested;

  /// Whether the reference binds the keys below [key] too (a `Map` or a
  /// `List` field of a `@ConfigurationProperties` class: `shop.tags.x`,
  /// `shop.tags[0]`).
  final bool subtree;

  /// The offset just after the reference: where its value is shown.
  final int end;

  /// The default of a placeholder (`${port:8080}`), used when no entry
  /// gives the key.
  final String? fallback;
}

/// The placeholders of the template string whose contents start at
/// [contentStart] of a file and read [contents]; one in the default of
/// another (`b` of `${a:${b}}`) is [PropertyReference.nested], as Spring
/// resolves it too.
Iterable<PropertyReference> placeholderReferences(
  String contents,
  int contentStart,
) sync* {
  var outerEnd = -1;
  for (final part in scanTemplate(contents)) {
    final nested = part.start < outerEnd;
    if (!nested) {
      outerEnd = part.end;
    }
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
      nested: nested,
    );
  }
}

/// The groups of properties the `@ConfigurationProperties` classes bind,
/// by class name: `shop` for `@ConfigurationProperties('shop') class Shop`,
/// and `shop.address` for the class `Address` of its field
/// `final Address address;` (a nested group, as Boot binds it), followed
/// through the classes of the workspace.
final class ConfigurationPropertiesGroups {
  /// The groups of [classes], every class of the workspace.
  ConfigurationPropertiesGroups(Iterable<ClassDeclaration> classes) {
    final byName = <String, List<ClassDeclaration>>{};
    for (final declaration in classes) {
      (byName[declaration.namePart.typeName.lexeme] ??= []).add(declaration);
    }
    _classes = byName.keys.toSet();
    final pending = <(ClassDeclaration, String, int)>[
      for (final declaration in classes)
        if (_prefixOf(declaration) case final prefix?) (declaration, prefix, 0),
    ];
    while (pending.isNotEmpty) {
      final (declaration, prefix, depth) = pending.removeLast();
      final prefixes = _prefixes[declaration.namePart.typeName.lexeme] ??= {};
      if (!prefixes.add(prefix) || depth >= _maxDepth) {
        continue;
      }
      for (final (name, type, _) in _fields(declaration)) {
        if (type case final type? when _classes.contains(type)) {
          for (final nested in byName[type]!) {
            pending.add((nested, _join(prefix, name), depth + 1));
          }
        }
      }
    }
  }

  static const _maxDepth = 8;

  late final Set<String> _classes;
  final _prefixes = <String, Set<String>>{};

  /// The fields the groups' classes of [unit] bind: for
  /// `@ConfigurationProperties('shop') class Shop { final int maxBasketSize; }`
  /// the key `shop.max-basket-size`, at the end of the field's name, with
  /// the field's literal initializer as its default. Every type binds (an
  /// enum, a `DataSize`, a type of a dependency) but a class of the
  /// workspace, which is a nested group whose own fields are listed; a
  /// `Map`, `List`, `Set` or `Iterable` binds the keys below it too.
  /// Static fields are left out.
  Iterable<PropertyReference> fieldsOf(CompilationUnit unit) sync* {
    for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
      final prefixes = _prefixes[declaration.namePart.typeName.lexeme];
      if (prefixes == null) {
        continue;
      }
      for (final prefix in prefixes) {
        for (final (name, type, variable) in _fields(declaration)) {
          if (type != null && _classes.contains(type)) {
            continue;
          }
          yield PropertyReference(
            _join(prefix, name),
            variable.name.end,
            nameStart: variable.name.offset,
            nameEnd: variable.name.end,
            fallback: literalValue(variable.initializer),
            derived: true,
            subtree: const {'Map', 'List', 'Set', 'Iterable'}.contains(type),
          );
        }
      }
    }
  }

  static String _join(String prefix, String name) =>
      prefix.isEmpty ? kebabCase(name) : '$prefix.${kebabCase(name)}';

  /// The instance fields of [declaration]: each one's name (leading `_`
  /// dropped), the simple name of its type (null without a named type),
  /// and its declaration.
  static Iterable<(String, String?, VariableDeclaration)> _fields(
    ClassDeclaration declaration,
  ) sync* {
    for (final member
        in declaration.body.members.whereType<FieldDeclaration>()) {
      if (member.isStatic) {
        continue;
      }
      final type = member.fields.type;
      for (final variable in member.fields.variables) {
        yield (
          variable.name.lexeme.replaceFirst(RegExp('^_+'), ''),
          type is NamedType ? type.name.lexeme : null,
          variable,
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
