import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart' show DiagnosticSeverity;
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:spring_core_dart_generator/src/bean_model.dart'
    show exposedBeanTypes, publicSdkLibrary;
import 'package:spring_core_dart_generator/src/package_directory.dart';

/// The builder that turns the `@SpringBootTest` classes of a test file into
/// `package:test` tests.
///
/// A `@SpringBootTest` class describes an integration test: the
/// application to start, the beans to inject into fields, and the `@Test`
/// methods to run against them. `package:test` only runs functions
/// registered with `test` and `group`, and Dart has no reflection to find
/// the annotated methods. So for every `test/<name>_test.dart` with such
/// classes this builder writes `test/spring/<name>.test.spring.dart` with
/// a `runSpringTests()` function that registers them. It uses
/// `springBootTest`, `group`, `test`, `setUp` and `tearDown` from
/// `spring_boot_starter_test`. `springTestBuilder` creates it for
/// `build_runner`.
///
/// The application is the package's only `main` with
/// `@SpringBootApplication` in `bin/` or `lib/`, or the one named by
/// `@SpringBootTest(application: ...)` when there are several. A test class
/// that cannot be generated (no application, an unknown one, a private
/// name in an annotation argument...) throws a [TestClassException] that
/// points at the member. When the test file does not import its generated
/// file, a warning says which import to add.
///
/// The test file is read as syntax, so the builder stays fast. To make
/// every type and constant written in the test class mean the same in the
/// generated code, the generated file imports what the test file imports
/// (with the same prefixes and combinators) and the test file itself. Bean
/// types are not written out: `instance.checkout = app.getBean();` takes
/// its type from the field. A test file with `@TestBean` fields is
/// resolved as well when the syntax does not tell enough:
///
/// - a `@TestBean(name: ...)` field without `type:` whose value is a call
///   (`= FakeGateway()`, `= Fakes.gateway()`): when the value is a
///   constructor call, the fake is registered under the types of its
///   class, written with imports of their own;
/// - a field whose type is inferred, or named without `?` and not
///   declared in the test file as a class, mixin, enum or extension type:
///   it may be a nullable type alias (`typedef MaybeMailer = Mailer?;`),
///   whose value the override checks for `null` like that of a `Mailer?`
///   field.
///
/// While the test file has syntax errors, the existing generated file (in
/// the directory of the test's package, also in a workspace build) is kept
/// so the test's import of it keeps working.
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
  /// Creates the builder; it has no build options. [packageDirectories] finds
  /// the existing generated file on disk ([PackageDirectories.current]
  /// unless given; tests pass directories of their own).
  SpringTestBuilder({PackageDirectories? packageDirectories})
    : _packageDirectories = packageDirectories ?? PackageDirectories.current;

  final PackageDirectories _packageDirectories;

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
    final output = springTestOutput(input);
    // While the file does not parse (being edited under `build_runner
    // watch`) the generated file stays as it is, so the test's import of
    // it keeps working.
    final syntaxErrors = parsed.errors
        .where((e) => e.diagnosticCode.severity == DiagnosticSeverity.ERROR)
        .toList();
    if (syntaxErrors.isNotEmpty) {
      // The output's own package directory: in a workspace build the
      // working directory may be another package's.
      final existing = await _packageDirectories.read(output);
      log.warning(
        '${input.path} has syntax errors; ${output.path} is kept as it is '
        'until it parses again:\n${syntaxErrors.first.message}',
      );
      if (existing != null) {
        await buildStep.writeAsString(output, existing);
      }
      return;
    }
    final file = TestFile(input.path, parsed.unit, parsed.lineInfo, text);
    if (file.testClasses.isEmpty) {
      return;
    }
    final applications = <String>[];
    await for (final asset in buildStep.findAssets(Glob('{bin,lib}/**.dart'))) {
      if (asset.path.endsWith('.spring.dart')) {
        continue;
      }
      final source = await buildStep.readAsString(asset);
      if (source.contains('SpringBootApplication') &&
          _isEntryPoint(asset.path, source)) {
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
    final fakes = TestEmitter.fakesToResolve(file);
    final fields = TestEmitter.nullabilityToResolve(file);
    final resolved = fakes.isEmpty && fields.isEmpty
        ? null
        : await _resolve(buildStep, fakes, fields);
    final source = TestEmitter(
      file: file,
      output: output,
      package: input.package,
      applications: applications,
      fakeTypes: resolved?.fakeTypes ?? const {},
      nullableFields: resolved?.nullable ?? const {},
    ).emit();
    await buildStep.writeAsString(output, source);
  }

  // What only the resolved test file tells, by `Class.field`:
  // - the types of the values of [fakes] (`@TestBean(name: ...)` fields
  //   whose value is a call, as (class, field)): for a constructor call,
  //   its class and that class's supertypes, as the generator registers a
  //   bean of that class. Any other value (a function or static method,
  //   which may return any subclass) and a class that cannot be resolved
  //   are left out;
  // - whether the types of [fields] (`@TestBean` fields whose syntax does
  //   not tell, as (class, field)) are nullable, through type aliases
  //   (`typedef MaybeMailer = Mailer?;`). One that cannot be resolved is
  //   left out.
  // Only such a test file is resolved; the builder reads the others as
  // syntax, which is faster.
  static Future<
    ({Map<String, List<InterfaceType>> fakeTypes, Map<String, bool> nullable})
  >
  _resolve(
    BuildStep buildStep,
    List<(String, String)> fakes,
    List<(String, String)> fields,
  ) async {
    final resolver = buildStep.resolver;
    final LibraryElement library;
    try {
      library = await resolver.libraryFor(
        buildStep.inputId,
        allowSyntaxErrors: true,
      );
    } on Exception catch (e) {
      log.fine('${buildStep.inputId.path} cannot be resolved: $e');
      return (
        fakeTypes: const <String, List<InterfaceType>>{},
        nullable: const <String, bool>{},
      );
    }
    final nullable = <String, bool>{
      for (final (owner, name) in fields)
        if (library.getClass(owner)?.getField(name)?.type case final type?
            when type is! InvalidType)
          '$owner.$name': library.typeSystem.isPotentiallyNullable(type),
    };
    final types = <String, List<InterfaceType>>{};
    for (final (owner, name) in fakes) {
      final field = library.getClass(owner)?.getField(name);
      if (field == null) {
        continue;
      }
      final node = await resolver.astNodeFor(
        field.firstFragment,
        resolve: true,
      );
      if (node case VariableDeclaration(:final initializer)) {
        if (_constructedType(initializer) case final type?) {
          types['$owner.$name'] = exposedBeanTypes(type);
        }
      }
    }
    return (fakeTypes: types, nullable: nullable);
  }

  // The class whose constructor creates [value] (resolved; in parentheses
  // or with a cascade too), or `null` for any other value.
  static InterfaceType? _constructedType(Expression? value) =>
      switch (_unwrapped(value)) {
        InstanceCreationExpression(staticType: final InterfaceType type) ||
        DotShorthandConstructorInvocation(
          staticType: final InterfaceType type,
        ) => type,
        _ => null,
      };
}

