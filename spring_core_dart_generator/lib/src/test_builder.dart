import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Writes `test/spring/<name>.test.spring.dart` for a `test/<name>_test.dart` that
/// declares `@SpringBootTest` classes: `runSpringTests()`, declaring their
/// tests with `springBootTest`, `group`, `test`, `setUp` and `tearDown`.
///
/// The test file is read as syntax, not resolved: the generated file
/// imports what the test file imports (with the same prefixes and
/// combinators) and the test file itself, so every type and constant
/// written in the test class means the same in the generated code. Bean
/// types are not written out: `instance.checkout = app.getBean();` takes
/// its type from the field.
///
/// ```dart
/// // test/checkout_test.dart
/// import 'spring/checkout.test.spring.dart';
///
/// @SpringBootTest()
/// class CheckoutTest {
///   @Autowired()
///   late Checkout checkout;
///
///   @Test()
///   void pays() => expect(checkout.pay(3), 'paid 3.0');
/// }
///
/// void main() => runSpringTests();
///
/// // test/spring/checkout.test.spring.dart (generated)
/// void runSpringTests() {
///   _sbt.group('CheckoutTest', () {
///     final instance = CheckoutTest();
///     final app = _sbt.springBootTest(_app.springApplication);
///     _sbt.setUp(() {
///       instance.checkout = app.getBean();
///     });
///     _sbt.test('pays', () => instance.pays());
///   });
/// }
/// ```
///
/// Spring (Java): JUnit's `SpringExtension` does this at runtime with
/// reflection; Dart has none, so it is generated.
class SpringTestBuilder implements Builder {
  /// Creates the builder.
  SpringTestBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
    '^test/{{}}_test.dart': ['test/spring/{{}}.test.spring.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    final text = await buildStep.readAsString(input);
    if (!text.contains('SpringBootTest')) {
      return;
    }
    final parsed = parseString(
      content: text,
      path: input.path,
      throwIfDiagnostics: false,
    );
    final file = TestFile(input.path, parsed.unit, parsed.lineInfo);
    if (file.testClasses.isEmpty) {
      return;
    }
    final output = springTestOutput(input);
    final applications = <String>[];
    await for (final asset in buildStep.findAssets(Glob('{bin,lib}/**.dart'))) {
      if (asset.path.endsWith('.spring.dart')) {
        continue;
      }
      final source = await buildStep.readAsString(asset);
      if (_entryPoint.hasMatch(source)) {
        applications.add(asset.path);
      }
    }
    applications.sort();
    if (!file.imports.any((d) => file.resolve(d) == output.path)) {
      final uri = p.url.relative(output.path, from: p.url.dirname(input.path));
      log.warning(
        "${input.path} does not import '$uri': add import '$uri'; and "
        'void main() => runSpringTests();',
      );
    }
    final source = TestEmitter(
      file: file,
      output: output,
      package: input.package,
      applications: applications,
    ).emit();
    await buildStep.writeAsString(output, source);
  }
}

// `@SpringBootApplication()` at the start of a line, not in a comment.
final _entryPoint = RegExp(
  r'^\s*@(\w+\.)?SpringBootApplication\(',
  multiLine: true,
);

/// Where the generated file of the test [input] goes:
/// `test/orders/basket_test.dart` → `test/spring/orders/basket.test.spring.dart`.
AssetId springTestOutput(AssetId input) {
  final inTest = input.path.substring('test/'.length);
  return AssetId(
    input.package,
    'test/spring/'
    '${inTest.substring(0, inTest.length - '_test.dart'.length)}'
    '.test.spring.dart',
  );
}

/// A build error in a test class, pointing at the member.
final class TestClassException implements Exception {
  /// The error [message] at [location] (`path:line:column`).
  TestClassException(this.location, this.message);

  /// Where: `test/checkout_test.dart:12:3`.
  final String location;

  /// What is wrong and how to fix it.
  final String message;

