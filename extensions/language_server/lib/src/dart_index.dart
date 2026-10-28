import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// The annotations that make a class a bean, by name.
///
/// Annotation classes of the workspace that extend one of them count too
/// (`SpringWorkspace.stereotypes`). The web and WebSocket ones are listed
/// by name because the classes they extend live in a dependency, which is
/// not indexed.
const baseStereotypes = {
  'Component',
  'Service',
  'Repository',
  'Controller',
  'Configuration',
  'Named',
  'ConfigurationProperties',
  'AutoConfiguration',
  // spring_boot_starter_flutter: a plain class whose proxy is a ChangeNotifier.
  'ChangeNotifierComponent',
  // spring_web_dart (spring_boot_starter_web): the classes they extend are
  // in a dependency, which is not indexed, so they are listed by name.
  'RestController',
  'ControllerAdvice',
  'RestControllerAdvice',
  // spring_boot_starter_websocket: a server endpoint.
  'WebSocketEndpoint',
};

/// Stereotypes whose first positional argument is not the bean name but a
/// prefix or a path. Their bean name comes from a `name:` argument when
/// they have one, else from the class name.
const unnamedStereotypes = {
  'ConfigurationProperties',
  'AutoConfiguration',
  // The first argument is the path.
  'WebSocketEndpoint',
};

/// A Dart source file parsed for syntax only, with the index the
/// workspace needs: its top-level classes and a way to find the node at
/// an offset.
///
/// There is no type resolution, so parsing is fast and works without
/// `pub get` and on code that does not compile. The workspace keeps one
/// per file and parses it again when the file or the open document
/// changes.
final class DartFile {
  DartFile._(this.path, this.text, this.unit, this.lineInfo, this.classes);

  /// Parses [text] as the content of [path]. Syntax errors do not throw: the
  /// tree holds what could be read.
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

  /// The absolute path of the file.
  final String path;

  /// The text that was parsed: the open document's, when there is one.
  final String text;

  /// The syntax tree.
  final CompilationUnit unit;

  /// Converts offsets to lines and columns and back.
  final LineInfo lineInfo;

  /// The top-level class declarations (not mixins, enums or extension
  /// types), where beans and supertypes are found.
  final List<ClassInfo> classes;

  /// The innermost syntax node at [offset] (an offset at a node's end counts
  /// as inside it): where every editor query starts.
  AstNode? nodeAt(int offset) {
    final finder = _NodeAt(offset);
    unit.accept(finder);
    return finder.found;
  }
}

/// A top-level class of a [DartFile], with what the bean index needs: its
/// name, its direct supertypes and its annotations.
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

  /// The file that declares the class.
  final String path;

  /// The class name.
  final String name;

  /// The offset of the name, where navigation to the class goes.
  final int nameOffset;

  /// The simple names of the direct supertypes: `extends`, `implements` and
  /// `with`.
  final Set<String> supertypes;

  /// The annotations on the class.
  final List<Annotation> annotations;

  /// The class's syntax tree, for its members.
  final ClassDeclaration declaration;

  /// The names of [annotations], as [annotationName] reads them.
  Set<String> get annotationNames => {
    for (final annotation in annotations) annotationName(annotation),
  };
}

/// How a bean is declared.
enum BeanKind {
  /// A class with a stereotype annotation (`@Service()`, `@Component()`,
  /// ...).
  component,

  /// A `@Bean` method of such a class.
  beanMethod,
}