// [value] without the parentheses and cascades around it: `FakeGateway()`
// for `(FakeGateway()..reset())`.
Expression? _unwrapped(Expression? value) => switch (value) {
  ParenthesizedExpression(:final expression) => _unwrapped(expression),
  CascadeExpression(:final target) => _unwrapped(target),
  _ => value,
};

// Whether [source] declares a top-level function annotated with
// `@SpringBootApplication` (read as syntax: comments and strings that
// mention it do not count).
bool _isEntryPoint(String path, String source) {
  final unit = parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  ).unit;
  return unit.declarations.any(
    (d) =>
        d is FunctionDeclaration &&
        annotation(d.metadata, 'SpringBootApplication') != null,
  );
}

/// The generated file of the test [input]: the same path under
/// `test/spring/`, with `_test.dart` replaced by `.test.spring.dart`.
///
/// Keeping generated files in their own folder stops `dart test` from
/// taking them for tests. For example `test/orders/basket_test.dart` gives
/// `test/spring/orders/basket.test.spring.dart`.
AssetId springTestOutput(AssetId input) {
  final inTest = input.path.substring('test/'.length);
  return AssetId(
    input.package,
    'test/spring/'
    '${inTest.substring(0, inTest.length - '_test.dart'.length)}'
    '.test.spring.dart',
  );
}

/// A build error in a `@SpringBootTest` class, located at the member that
/// causes it.
///
/// The test builder reads the test file as syntax (it resolves it only
/// for the classes of `@TestBean(name: ...)` fakes), so it cannot use the
/// analyzer's element-based errors. It throws this exception instead, and
/// `build_runner` prints it as `path:line:column: message`.
final class TestClassException implements Exception {
  /// The error [message] at [location] (`path:line:column`).
  TestClassException(this.location, this.message);

  /// Where the error is, as `path:line:column` with 1-based numbers, for
  /// example `test/checkout_test.dart:12:3`.
  final String location;

  /// What is wrong and how to fix it.
  final String message;

  @override
  String toString() => '$location: $message';
}

/// A parsed test file, with the queries the test builder needs: its
/// imports, its `@SpringBootTest` classes, and error locations.
final class TestFile {
  /// Wraps [unit], the parsed syntax of the file at [path].
  ///
  /// [text] is the source as written; it defaults to [unit] printed back,
  /// which may differ in spacing.
  TestFile(this.path, this.unit, this.lineInfo, [String? text])
    : text = text ?? unit.toSource();

  /// The source as written, used to copy annotation arguments verbatim.
  final String text;

  /// Names of superclasses declared in other files that were already
  /// warned about. Their members cannot be seen, and the warning is logged
  /// once per file.
  final Set<String> warnedSuperclasses = {};

  /// The file's path in its package (`test/checkout_test.dart`).
  final String path;

  /// The parsed syntax of the file.
  final CompilationUnit unit;

  /// Turns offsets into the line and column numbers of [error].
  final LineInfo lineInfo;

  /// The classes annotated with `@SpringBootTest`, in file order. The
  /// builder writes nothing when there are none.
  late final List<ClassDeclaration> testClasses = [
    for (final declaration in unit.declarations)
      if (declaration is ClassDeclaration &&
          annotation(declaration.metadata, 'SpringBootTest') != null)
        declaration,
  ];

  /// The class called [name] declared in this file, or `null` when it is
  /// declared elsewhere.
  ClassDeclaration? classNamed(String name) {
    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration &&
          declaration.namePart.typeName.lexeme == name) {
        return declaration;
      }
    }
    return null;
  }

  /// Whether this file declares a class, mixin, enum or extension type
  /// called [name] (a type that is never nullable; not a type alias).
  bool declaresType(String name) => unit.declarations.any(
    (declaration) => switch (declaration) {
      ClassDeclaration(:final namePart) ||
      EnumDeclaration(:final namePart) ||
      ExtensionTypeDeclaration(
        :final namePart,
      ) => namePart.typeName.lexeme == name,
      ClassTypeAlias(name: final token) ||
      MixinDeclaration(name: final token) => token.lexeme == name,
      _ => false,
    },
  );

  /// The import directives, as written; the generated file repeats them.
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

  /// A [TestClassException] with [message], located at the start of
  /// [node].
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

/// The expression of [annotation]'s positional argument [index], or `null`.
Expression? positionalNode(Annotation annotation, int index) {
  final arguments = [
    for (final argument in annotation.arguments?.arguments ?? <Argument>[])
      if (argument is! NamedArgument) argument.argumentExpression,
  ];
  return index < arguments.length ? arguments[index] : null;
}

