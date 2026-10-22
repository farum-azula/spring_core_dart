import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// Annotations that make a class a bean; classes extending one of them are
/// stereotypes too (custom `@Component` subclasses).
const baseStereotypes = {
  'Component',
  'Service',
  'Repository',
  'Controller',
  'Configuration',
  'Named',
  'ConfigurationProperties',
  'AutoConfiguration',
};

/// Stereotypes whose first argument is not the bean name.
const unnamedStereotypes = {'ConfigurationProperties', 'AutoConfiguration'};

/// A parsed Dart file.
final class DartFile {
  DartFile._(this.path, this.text, this.unit, this.lineInfo, this.classes);

  /// Parses [text] (syntax only: no type resolution, so it is fast and works
  /// without `pub get`).
  factory DartFile.parse(String path, String text) {
    final result = parseString(
      content: text,
      path: path,
      throwIfDiagnostics: false,
    );
    final unit = result.unit;
    final classes = <ClassInfo>[];
    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration) {
        classes.add(ClassInfo._from(path, declaration));
      }
    }
    return DartFile._(path, text, unit, result.lineInfo, classes);
  }

  /// File path.
  final String path;

  /// Source text.
  final String text;

  /// Syntax tree.
  final CompilationUnit unit;

  /// Offsets ↔ lines and columns.
  final LineInfo lineInfo;

  /// Top-level classes.
  final List<ClassInfo> classes;

  /// The innermost node that contains [offset].
  AstNode? nodeAt(int offset) {
    final finder = _NodeAt(offset);
    unit.accept(finder);
    return finder.found;
  }
}

/// A class declaration: name, supertypes and annotations.
final class ClassInfo {
  ClassInfo._(
    this.path,
    this.name,
    this.nameOffset,
    this.supertypes,
    this.annotations,
    this.declaration,
  );

  factory ClassInfo._from(String path, ClassDeclaration node) {
    final nameToken = node.namePart.typeName;
    return ClassInfo._(
      path,
      nameToken.lexeme,
      nameToken.offset,
      {
        if (node.extendsClause case final clause?)
          clause.superclass.name.lexeme,
        for (final type in node.implementsClause?.interfaces ?? <NamedType>[])
          type.name.lexeme,
        for (final type in node.withClause?.mixinTypes ?? <NamedType>[])
          type.name.lexeme,
      },
      node.metadata,
      node,
    );
  }

  /// File path.
  final String path;

  /// Class name.
  final String name;

  /// Offset of the name.
  final int nameOffset;

  /// Direct supertype names (`extends`, `implements`, `with`).
  final Set<String> supertypes;

  /// Annotations on the class.
  final List<Annotation> annotations;

  /// The declaration.
  final ClassDeclaration declaration;

  /// Names of the annotations.
  Set<String> get annotationNames => {
    for (final annotation in annotations) annotationName(annotation),
  };
}

/// Where a bean comes from.
enum BeanKind {
  /// A class with a stereotype annotation.
  component,

  /// A `@Bean` method.
  beanMethod,
}

/// A bean found in the sources.
final class BeanInfo {
  /// Creates a bean.
  BeanInfo({
    required this.name,
    required this.typeName,
    required this.kind,
    required this.path,
    required this.offset,
    required this.length,
    this.aliases = const {},
    this.qualifiers = const {},
    this.primary = false,
    this.profiles = const [],
    this.owner,
  });

  /// Bean name.
  final String name;

  /// The class of a component, the return type of a `@Bean` method.
  final String typeName;

  /// Component or `@Bean` method.
  final BeanKind kind;

  /// File path.
  final String path;

  /// Offset of the class or method name.
  final int offset;

  /// Length of the name.
  final int length;

  /// `@Bean(aliases: [...])`.
  final Set<String> aliases;

  /// `@Qualifier('x')` on the declaration.
  final Set<String> qualifiers;

  /// `@Primary`.
  final bool primary;

  /// `@Profile([...])`.
  final List<String> profiles;

  /// The configuration class of a `@Bean` method.
  final String? owner;

  /// Every type the bean can be injected as (filled by the index).
  Set<String> providedTypes = const {};

  /// Whether the bean answers to [qualifier] (name, alias or qualifier).
  bool matches(String qualifier) =>
      name == qualifier ||
      aliases.contains(qualifier) ||
      qualifiers.contains(qualifier);

  /// One line for hovers.
  String get summary =>
      "${kind == BeanKind.component ? 'bean' : '@Bean'} '$name': $typeName"
      '${owner == null ? '' : ' (in $owner)'}'
      '${primary ? ' @Primary' : ''}'
      '${profiles.isEmpty ? '' : ' @Profile($profiles)'}';
}

/// The name of an annotation (`Service` for `@Service()` or `@s.Service()`).
String annotationName(Annotation annotation) => switch (annotation.name) {
  PrefixedIdentifier(:final identifier) => identifier.name,
  final Identifier name => name.name,
};

/// The string value of an expression, if it is a plain string literal.
String? stringValue(Expression? expression) => switch (expression) {
  SimpleStringLiteral(:final value) => value,
  AdjacentStrings(:final strings) =>
    strings.every((s) => s is SimpleStringLiteral)
        ? strings.map((s) => (s as SimpleStringLiteral).value).join()
        : null,
  _ => null,
};

/// Strings of a list literal expression (`['a', 'b']`).
List<String> stringList(Expression? expression) => [
  if (expression is ListLiteral)
    for (final element in expression.elements)
      if (element is Expression) ?stringValue(element),
];

/// The positional argument [index] of [annotation].
Expression? positionalArgument(Annotation annotation, [int index = 0]) {
  final positional = [
    for (final argument in annotation.arguments?.arguments ?? <Argument>[])
      if (argument is! NamedArgument) argument.argumentExpression,
  ];
  return index < positional.length ? positional[index] : null;
}

/// The named argument [name] of [annotation].
Expression? namedArgument(Annotation annotation, String name) {
  for (final argument in annotation.arguments?.arguments ?? <Argument>[]) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return argument.argumentExpression;
    }
  }
  return null;
}

/// Spring's default bean name: `orderService` for `OrderService`, but
/// `URLService` stays (two leading capitals).
String defaultBeanName(String name) {
  if (name.isEmpty) {
    return name;
  }
  if (name.length > 1 &&
      name[0].toUpperCase() == name[0] &&
      name[1].toUpperCase() == name[1] &&
      name[1].toLowerCase() != name[1]) {
    return name;
  }
  return name[0].toLowerCase() + name.substring(1);
}

/// The type name of a type annotation without `?` and type arguments.
String? typeName(TypeAnnotation? type) =>
    type is NamedType ? type.name.lexeme : null;

final class _NodeAt extends GeneralizingAstVisitor<void> {
  _NodeAt(this.offset);

  final int offset;
  AstNode? found;

  @override
  void visitNode(AstNode node) {
    if (node.offset <= offset && offset <= node.end) {
      found = node;
      node.visitChildren(this);
    }
  }
}