/// A bean declared in the workspace's sources, as far as the syntax shows
/// it: its name, type, qualifiers and where it is declared.
///
/// Go to definition leads to [offset] of [path]; a hover lists the
/// [summary] of each candidate.
final class BeanInfo {
  /// A bean; the index fills [providedTypes] afterwards.
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
    this.contextGetter,
  });

  /// The bean name: the one given in the annotation, else the class name in
  /// lower camel case ([defaultBeanName]) or the `@Bean` method's name.
  final String name;

  /// The class of a component, the declared return type of a `@Bean` method.
  final String typeName;

  /// Whether a class or a `@Bean` method declares the bean.
  final BeanKind kind;

  /// The file that declares the bean.
  final String path;

  /// The offset of the class or method name.
  final int offset;

  /// The length of that name.
  final int length;

  /// The other names given by `@Bean(aliases: [...])`.
  final Set<String> aliases;

  /// The values of the `@Qualifier('...')` annotations on the declaration.
  final Set<String> qualifiers;

  /// Whether it is marked `@Primary`; such beans are listed first.
  final bool primary;

  /// The profiles of its `@Profile([...])`, shown in hovers; beans are not
  /// filtered by them.
  final List<String> profiles;

  /// The class that declares a `@Bean` method; `null` for a component.
  final String? owner;

  /// With `@BuildContextAccess` (spring_boot_starter_flutter): the name of
  /// the generated `BuildContext` getter (`context.basket`).
  final String? contextGetter;

  /// Every type name the bean can be injected as: its type and that type's
  /// supertypes known to the workspace. Set by the index once all beans are
  /// found.
  Set<String> providedTypes = const {};

  /// Whether [qualifier] selects this bean: its name, one of its aliases or
  /// one of its qualifiers.
  bool matches(String qualifier) =>
      name == qualifier ||
      aliases.contains(qualifier) ||
      qualifiers.contains(qualifier);

  /// One line describing the bean for hovers, such as
  /// `bean 'checkout': Checkout` or `@Bean 'clock': Clock (in TimeConfig)`,
  /// with `@Primary` and `@Profile` when set.
  String get summary =>
      "${kind == BeanKind.component ? 'bean' : '@Bean'} '$name': $typeName"
      '${owner == null ? '' : ' (in $owner)'}'
      '${primary ? ' @Primary' : ''}'
      '${profiles.isEmpty ? '' : ' @Profile($profiles)'}';
}

/// The name of an annotation's type: `Service` for `@Service()` and for
/// `@s.Service()`, `Cacheable` for `@Cacheable.of()`. Without resolution
/// `A.b` is ambiguous; a lower-case last part is read as a named
/// constructor, not a type.
String annotationName(Annotation annotation) => switch (annotation.name) {
  PrefixedIdentifier(:final prefix, :final identifier) =>
    _isTypeName(identifier.name) ? identifier.name : prefix.name,
  final Identifier name => name.name,
};

bool _isTypeName(String name) =>
    name.isNotEmpty && name[0].toUpperCase() == name[0] && name[0] != '_';

/// The value of [expression] when it is a plain string literal, or
/// adjacent plain literals (`'a' 'b'`); `null` for anything else,
/// interpolation included.
String? stringValue(Expression? expression) => switch (expression) {
  SimpleStringLiteral(:final value) => value,
  AdjacentStrings(:final strings) =>
    strings.every((s) => s is SimpleStringLiteral)
        ? strings.map((s) => (s as SimpleStringLiteral).value).join()
        : null,
  _ => null,
};

/// The plain strings of a list literal (`['a', 'b']`); other elements are
/// skipped, and anything but a list literal gives an empty list.
List<String> stringList(Expression? expression) => [
  if (expression is ListLiteral)
    for (final element in expression.elements)
      if (element is Expression) ?stringValue(element),
];

/// The positional argument at [index] of [annotation]; `null` when there
/// are fewer.
Expression? positionalArgument(Annotation annotation, [int index = 0]) {
  final positional = [
    for (final argument in annotation.arguments?.arguments ?? <Argument>[])
      if (argument is! NamedArgument) argument.argumentExpression,
  ];
  return index < positional.length ? positional[index] : null;
}

/// The named argument [name] of [annotation]; `null` when it is absent.
Expression? namedArgument(Annotation annotation, String name) {
  for (final argument in annotation.arguments?.arguments ?? <Argument>[]) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return argument.argumentExpression;
    }
  }
  return null;
}

/// The bean name the framework gives a class called [name]:
/// `orderService` for `OrderService`, but `URLService` stays as it is (two
/// leading capitals, the rule of Java's `Introspector.decapitalize`).
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

/// The simple name of [type], without `?` and type arguments (`List` for
/// `List<Mailer>?`); `null` for a function or record type.
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