/// The expression of [annotation]'s named argument [name], or `null`.
Expression? namedNode(Annotation annotation, String name) {
  for (final argument in annotation.arguments?.arguments ?? <Argument>[]) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return argument.argumentExpression;
    }
  }
  return null;
}

// The generated code's own names; `$` keeps them apart from the user's
// names and import prefixes.
const _instance = r'$instance';
const _app = r'$app';
const _logs = r'$logs';

/// Generates the source of `<name>.test.spring.dart` for a [TestFile]: the
/// copied imports and a `runSpringTests()` function that registers one
/// group per `@SpringBootTest` class.
final class TestEmitter {
  /// An emitter for [file], written to [output] in [package], whose
  /// `@SpringBootApplication` entry points are [applications] (paths in
  /// the package).
  ///
  /// [fakeTypes] are the types of the values of `@TestBean(name: ...)`
  /// fields created with a constructor call, by `Class.field`
  /// ([fakesToResolve]): the value's class first, then its supertypes. A
  /// `@TestBean(name: ...)` field without an entry keeps the types of the
  /// bean it replaces.
  ///
  /// [nullableFields] tells, by `Class.field`, whether the type of a
  /// `@TestBean` field of [nullabilityToResolve] is nullable; a field
  /// without an entry is nullable when its declared type ends with `?`.
  TestEmitter({
    required this.file,
    required this.output,
    required this.package,
    required this.applications,
    this.fakeTypes = const {},
    this.nullableFields = const {},
  });

  /// The `@TestBean(name: ...)` fields without `type:` (as (class,
  /// field)) of [file] whose value is a call, which only the resolved file
  /// tells a constructor's from a function's (`FakeGateway()`,
  /// `f.FakeGateway.sandbox()`, `_Fake()..reset()`, `Fakes.gateway()`):
  /// the builder resolves the test file for their [fakeTypes]. Classes
  /// that cannot be generated are skipped here; [emit] reports them.
  static List<(String, String)> fakesToResolve(TestFile file) => [
    for (final testClass in file.testClasses)
      ...?_testBeans(file, testClass)
          ?.where((f) => f.mayCreateFake)
          .map(
            (f) => (f.owner.namePart.typeName.lexeme, f.name),
          ),
  ];

  /// The `@TestBean` fields (as (class, field)) of [file] whose
  /// nullability their syntax does not tell: an inferred type, or a named
  /// type without `?` that is not a class, mixin, enum or extension type of
  /// [file], as it may be a nullable type alias (`typedef MaybeMailer =
  /// Mailer?;`, also from another library). The builder resolves the test
  /// file for their [nullableFields]. Classes that cannot be generated are
  /// skipped here; [emit] reports them.
  static List<(String, String)> nullabilityToResolve(TestFile file) => [
    for (final testClass in file.testClasses)
      ...?_testBeans(file, testClass)
          ?.where(
            (f) => switch (f.declarations.type) {
              null => true,
              NamedType(question: null, importPrefix: null, :final name) =>
                !file.declaresType(name.lexeme),
              NamedType(question: null) => true,
              _ => false,
            },
          )
          .map((f) => (f.owner.namePart.typeName.lexeme, f.name)),
  ];

  static List<_Field>? _testBeans(TestFile file, ClassDeclaration testClass) {
    try {
      return _Members.of(file, testClass, outer: true).testBeans;
    } on TestClassException {
      return null;
    }
  }

  /// The types of the fakes of [fakesToResolve] created with a
  /// constructor of a class that could be resolved, by `Class.field`.
  final Map<String, List<InterfaceType>> fakeTypes;

  /// Whether the types of the fields of [nullabilityToResolve] that could
  /// be resolved are nullable, by `Class.field`.
  final Map<String, bool> nullableFields;

  // The libraries of [fakeTypes] written here → their import prefix.
  final Map<String, String> _typeImports = {};

  /// The test file whose classes are generated.
  final TestFile file;

  /// The generated file; relative imports are re-pointed from its folder.
  final AssetId output;

  /// The package of the test, for `package:` imports of an application in
  /// `lib/`.
  final String package;

  /// The paths of the package's `@SpringBootApplication` entry points,
  /// sorted. A test class without `application:` needs exactly one.
  final List<String> applications;

  // Entry point → its import prefix in the generated file.
  final Map<String, String> _applicationPrefixes = {};

  final StringBuffer _body = StringBuffer();

  // The generated function that types an override by its value: written
  // in the `List<BeanOverride<Object>>` of `overrides:`,
  // `BeanOverride.named(field, ...)` (a `@TestBean(name: ...)` field) or
  // `BeanOverride(field)` (a field whose type is a nullable type alias,
  // which cannot be written without its `?`) alone gets `Object` as its
  // type argument (downward inference), and the override would not
  // register the fake under the field's type. Called around it, the type
  // argument is inferred from the value: the field's type, without `?`.
  static const _named = r'_$named';

  // Whether the generated file needs [_named].
  bool _usesNamed = false;

