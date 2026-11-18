// `@Log` (spring_core_dart): a `log` getter generated as an extension on
// the class, like Lombok's `@Slf4j`.
import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';

/// Recognises the `@Log` annotation of `spring_core_dart` (matched by name
/// and package).
const logChecker = TypeChecker.typeNamedLiterally(
  'Log',
  inPackage: 'spring_core_dart',
);

/// A scanned class annotated `@Log`, for which the module gets a logger
/// getter: [fieldName] on [element], returning the logger named [topic].
///
/// The getter is generated as an extension on the class, so the class can
/// write `log.info(...)` without declaring a logger field.
///
/// ```dart
/// // Input:
/// @Log()
/// class Checkout { ... }
///
/// // Output:
/// extension $CheckoutLog on Checkout {
///   SpringLog get log => const SpringLog('my_app.Checkout');
/// }
/// ```
class LogModel {
  /// The getter [fieldName] of [element], returning the logger [topic].
  LogModel(this.element, this.fieldName, this.topic);

  /// The annotated class; the extension is declared on it.
  final ClassElement element;

  /// The getter's name: `@Log(fieldName: ...)`, `log` by default.
  final String fieldName;

  /// The logger name: `@Log(topic: ...)`, by default `<package>.<Class>`
  /// (the file name instead of the package outside a package).
  final String topic;
}

const _reserved = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

/// Adds a [LogModel] for [element] to `module.loggers` when the class is
/// annotated `@Log`; does nothing otherwise.
///
/// Throws `InvalidGenerationSource` when the getter could not work: a
/// private class (an extension in another file cannot name it), an
/// invalid or reserved getter name, or a member of the class or its
/// supertypes with that name, which would win over the getter.
void scanLog(ClassElement element, ModuleModel module) {
  final annotation = logChecker.firstAnnotationOfExact(element);
  if (annotation == null) {
    return;
  }
  final reader = ConstantReader(annotation);
  final name = element.name ?? '?';
  final fieldName = reader.peek('fieldName')?.stringValue ?? 'log';
  if (element.isPrivate) {
    throw InvalidGenerationSource(
      '@Log on $name: the class is private, so the generated getter (an '
      'extension in the .spring.dart file) cannot name it; make the class '
      'public or declare the logger yourself: '
      "const _log = SpringLog('...');",
      element: element,
    );
  }
  if (!RegExp(r'^[a-zA-Z$][a-zA-Z0-9_$]*$').hasMatch(fieldName) ||
      _reserved.contains(fieldName)) {
    throw InvalidGenerationSource(
      '@Log on $name: fieldName "$fieldName" is not a valid getter name '
      '(a public Dart identifier that is no reserved word).',
      element: element,
    );
  }
  final members = {
    for (final type in [element.thisType, ...element.allSupertypes]) ...[
      for (final method in type.methods) method.name,
      for (final getter in type.getters) getter.name,
      for (final setter in type.setters) setter.name?.replaceAll('=', ''),
    ],
    for (final field in element.fields) field.name,
  };
  if (members.contains(fieldName)) {
    throw InvalidGenerationSource(
      '@Log on $name: $name already has a member "$fieldName", which would '
      'win over the generated getter; choose another name with '
      "@Log(fieldName: '...').",
      element: element,
    );
  }
  final uri = element.library.uri;
  final package = uri.scheme == 'package'
      ? uri.pathSegments.first
      : uri.pathSegments.last.replaceAll('.dart', '');
  module.loggers.add(
    LogModel(
      element,
      fieldName,
      reader.peek('topic')?.stringValue ?? '$package.$name',
    ),
  );
}