  @override
  String toString() => '$location: $message';
}

/// The parsed test file: its imports and `@SpringBootTest` classes.
final class TestFile {
  /// Reads [unit], the syntax of the file at [path].
  TestFile(this.path, this.unit, this.lineInfo);

  /// The file's path in its package (`test/checkout_test.dart`).
  final String path;

  /// The file's syntax.
  final CompilationUnit unit;

  /// Line numbers for errors.
  final LineInfo lineInfo;

  /// The classes annotated with `@SpringBootTest`.
  late final List<ClassDeclaration> testClasses = [
    for (final declaration in unit.declarations)
      if (declaration is ClassDeclaration &&
          annotation(declaration.metadata, 'SpringBootTest') != null)
        declaration,
  ];

  /// The class called [name] declared in this file.
  ClassDeclaration? classNamed(String name) {
    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration &&
          declaration.namePart.typeName.lexeme == name) {
        return declaration;
      }
    }
    return null;
  }

  /// The import directives, as written.
  List<ImportDirective> get imports => [
    for (final directive in unit.directives)
      if (directive is ImportDirective) directive,
  ];

  /// The path in the package a relative import points at, or `null` for
  /// a `package:` or `dart:` import.
  String? resolve(ImportDirective directive) {
    final uri = directive.uri.stringValue;
    if (uri == null || Uri.parse(uri).hasScheme) {
      return null;
    }
    return p.url.normalize(p.url.join(p.url.dirname(path), uri));
  }

  /// An error at [node].
  TestClassException error(AstNode node, String message) {
    final location = lineInfo.getLocation(node.offset);
    return TestClassException(
      '$path:${location.lineNumber}:${location.columnNumber}',
      message,
    );
  }
}

/// The annotation called [name] in [metadata] (with or without an import
/// prefix: `@Test()`, `@spring.Test()`), or `null`.
Annotation? annotation(List<Annotation> metadata, String name) {
  for (final annotation in metadata) {
    if (_simpleName(annotation) == name) {
      return annotation;
    }
  }
  return null;
}

/// Every annotation called [name] in [metadata].
List<Annotation> annotations(List<Annotation> metadata, String name) => [
  for (final annotation in metadata)
    if (_simpleName(annotation) == name) annotation,
];

String _simpleName(Annotation annotation) => switch (annotation.name) {
  PrefixedIdentifier(:final identifier) => identifier.name,
  final Identifier name => name.name,
};

/// The source of [annotation]'s positional argument [index], or `null`.
String? positional(Annotation annotation, int index) {
  final arguments = [
    for (final argument in annotation.arguments?.arguments ?? <Argument>[])
      if (argument is! NamedArgument) argument,
  ];
  return index < arguments.length
      ? arguments[index].argumentExpression.toSource()
      : null;
}

/// The source of [annotation]'s named argument [name], or `null`.
String? named(Annotation annotation, String name) {
  for (final argument in annotation.arguments?.arguments ?? <Argument>[]) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return argument.argumentExpression.toSource();
    }
  }
  return null;
}

// The annotations of a test class, of its members and where they belong.
const _classOnly = {
  'SpringBootTest',
  'ActiveProfiles',
  'TestPropertySource',
  'TestEnvironment',
};

/// Writes the generated library for a [TestFile].
final class TestEmitter {
  /// An emitter for [file], written to [output] in [package], whose
  /// `@SpringBootApplication` entry points are [applications] (paths in
  /// the package).
  TestEmitter({
    required this.file,
    required this.output,
    required this.package,
    required this.applications,
  });

  /// The test file.
  final TestFile file;

  /// The generated library.
  final AssetId output;

  /// The package of the test.
  final String package;

  /// The `@SpringBootApplication` entry points of the package.
  final List<String> applications;

  // Entry point → its import prefix in the generated file.
  final Map<String, String> _applicationPrefixes = {};

  final StringBuffer _body = StringBuffer();