  /// Generates every test class of [file] and returns the formatted
  /// source of the generated library.
  ///
  /// Throws a [TestClassException] for a test class that cannot be
  /// generated.
  String emit() {
    file.testClasses.forEach(_testClass);
    final out = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln(
        '// Generated by spring_core_dart_generator from the @SpringBootTest '
        'classes of ${p.url.basename(file.path)}.',
      )
      ..writeln()
      // The test file's imports are copied whole: some are unused here.
      ..writeln(
        '// ignore_for_file: type=lint, unused_import, unused_shown_name, '
        'duplicate_import',
      )
      ..writeln();
    // The test file's imports; relative ones (and those of conditional
    // imports) re-pointed from test/spring/.
    for (final directive in file.imports) {
      if (file.resolve(directive) == output.path) {
        continue;
      }
      out.writeln(_repointed(directive));
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
    for (final MapEntry(key: uri, value: prefix) in _typeImports.entries) {
      out.writeln("import '$uri' as $prefix;");
      if (uri == 'dart:core') {
        // A prefixed import of dart:core removes the implicit one, which
        // the generated code needs (StateError, dynamic).
        out.writeln("import 'dart:core';");
      }
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
    if (_usesNamed) {
      out
        ..writeln()
        ..writeln(
          '// The override of a @TestBean field, typed by the field: in the '
          'overrides',
        )
        ..writeln(
          '// list, BeanOverride.named (or BeanOverride) alone infers Object.',
        )
        ..write('_sbt.BeanOverride<Object> $_named<T extends Object>')
        ..writeln('(_sbt.BeanOverride<T> override) => override;');
    }
    return DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)
        .format(out.toString());
  }

  String _repointed(ImportDirective directive) {
    final source = directive.toSource();
    final replacements = <(int, int, String)>[];
    void repoint(StringLiteral uri) {
      final value = uri.stringValue;
      if (value == null || Uri.parse(value).hasScheme) {
        return;
      }
      final target = p.url.normalize(
        p.url.join(p.url.dirname(file.path), value),
      );
      replacements.add((
        uri.offset - directive.offset,
        uri.end - directive.offset,
        "'${_relative(target)}'",
      ));
    }

    repoint(directive.uri);
    for (final configuration in directive.configurations) {
      repoint(configuration.uri);
    }
    var result = source;
    for (final (start, end, text) in replacements.reversed) {
      result = result.replaceRange(start, end, text);
    }
    return result;
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

  /// The source of [expression], an annotation argument, rewritten so the
  /// generated library can use it.
  ///
  /// In the test file, an annotation on a member may name static members of
  /// its class without the class name, since Dart resolves them in that
  /// class's scope. The generated library is outside the class, so those
  /// names (from [scope]) are qualified with their class. A private name
  /// cannot be reached from another library and throws a
  /// [TestClassException].
  String? _code(Expression? expression, {_Scope? scope}) {
    if (expression == null) {
      return null;
    }
    final names = _Identifiers()..visit(expression);
    final replacements = <(int, int, String)>[];
    for (final identifier in names.found) {
      final owner = scope?.statics[identifier.name];
      if (owner != null) {
        if (owner.startsWith('_') || identifier.name.startsWith('_')) {
          throw file.error(
            identifier,
            "'${identifier.name}' is private; the generated test cannot "
            'reach it: make it public.',
          );
        }
        replacements.add((
          identifier.offset - expression.offset,
          identifier.end - expression.offset,
          '$owner.${identifier.name}',
        ));
      } else if (identifier.name.startsWith('_')) {
        throw file.error(
          identifier,
          "'${identifier.name}' is private to the test file; the generated "
          'test cannot reach it: make it public.',
        );
      }
    }
    var source = expression.toSource();
    if (replacements.isEmpty) {
      return source;
    }
    // toSource() may differ from the text in spacing: use the text.
    source = file.text.substring(expression.offset, expression.end);
    for (final (start, end, text) in replacements.reversed) {
      source = source.replaceRange(start, end, text);
    }
    return source;
  }

  String _application(ClassDeclaration testClass, Annotation springBootTest) {
    final given = named(springBootTest, 'application');
    final String entry;
    if (given != null) {
      final path = _stringValue(given);
      if (path == null || !applications.contains(path)) {
        final found = applications.isEmpty
            ? 'none found'
            : applications.join(', ');
        throw file.error(
          springBootTest,
          '$given is not an entry point with @SpringBootApplication of this '
          'package ($found).',
        );
      }
      entry = path;
    } else if (applications.length == 1) {
      entry = applications.single;
    } else if (applications.isEmpty) {
      throw file.error(
        springBootTest,
        'No application in this package: @SpringBootTest needs a '
        '@SpringBootApplication entry point in bin/ or lib/.',
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
    _checkCreatable(testClass, testClass);
    final members = _Members.of(file, testClass, outer: true);

    _body.writeln('_sbt.group(${_literal(name)}, () {');
    for (final method in members.beforeAll) {
      _body.writeln('_sbt.setUpAll(() => $method());');
    }
    // Declared before springBootTest: tearDownAll runs in reverse order, so
    // these run after the context is closed.
    for (final method in members.afterAll) {
      _body.writeln('_sbt.tearDownAll(() => $method());');
    }
    _body.writeln('final $_instance = $name();');
    if (_capturesOutput(testClass, members)) {
      _body.writeln('final $_logs = _sbt.captureLogs();');
    }
    final application = _application(testClass, springBootTest);
    _body.writeln('final $_app = _sbt.springBootTest($application,');
    _startOptions(testClass, springBootTest, members);
    _body.writeln(');');
    _classBody(testClass, members, _instance, testClass.metadata);
    _body.writeln('}${_groupOptions(testClass.metadata)});');
  }

  // Whether the class or one of its @Nested classes has a @CapturedOutput
  // field.
  bool _capturesOutput(ClassDeclaration declaration, _Members members) {
    if (members.capturedOutput.isNotEmpty) {
      return true;
    }
    for (final member in members.ordered) {
      if (member is _Field) {
        final nested = _nestedClass(member);
        if (_capturesOutput(nested, _Members.of(file, nested, outer: false))) {
          return true;
        }
      }
    }
    return false;
  }

  void _startOptions(
    ClassDeclaration testClass,
    Annotation springBootTest,
    _Members members,
  ) {
    final metadata = testClass.metadata;
    if (_code(namedNode(springBootTest, 'args')) case final args?) {
      _body.writeln('args: $args,');
    }
    final propertySource = annotation(metadata, 'TestPropertySource');
    final properties = [
      ?_code(namedNode(springBootTest, 'properties')),
      if (propertySource != null)
        ?_code(namedNode(propertySource, 'properties')),
    ];
    if (properties.length == 1) {
      _body.writeln('properties: ${properties.single},');
    } else if (properties.length == 2) {
      _body.writeln('properties: {...${properties[0]}, ...${properties[1]}},');
    }
    if (propertySource != null) {
      if (_code(namedNode(propertySource, 'locations')) case final locations?) {
        _body.writeln('propertyFiles: $locations,');
      }
    }
    if (_code(namedNode(springBootTest, 'resourceDirectories'))
        case final directories?) {
      _body.writeln('resourceDirectories: $directories,');
    }
    if (_code(namedNode(springBootTest, 'webEnvironment'))
        case final environment?) {
      _body.writeln('webEnvironment: $environment,');
    }
    if (annotation(metadata, 'ActiveProfiles') case final profiles?) {
      _body.writeln('profiles: ${_code(positionalNode(profiles, 0))},');
    }
    if (annotation(metadata, 'TestEnvironment') case final environment?) {
      _body.writeln(
        'systemEnvironment: ${_code(positionalNode(environment, 0))},',
      );
    }
    switch (members.dynamicProperties) {
      case [final method]:
        _body.writeln('dynamicProperties: $method,');
      case [_, _, ...] && final methods:
        _body.writeln(
          'dynamicProperties: (registry) {'
          '${methods.map((m) => '$m(registry);').join()}},',
        );
    }
    if (members.initializers.isNotEmpty) {
      final initializers = members.initializers
          .map((m) => '_sbt.ApplicationContextInitializer.of($m)')
          .join(', ');
      _body.writeln('initializers: [$initializers],');
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
    final owner = bean.owner.namePart.typeName.lexeme;
    // A nullable field: the override takes the value itself (a null one
    // fails the test file with this message). Resolved when the syntax
    // does not tell (a nullable type alias).
    final nullable =
        nullableFields['$owner.${bean.name}'] ??
        bean.type?.endsWith('?') ??
        false;
    final message = _literal(
      '@TestBean field $owner.${bean.name} is null: it needs a value',
    );
    final value = nullable
        ? '($_instance.${bean.name} ?? (throw StateError($message)))'
        : '$_instance.${bean.name}';
    final scope = _Scope.of(file, bean.owner);
    final name = _code(namedNode(testBean, 'name'), scope: scope);
    final type = _code(namedNode(testBean, 'type'), scope: scope);
    if (type != null) {
      final named = name == null ? '' : ', name: $name';
      return '_sbt.BeanOverride<$type>($value$named)';
    }
    final declared = bean.type;
    if (name != null) {
      // A value created with a constructor (`= FakeGateway()`, whatever
      // the field's declared type): the fake is registered under the types
      // of its class, read from the resolved test file, not under the
      // replaced bean's, which it may not implement. Otherwise (a function
      // or static method call, a variable, a literal, a class that cannot
      // be resolved or a type that cannot be written here) the replaced
      // bean's types are kept. Either way BeanOverride.named adds its type
      // argument, the field's type: [_named] keeps the overrides list from
      // inferring Object for it.
      final types = bean.mayCreateFake
          ? _typeList(fakeTypes['$owner.${bean.name}'])
          : null;
      _usesNamed = true;
      if (types == null) {
        return '$_named(_sbt.BeanOverride.named($value, name: $name))';
      }
      return '$_named(_sbt.BeanOverride.named($value, name: $name, '
          'types: [$types]))';
    }
    if (declared == null) {
      throw file.error(
        bean.node,
        "@TestBean field '${bean.name}' needs the type of the bean it "
        'replaces: write it (final PaymentGateway ${bean.name} = ...), or '
        '@TestBean(type: PaymentGateway), or @TestBean(name: ...).',
      );
    }
    if (declared.endsWith('?')) {
      return '_sbt.BeanOverride<${declared.substring(0, declared.length - 1)}>'
          '($value)';
    }
    if (nullable) {
      // A nullable type alias (`MaybeMailer` for `Mailer?`): its
      // non-nullable form has no name to write, so the type argument is
      // inferred from the value, which is not null.
      _usesNamed = true;
      return '$_named(_sbt.BeanOverride($value))';
    }
    return '_sbt.BeanOverride<$declared>($value)';
  }

  // [types] (a fake's class first, then its supertypes) as the elements
  // of a `types:` list. A type whose class or a type argument is private
  // is left out: only its own library can look a bean up by it (the
  // fake's own class is added by its runtime type anyway, and a generic
  // one by its raw form, `Repo<dynamic>` for `Repo<_Draft>`). `null` when
  // [types] is `null` or one of the others cannot be written in the
  // generated file, which would lose it.
  String? _typeList(List<InterfaceType>? types) {
    if (types == null) {
      return null;
    }
    final written = <String>[];
    for (final type in types) {
      if (_hasPrivateClass(type)) {
        continue;
      }
      final source = _typeSource(type);
      if (source == null) {
        return null;
      }
      written.add(source);
    }
    return written.isEmpty ? null : written.join(', ');
  }

  // Whether [type] or one of its type arguments (at any depth) is a
  // private class.
  static bool _hasPrivateClass(DartType type) =>
      type is InterfaceType &&
      (type.element.isPrivate || type.typeArguments.any(_hasPrivateClass));

  // [type] as source in the generated file, its libraries imported with
  // prefixes of their own; `null` for a type that cannot be written (a
  // function, record or private type, a file of another package outside
  // lib/, or a class of an internal SDK library that no public one
  // exports).
  String? _typeSource(DartType type) {
    final nullable = type.nullabilitySuffix == NullabilitySuffix.question
        ? '?'
        : '';
    switch (type) {
      case DynamicType():
        return 'dynamic';
      case VoidType():
        return 'void';
      case NeverType():
        return 'Never$nullable';
      case InterfaceType(:final element) when element.isPublic:
        final prefix = _typeImport(element);
        final arguments = [
          for (final argument in type.typeArguments) _typeSource(argument),
        ];
        if (prefix == null || arguments.contains(null)) {
          return null;
        }
        final written = arguments.isEmpty ? '' : '<${arguments.join(', ')}>';
        return '$prefix.${element.name}$written$nullable';
      default:
        return null;
    }
  }

  // The prefix of the import of the library of [element] in the generated
  // file. A class of an internal SDK library is imported through the
  // public one that exports it (`HttpClient` of `dart:_http` through
  // `dart:io`), as the generator writes it.
  String? _typeImport(InterfaceElement element) {
    final uri = element.library.uri;
    final String import;
    switch (uri.scheme) {
      case 'dart' when uri.path.startsWith('_'):
        final public = publicSdkLibrary(
          element.name!,
          element,
          declaration: element,
        );
        if (public == null) {
          return null;
        }
        import = '$public';
      case 'dart':
      case 'package':
        import = '$uri';
      // A file of this package outside lib/ (the test file itself).
      case 'asset' when uri.pathSegments.firstOrNull == package:
        import = _relative(uri.pathSegments.skip(1).join('/'));
      default:
        return null;
    }
    return _typeImports[import] ??= _freshPrefix('_t${_typeImports.length}');
  }

  // [prefix], or one with more underscores when the test file already
  // imports with it.
  String _freshPrefix(String prefix) {
    final used = {
      for (final directive in file.imports) ?directive.prefix?.name,
    };
    var candidate = prefix;
    while (used.contains(candidate)) {
      candidate = '_$candidate';
    }
    return candidate;
  }

  // Injection, lifecycle and tests of a class (the test class or a
  // @Nested one) whose instance is [instance]; [metadata]: the
  // annotations that apply to the whole group (the class's, and for a
  // @Nested class also its field's).
  void _classBody(
    ClassDeclaration declaration,
    _Members members,
    String instance,
    List<Annotation> metadata,
  ) {
    final inject = <String>[
      for (final field in members.autowired)
        '$instance.${field.name} = ${_injection(field)};',
      for (final field in members.capturedOutput)
        '$instance.${field.name} = $_logs;',
    ];
    if (inject.isNotEmpty) {
      // Before every test: after a @DirtiesContext restart the beans are
      // new.
      _body.writeln('_sbt.setUp(() {${inject.join()}});');
    }
    if (annotation(metadata, 'DirtiesContext') != null) {
      // On a class or @Nested field: a new context after each test, as
      // Spring's classMode AFTER_EACH_TEST_METHOD. Spring's default for a
      // class, AFTER_CLASS, would change nothing: the class's context is
      // closed after its tests anyway (no context cache across classes).
      _body.writeln('_sbt.setUp($_app.markDirty);');
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
    final scope = _Scope.of(file, field.owner);
    if (annotation(field.metadata, 'LocalServerPort') != null) {
      return '$_app.localServerPort';
    }
    if (annotation(field.metadata, 'Value') case final value?) {
      final expression = _code(positionalNode(value, 0), scope: scope);
      return nullable
          ? '$_app.optionalValue($expression)'
          : '$_app.value($expression)';
    }
    final qualifier = switch (annotation(field.metadata, 'Qualifier')) {
      final q? => 'qualifier: ${_code(positionalNode(q, 0), scope: scope)}',
      null => '',
    };
    final arguments = field.typeArguments;
    switch (field.simpleTypeName) {
      case 'SpringBootTestContext':
        return _app;
      case 'MockMvc':
        return '$_app.mockMvc';
      case 'ApplicationContext' || 'ConfigurableApplicationContext':
        return '$_app.context';
      case 'Environment' || 'ConfigurableEnvironment':
        return '$_app.environment';
      case 'List' || 'Iterable':
        return '$_app.getBeans($qualifier)';
      case 'Set' when arguments.length == 1:
        return '$_app.getBeans<${arguments.single}>($qualifier).toSet()';
      case 'Map' when arguments.length == 2:
        return '$_app.context.getBeansOfType<${arguments.last}>()';
      case 'ObjectProvider' || 'ObjectFactory' || 'Provider':
        return '$_app.context.getBeanProvider($qualifier)';
    }
    return nullable
        ? '$_app.findBean($qualifier)'
        : '$_app.getBean($qualifier)';
  }

  void _test(_Method method, String instance) {
    final metadata = method.metadata;
    final scope = _Scope.of(file, method.owner);
    final display = annotation(metadata, 'DisplayName');
    final name =
        (display == null
            ? null
            : _code(positionalNode(display, 0), scope: scope)) ??
        _code(positionalNode(annotation(metadata, 'Test')!, 0), scope: scope) ??
        _literal(_words(method.name));
    final dirties = annotation(metadata, 'DirtiesContext') != null;
    final call = '$instance.${method.name}()';
    final body = dirties
        ? '() {$_app.markDirty(); return $call;}'
        : '() => $call';
    _body.writeln(
      '_sbt.test($name, $body${_groupOptions(metadata, scope: scope)});',
    );
  }

  ClassDeclaration _nestedClass(_Field field) {
    final type = field.initializerClass;
    final declaration = type == null ? null : file.classNamed(type);
    if (declaration == null) {
      throw file.error(
        field.node,
        "@Nested field '${field.name}' must be created with a class of this "
        'file: final ${field.name} = WithOneBook();',
      );
    }
    return declaration;
  }

  void _nested(_Field field, String instance) {
    final nested = annotation(field.metadata, 'Nested')!;
    final declaration = _nestedClass(field);
    _checkCreatable(declaration, field.node);
    final members = _Members.of(file, declaration, outer: false);
    final scope = _Scope.of(file, field.owner);
    final name =
        _code(positionalNode(nested, 0), scope: scope) ??
        _literal(_words(field.name));
    final inner = '$instance.${field.name}';
    // The field's @Disabled, @Tag, @TestOptions and @DirtiesContext apply
    // to the group as the class's do.
    final metadata = [...declaration.metadata, ...field.metadata];
    _body.writeln('_sbt.group($name, () {');
    _classBody(declaration, members, inner, metadata);
    final options = _groupOptions(
      declaration.metadata,
      also: field.metadata,
      scope: scope,
    );
    _body.writeln('}$options);');
  }

  // `, skip: ..., tags: [...], timeout: ...` from @Disabled, @Tag and
  // @TestOptions of [metadata] (and of [also], which wins).
  String _groupOptions(
    List<Annotation> metadata, {
    List<Annotation> also = const [],
    _Scope? scope,
  }) {
    final options = <String>[];
    final all = [...metadata, ...also];
    final disabled =
        annotation(also, 'Disabled') ?? annotation(metadata, 'Disabled');
    if (disabled != null) {
      final inScope = identical(disabled, annotation(also, 'Disabled'))
          ? scope
          : (also.isEmpty ? scope : null);
      options.add(
        'skip: ${_code(positionalNode(disabled, 0), scope: inScope) ?? 'true'}',
      );
    }
    final tags = [
      for (final tag in annotations(all, 'Tag'))
        ?_code(
          positionalNode(tag, 0),
          scope: also.contains(tag) || also.isEmpty ? scope : null,
        ),
    ];
    if (tags.isNotEmpty) {
      options.add('tags: [${tags.join(', ')}]');
    }
    final testOptions =
        annotation(also, 'TestOptions') ?? annotation(metadata, 'TestOptions');
    if (testOptions != null) {
      final inScope = also.contains(testOptions) || also.isEmpty ? scope : null;
      for (final option in ['timeout', 'retry', 'testOn', 'onPlatform']) {
        if (_code(namedNode(testOptions, option), scope: inScope)
            case final value?) {
          options.add('$option: $value');
        }
      }
    }
    return options.isEmpty ? '' : ', ${options.join(', ')}';
  }

  // The generated code creates the class with `Name()`: it must be public
  // and have an unnamed constructor without required parameters.
  void _checkCreatable(ClassDeclaration declaration, AstNode at) {
    final name = declaration.namePart.typeName.lexeme;
    if (name.startsWith('_')) {
      throw file.error(
        at,
        "'$name' is private; the generated test cannot create it: make it "
        'public.',
      );
    }
    if (declaration.abstractKeyword != null) {
      throw file.error(
        at,
        "'$name' is abstract; the generated test cannot create it.",
      );
    }
    final constructors = [
      for (final member in declaration.body.members)
        if (member is ConstructorDeclaration) member,
    ];
    final unnamed = constructors.where((c) => c.name == null).firstOrNull;
    if (constructors.isNotEmpty && unnamed == null) {
      throw file.error(
        constructors.first,
        "'$name' has no unnamed constructor: the generated test creates "
        'it with $name().',
      );
    }
    if (unnamed != null &&
        unnamed.parameters.parameters.any((p) => p.isRequired)) {
      throw file.error(
        unnamed,
        "'$name' needs a constructor without required parameters: the "
        'generated test creates it.',
      );
    }
  }
}

/// A single-quoted Dart string literal of [value], with backslashes,
/// quotes, `$` and newlines escaped.
String _literal(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

/// The description of a test or `@Nested` group without `@DisplayName` or
/// a name argument, made from the method or field name: words split at
/// case changes and underscores, in lower case.
///
/// `paysThroughTheFake` → `pays through the fake`, `addsABook` → `adds a
/// book`, `readsURLService` → `reads url service`, `checkout_pays` →
/// `checkout pays`.
String _words(String name) => name
    .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .replaceAllMapped(RegExp('([A-Z])([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}')
    .replaceAll('_', ' ')
    .replaceAll(RegExp(' +'), ' ')
    .toLowerCase()
    .trim();

String? _stringValue(String source) {
  final match = RegExp(r'''^r?(['"])(.*)\1$''').firstMatch(source);
  return match?[2];
}

// The plain names in an expression that a scope resolves (not the
// property of `a.b`, a named argument's label or a type).
final class _Identifiers extends RecursiveAstVisitor<void> {
  final found = <SimpleIdentifier>[];

  void visit(Expression expression) => expression.accept(this);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    final qualified = switch (parent) {
      PrefixedIdentifier(:final identifier) => identical(identifier, node),
      PropertyAccess(:final propertyName) => identical(propertyName, node),
      MethodInvocation(:final methodName, :final target) =>
        identical(methodName, node) && target != null,
      Label() => true,
      _ => false,
    };
    if (!qualified) {
      found.add(node);
    }
  }
}

// The static members visible by their plain name inside a class of the
// file: its own and those of its superclasses declared in the file, with
// the class that declares each (Dart does not inherit statics, so the
// generated code names the declaring class).
final class _Scope {
  _Scope._(this.statics);

  final Map<String, String> statics;

  static _Scope of(TestFile file, ClassDeclaration owner) {
    final statics = <String, String>{};
    for (final declaration in _chain(file, owner)) {
      final name = declaration.namePart.typeName.lexeme;
      for (final member in declaration.body.members) {
        switch (member) {
          case MethodDeclaration(isStatic: true, name: final method):
            statics[method.lexeme] = name;
          case FieldDeclaration(isStatic: true, :final fields):
            for (final variable in fields.variables) {
              statics[variable.name.lexeme] = name;
            }
          default:
        }
      }
    }
    return _Scope._(statics);
  }
}

// [declaration] and its superclasses declared in [file], the farthest
// first; a superclass of another file is reported once (its members are
// not seen: the file is read as syntax).
List<ClassDeclaration> _chain(TestFile file, ClassDeclaration declaration) {
  final chain = <ClassDeclaration>[declaration];
  var current = declaration;
  while (true) {
    final superclass = current.extendsClause?.superclass.name.lexeme;
    if (superclass == null || superclass == 'Object') {
      break;
    }
    final next = file.classNamed(superclass);
    if (next == null || chain.contains(next)) {
      if (next == null && file.warnedSuperclasses.add(superclass)) {
        log.warning(
          '${file.path}: ${current.namePart.typeName.lexeme} extends '
          '$superclass from another file; its @Test, @Autowired and other '
          'annotated members are not seen. Declare it in the test file.',
        );
      }
      break;
    }
    chain.insert(0, next);
    current = next;
  }
  return chain;
}

sealed class _Member {
  ClassDeclaration get owner;
  List<Annotation> get metadata;
}

final class _Method extends _Member {
  _Method(this.node, this.owner);

  final MethodDeclaration node;

  @override
  final ClassDeclaration owner;

  String get name => node.name.lexeme;

  @override
  List<Annotation> get metadata => node.metadata;
}

final class _Field extends _Member {
  _Field(this.node, this.declarations, this.variable, this.owner);

  final FieldDeclaration node;
  final VariableDeclarationList declarations;
  final VariableDeclaration variable;

  @override
  final ClassDeclaration owner;

  String get name => variable.name.lexeme;

  @override
  List<Annotation> get metadata => node.metadata;

  /// The field's declared type, as written; `null` when it is inferred.
  String? get type => declarations.type?.toSource();

  /// The name of the declared type without prefix, `?` or type
  /// arguments: `Checkout` for `Checkout`, `p.Checkout?` and
  /// `Checkout<int>`; `null` for an inferred, function or record type.
  String? get simpleTypeName => switch (declarations.type) {
    final NamedType named => named.name.lexeme,
    _ => null,
  };

  /// Whether this is a `@TestBean(name: ...)` field without `type:` whose
  /// value is a call, parentheses and cascades aside: `FakeGateway()`,
  /// `f.FakeGateway.sandbox()`, `_Fake()..reset()`, but also
  /// `Fakes.gateway()`. Only the resolved test file tells a constructor
  /// call (the fake gets the types of its class) from a function's; a
  /// literal, a variable or a function expression is neither.
  bool get mayCreateFake {
    final testBean = annotation(metadata, 'TestBean');
    if (testBean == null ||
        namedNode(testBean, 'name') == null ||
        namedNode(testBean, 'type') != null) {
      return false;
    }
    return switch (_unwrapped(variable.initializer)) {
      InstanceCreationExpression() || InvocationExpression() => true,
      _ => false,
    };
  }

  /// The type arguments as written: `[String, PaymentGateway]` for
  /// `Map<String, PaymentGateway>`.
  List<String> get typeArguments => switch (declarations.type) {
    NamedType(:final typeArguments?) => [
      for (final argument in typeArguments.arguments) argument.toSource(),
    ],
    _ => const [],
  };

  /// The class the field's initializer creates, as written: `WithOneBook`
  /// for `= WithOneBook()`; `null` for any other initializer.
  String? get initializerClass => switch (variable.initializer) {
    InstanceCreationExpression(:final constructorName) =>
      constructorName.type.name.lexeme,
    MethodInvocation(target: null, :final methodName) => methodName.name,
    _ => null,
  };
}

// The annotated members of a test class (or a @Nested class) and of its
// superclasses in the file, checked. Static methods are qualified with the
// class that declares them (`Base.start`).
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

  /// The tests and `@Nested` groups, in declaration order with the
  /// superclass's first; they are registered in this order.
  final List<_Member> ordered = [];

  static _Members of(
    TestFile file,
    ClassDeclaration declaration, {
    required bool outer,
  }) {
    final members = _Members._();
    for (final owner in _chain(file, declaration)) {
      for (final member in owner.body.members) {
        switch (member) {
          case MethodDeclaration():
            members._method(file, _Method(member, owner), outer: outer);
          case FieldDeclaration(:final fields):
            for (final variable in fields.variables) {
              members._field(
                file,
                _Field(member, fields, variable, owner),
                outer: outer,
              );
            }
          default:
        }
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
    final owner = method.owner.namePart.typeName.lexeme;
    String staticMethod(String annotationName) {
      if (!node.isStatic) {
        final runs = annotationName == 'AfterAll'
            ? 'it runs after the tests'
            : 'it runs before the class is created';
        throw file.error(
          node,
          '@$annotationName method ${method.name} must be static: $runs.',
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
      _public(file, node, owner);
      return '$owner.${method.name}';
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
        annotation(metadata, 'Value') != null ||
        annotation(metadata, 'LocalServerPort') != null;
    final captured = annotation(metadata, 'CapturedOutput') != null;
    if (injected || captured) {
      final what = captured
          ? 'CapturedOutput'
          : annotation(metadata, 'Value') != null
          ? 'Value'
          : annotation(metadata, 'LocalServerPort') != null
          ? 'LocalServerPort'
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
    } else if (annotation(metadata, 'Nested') == null) {
      for (final name in ['Disabled', 'Tag', 'TestOptions', 'DirtiesContext']) {
        if (annotation(metadata, name) != null) {
          throw file.error(
            node,
            '@$name on the field ${field.name}, which is not @Nested.',
          );
        }
      }
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