  /// The formatted source of the generated library.
  String emit() {
    for (final testClass in file.testClasses) {
      _testClass(testClass);
    }
    final out = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln(
        '// Generated by spring_core_dart_generator from the @SpringBootTest '
        'classes of ${p.url.basename(file.path)}.',
      )
      ..writeln()
      ..writeln(
        '// ignore_for_file: directives_ordering, unused_import, '
        'no_leading_underscores_for_library_prefixes, '
        'unnecessary_import, unnecessary_lambdas',
      )
      ..writeln();
    // The test file's imports; relative ones re-pointed from test/spring/.
    for (final directive in file.imports) {
      final target = file.resolve(directive);
      if (target == output.path) {
        continue;
      }
      var source = directive.toSource();
      if (target != null) {
        source = source.replaceFirst(
          directive.uri.toSource(),
          "'${_relative(target)}'",
        );
      }
      out.writeln(source);
    }
    out
      ..writeln("import '${_relative(file.path)}';")
      ..writeln(
        "import 'package:spring_boot_starter_test/generated.dart' as _sbt;",
      );
    for (final MapEntry(key: entry, value: prefix)
        in _applicationPrefixes.entries) {
      out.writeln("import '${_applicationImport(entry)}' as $prefix;");
    }
    out
      ..writeln()
      ..writeln(
        '/// Declares the tests of the `@SpringBootTest` classes of '
        '`${p.url.basename(file.path)}`.',
      )
      ..writeln('void runSpringTests() {')
      ..write(_body)
      ..writeln('}');
    return DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)
        .format(out.toString());
  }

  String _applicationImport(String entry) {
    final generated = '${entry.substring(0, entry.length - 5)}.spring.dart';
    if (generated.startsWith('lib/')) {
      return 'package:$package/${generated.substring(4)}';
    }
    return _relative(generated);
  }

  // [path] in the package, relative to the generated file.
  String _relative(String path) =>
      p.url.relative(path, from: p.url.dirname(output.path));

  String _application(ClassDeclaration testClass, Annotation springBootTest) {
    final given = named(springBootTest, 'application');
    final String entry;
    if (given != null) {
      final path = _stringValue(given);
      if (path == null || !applications.contains(path)) {
        throw file.error(
          springBootTest,
          '$given is not an entry point with @SpringBootApplication of this '
          'package (${applications.isEmpty ? 'none found' : applications.join(', ')}).',
        );
      }
      entry = path;
    } else if (applications.length == 1) {
      entry = applications.single;
    } else if (applications.isEmpty) {
      throw file.error(
        springBootTest,
        'No application in this package: @SpringBootTest needs a '
        "@SpringBootApplication entry point in bin/ or lib/.",
      );
    } else {
      throw file.error(
        springBootTest,
        'Several applications in this package (${applications.join(', ')}): '
        "name one, @SpringBootTest(application: '${applications.first}').",
      );
    }
    final prefix = _applicationPrefixes.putIfAbsent(
      entry,
      () => '_app${_applicationPrefixes.length}',
    );
    return '$prefix.springApplication';
  }

  void _testClass(ClassDeclaration testClass) {
    final name = testClass.namePart.typeName.lexeme;
    final springBootTest = annotation(testClass.metadata, 'SpringBootTest')!;
    _checkConstructor(testClass);
    final members = _Members.of(file, testClass, outer: true);

    _body.writeln("_sbt.group(${_literal(name)}, () {");
    for (final method in members.beforeAll) {
      _body.writeln('_sbt.setUpAll(() => $name.$method());');
    }
    // Declared before springBootTest: tearDownAll runs in reverse order, so
    // these run after the context is closed.
    for (final method in members.afterAll) {
      _body.writeln('_sbt.tearDownAll(() => $name.$method());');
    }
    _body.writeln('final instance = $name();');
    if (members.capturedOutput.isNotEmpty) {
      _body.writeln('final logs = _sbt.captureLogs();');
    }
    _body.writeln(
      'final app = _sbt.springBootTest(${_application(testClass, springBootTest)},',
    );
    _startOptions(testClass, springBootTest, members, name);
    _body.writeln(');');
    _classBody(testClass, members, 'instance');
    _body.writeln('}${_groupOptions(testClass.metadata)});');
  }

  void _startOptions(
    ClassDeclaration testClass,
    Annotation springBootTest,
    _Members members,
    String name,
  ) {
    final metadata = testClass.metadata;
    if (named(springBootTest, 'args') case final args?) {
      _body.writeln('args: $args,');
    }
    final propertySource = annotation(metadata, 'TestPropertySource');
    final properties = [
      ?named(springBootTest, 'properties'),
      if (propertySource != null) ?named(propertySource, 'properties'),
    ];
    if (properties.length == 1) {
      _body.writeln('properties: ${properties.single},');
    } else if (properties.length == 2) {
      _body.writeln('properties: {...${properties[0]}, ...${properties[1]}},');
    }
    if (propertySource != null) {
      if (named(propertySource, 'locations') case final locations?) {
        _body.writeln('propertyFiles: $locations,');
      }
    }
    if (named(springBootTest, 'resourceDirectories') case final directories?) {
      _body.writeln('resourceDirectories: $directories,');
    }
    if (annotation(metadata, 'ActiveProfiles') case final profiles?) {
      _body.writeln('profiles: ${positional(profiles, 0)},');
    }
    if (annotation(metadata, 'TestEnvironment') case final environment?) {
      _body.writeln('systemEnvironment: ${positional(environment, 0)},');
    }
    switch (members.dynamicProperties) {
      case [final method]:
        _body.writeln('dynamicProperties: $name.$method,');
      case [_, _, ...] && final methods:
        _body.writeln(
          'dynamicProperties: (registry) {'
          '${methods.map((m) => '$name.$m(registry);').join()}},',
        );
    }
    if (members.initializers.isNotEmpty) {
      _body.writeln(
        'initializers: [${members.initializers.map((m) => '_sbt.ApplicationContextInitializer.of($name.$m)').join(', ')}],',
      );
    }
    if (members.testBeans.isNotEmpty) {
      _body.writeln('overrides: [');
      for (final bean in members.testBeans) {
        _body.writeln('${_override(bean)},');
      }
      _body.writeln('],');
    }
  }

  String _override(_Field bean) {
    final testBean = annotation(bean.metadata, 'TestBean')!;
    final value = 'instance.${bean.name}';
    final name = named(testBean, 'name');
    final type = named(testBean, 'type');
    if (type != null) {
      return '_sbt.BeanOverride<$type>($value${name == null ? '' : ', name: $name'})';
    }
    if (name != null) {
      return '_sbt.BeanOverride.named($value, name: $name)';
    }
    final declared = bean.type;
    if (declared == null) {
      throw file.error(
        bean.node,
        "@TestBean field '${bean.name}' needs the type of the bean it "
        'replaces: write it (final PaymentGateway ${bean.name} = ...), or '
        '@TestBean(type: PaymentGateway), or @TestBean(name: ...).',
      );
    }
    final nonNullable = declared.endsWith('?')
        ? declared.substring(0, declared.length - 1)
        : declared;
    return '_sbt.BeanOverride<$nonNullable>($value)';
  }

  // Injection, lifecycle and tests of a class (the test class or a
  // @Nested one) whose instance is [instance].
  void _classBody(
    ClassDeclaration declaration,
    _Members members,
    String instance,
  ) {
    final inject = <String>[
      for (final field in members.autowired)
        '$instance.${field.name} = ${_injection(field)};',
      for (final field in members.capturedOutput)
        '$instance.${field.name} = logs;',
    ];
    if (inject.isNotEmpty) {
      // Before every test: after a @DirtiesContext restart the beans are
      // new.
      _body.writeln('_sbt.setUp(() {${inject.join()}});');
    }
    if (annotation(declaration.metadata, 'DirtiesContext') != null) {
      _body.writeln('_sbt.setUp(app.markDirty);');
    }
    for (final method in members.beforeEach) {
      _body.writeln('_sbt.setUp(() => $instance.$method());');
    }
    for (final method in members.afterEach) {
      _body.writeln('_sbt.tearDown(() => $instance.$method());');
    }
    for (final member in members.ordered) {
      switch (member) {
        case _Method():
          _test(member, instance);
        case _Field():
          _nested(member, instance);
      }
    }
  }

  String _injection(_Field field) {
    final type = field.type!;
    final nullable = type.endsWith('?');
    if (annotation(field.metadata, 'Value') case final value?) {
      final expression = positional(value, 0);
      return nullable
          ? 'app.optionalValue($expression)'
          : 'app.value($expression)';
    }
    final qualifier = switch (annotation(field.metadata, 'Qualifier')) {
      final q? => 'qualifier: ${positional(q, 0)}',
      null => '',
    };
    final simple = field.simpleTypeName;
    switch (simple) {
      case 'SpringBootTestContext':
        return 'app';
      case 'ApplicationContext' || 'ConfigurableApplicationContext':
        return 'app.context';
      case 'Environment' || 'ConfigurableEnvironment':
        return 'app.environment';
      case 'List' || 'Iterable':
        return 'app.getBeans($qualifier)';
    }
    return nullable ? 'app.findBean($qualifier)' : 'app.getBean($qualifier)';
  }

  void _test(_Method method, String instance) {
    final metadata = method.metadata;
    final name =
        positional(annotation(metadata, 'DisplayName') ?? _none, 0) ??
        positional(annotation(metadata, 'Test')!, 0) ??
        _literal(_words(method.name));
    final dirties = annotation(metadata, 'DirtiesContext') != null;
    final call = '$instance.${method.name}()';
    final body = dirties
        ? '() {app.markDirty(); return $call;}'
        : '() => $call';
    _body.writeln('_sbt.test($name, $body${_groupOptions(metadata)});');
  }

  void _nested(_Field field, String instance) {
    final nested = annotation(field.metadata, 'Nested')!;
    final type = field.initializerClass;
    final declaration = type == null ? null : file.classNamed(type);
    if (declaration == null) {
      throw file.error(
        field.node,
        "@Nested field '${field.name}' must be created with a class of this "
        'file: final ${field.name} = WithOneBook();',
      );
    }
    _checkConstructor(declaration);
    final members = _Members.of(file, declaration, outer: false);
    final name = positional(nested, 0) ?? _literal(_words(field.name));
    final inner = '$instance.${field.name}';
    _body.writeln('_sbt.group($name, () {');
    _classBody(declaration, members, inner);
    _body.writeln('}${_groupOptions(declaration.metadata)});');
  }

  // `, skip: ..., tags: [...], timeout: ...` from @Disabled, @Tag and
  // @TestOptions.
  String _groupOptions(List<Annotation> metadata) {
    final options = <String>[];
    if (annotation(metadata, 'Disabled') case final disabled?) {
      options.add('skip: ${positional(disabled, 0) ?? 'true'}');
    }
    final tags = [
      for (final tag in annotations(metadata, 'Tag')) ?positional(tag, 0),
    ];
    if (tags.isNotEmpty) {
      options.add('tags: [${tags.join(', ')}]');
    }
    if (annotation(metadata, 'TestOptions') case final testOptions?) {
      for (final option in ['timeout', 'retry', 'testOn', 'onPlatform']) {
        if (named(testOptions, option) case final value?) {
          options.add('$option: $value');
        }
      }
    }
    return options.isEmpty ? '' : ', ${options.join(', ')}';
  }

  void _checkConstructor(ClassDeclaration declaration) {
    for (final member in declaration.body.members) {
      if (member is ConstructorDeclaration &&
          member.name == null &&
          member.factoryKeyword == null &&
          member.parameters.parameters.any((p) => p.isRequired)) {
        throw file.error(
          member,
          "'${declaration.namePart.typeName.lexeme}' needs a constructor "
          'without required parameters: the generated test creates it.',
        );
      }
    }
  }

  static final Annotation _none = parseString(content: '@_N() void _n() {}')
      .unit
      .declarations
      .single
      .metadata
      .single;
}

/// A Dart string literal of [value].
String _literal(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

/// `paysThroughTheFake` → `pays through the fake`; `checkout_pays` →
/// `checkout pays`.
String _words(String name) => name
    .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .replaceAll('_', ' ')
    .toLowerCase()
    .trim();

String? _stringValue(String source) {
  final match = RegExp(r'''^r?(['"])(.*)\1$''').firstMatch(source);
  return match?[2];
}

sealed class _Member {
  List<Annotation> get metadata;
}

final class _Method extends _Member {
  _Method(this.node);

  final MethodDeclaration node;

  String get name => node.name.lexeme;

  @override
  List<Annotation> get metadata => node.metadata;
}

final class _Field extends _Member {
  _Field(this.node, this.declarations, this.variable);

  final FieldDeclaration node;
  final VariableDeclarationList declarations;
  final VariableDeclaration variable;

  String get name => variable.name.lexeme;

  @override
  List<Annotation> get metadata => node.metadata;

  /// The declared type, as written; `null` when inferred.
  String? get type => declarations.type?.toSource();

  /// `Checkout` for `Checkout`, `p.Checkout?` and `List<Checkout>`.
  String? get simpleTypeName => switch (declarations.type) {
    final NamedType named => named.name.lexeme,
    _ => null,
  };

  /// `WithOneBook` for `= WithOneBook()`.
  String? get initializerClass => switch (variable.initializer) {
    InstanceCreationExpression(:final constructorName) =>
      constructorName.type.name.lexeme,
    MethodInvocation(target: null, :final methodName) => methodName.name,
    _ => null,
  };
}

// The annotated members of a test class (or a @Nested class), checked.
final class _Members {
  _Members._();

  final List<String> beforeAll = [];
  final List<String> afterAll = [];
  final List<String> beforeEach = [];
  final List<String> afterEach = [];
  final List<String> dynamicProperties = [];
  final List<String> initializers = [];
  final List<_Field> autowired = [];
  final List<_Field> testBeans = [];
  final List<_Field> capturedOutput = [];

  /// Tests and @Nested groups, in the order of the class.
  final List<_Member> ordered = [];

  static _Members of(
    TestFile file,
    ClassDeclaration declaration, {
    required bool outer,
  }) {
    final members = _Members._();
    for (final member in declaration.body.members) {
      switch (member) {
        case MethodDeclaration():
          members._method(file, _Method(member), outer: outer);
        case FieldDeclaration(:final fields):
          for (final variable in fields.variables) {
            members._field(
              file,
              _Field(member, fields, variable),
              outer: outer,
            );
          }
        default:
      }
    }
    return members;
  }

  void _method(TestFile file, _Method method, {required bool outer}) {
    final node = method.node;
    final metadata = method.metadata;
    for (final name in _classOnly) {
      if (annotation(metadata, name) != null) {
        throw file.error(
          node,
          '@$name on a method: it belongs to the class (one context per '
          'class); move it there, or write a second class.',
        );
      }
    }
    String staticMethod(String annotationName) {
      if (!node.isStatic) {
        throw file.error(
          node,
          '@$annotationName method ${method.name} must be static: '
          '${annotationName == 'BeforeAll' || annotationName == 'DynamicPropertySource' || annotationName == 'ContextInitializer' ? 'it runs before the class is created' : 'it runs after the tests'}.',
        );
      }
      if (!outer) {
        throw file.error(
          node,
          '@$annotationName in a @Nested class: it belongs to the '
          '@SpringBootTest class.',
        );
      }
      _public(file, node, method.name);
      return method.name;
    }

    String instanceMethod(String annotationName) {
      if (node.isStatic) {
        throw file.error(
          node,
          '@$annotationName method ${method.name} must not be static.',
        );
      }
      _public(file, node, method.name);
      final parameters = node.parameters?.parameters ?? const [];
      if (parameters.isNotEmpty) {
        throw file.error(
          node,
          '@$annotationName method ${method.name} has parameters: test '
          'methods take none (widget tests with a WidgetTester come with '
          'spring_boot_starter_flutter_test).',
        );
      }
      return method.name;
    }

    if (annotation(metadata, 'BeforeAll') != null) {
      beforeAll.add(staticMethod('BeforeAll'));
    }
    if (annotation(metadata, 'AfterAll') != null) {
      afterAll.add(staticMethod('AfterAll'));
    }
    if (annotation(metadata, 'DynamicPropertySource') != null) {
      dynamicProperties.add(staticMethod('DynamicPropertySource'));
    }
    if (annotation(metadata, 'ContextInitializer') != null) {
      initializers.add(staticMethod('ContextInitializer'));
    }
    if (annotation(metadata, 'BeforeEach') != null) {
      beforeEach.add(instanceMethod('BeforeEach'));
    }
    if (annotation(metadata, 'AfterEach') != null) {
      afterEach.add(instanceMethod('AfterEach'));
    }
    if (annotation(metadata, 'Test') != null) {
      instanceMethod('Test');
      ordered.add(method);
    } else {
      for (final name in ['DisplayName', 'Disabled', 'Tag', 'TestOptions']) {
        if (annotation(metadata, name) != null) {
          throw file.error(
            node,
            '@$name on ${method.name}, which is not a @Test method.',
          );
        }
      }
    }
  }

  void _field(TestFile file, _Field field, {required bool outer}) {
    final node = field.node;
    final metadata = field.metadata;
    final injected =
        annotation(metadata, 'Autowired') != null ||
        annotation(metadata, 'Value') != null;
    final captured = annotation(metadata, 'CapturedOutput') != null;
    if (injected || captured) {
      final what = captured
          ? 'CapturedOutput'
          : annotation(metadata, 'Value') != null
          ? 'Value'
          : 'Autowired';
      if (node.isStatic ||
          field.declarations.lateKeyword == null ||
          field.declarations.isFinal ||
          field.declarations.isConst) {
        throw file.error(
          node,
          "@$what field '${field.name}' must be late and not final or "
          "static: @$what() late ${field.type ?? 'Type'} ${field.name};",
        );
      }
      if (field.type == null) {
        throw file.error(
          node,
          "@$what field '${field.name}' needs its type written.",
        );
      }
      _public(file, node, field.name);
      (captured ? capturedOutput : autowired).add(field);
    }
    if (annotation(metadata, 'TestBean') != null) {
      if (!outer) {
        throw file.error(
          node,
          "@TestBean field '${field.name}' in a @Nested class: replaced "
          'beans belong to the @SpringBootTest class (one context).',
        );
      }
      if (node.isStatic || field.variable.initializer == null) {
        throw file.error(
          node,
          "@TestBean field '${field.name}' needs a value: "
          'final ${field.name} = FakeGateway();',
        );
      }
      _public(file, node, field.name);
      testBeans.add(field);
    }
    if (annotation(metadata, 'Nested') != null) {
      if (node.isStatic || field.variable.initializer == null) {
        throw file.error(
          node,
          "@Nested field '${field.name}' needs a value: "
          'final ${field.name} = WithOneBook();',
        );
      }
      _public(file, node, field.name);
      ordered.add(field);
    }
  }

  static void _public(TestFile file, AstNode node, String name) {
    if (name.startsWith('_')) {
      throw file.error(
        node,
        "'$name' is private; the generated test cannot reach it: make it "
        'public.',
      );
    }
  }
}
