import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/properties_index.dart';

/// The properties a test file sets for its own context, as entries at the
/// place they are written.
///
/// With them, a `${key}` that only a test defines is not reported as
/// unknown, and go to definition finds the test's value first. Read from:
///
/// - `@SpringBootTest(properties: {...}, args: ['--key=value'])` and
///   `springBootTest(properties: ..., args: ...)`;
/// - `@TestPropertySource(properties: {...})`;
/// - `@TestEnvironment({...})`, `springBootTest(systemEnvironment: ...)`
///   and `withSystemEnvironment({...})` (environment variables);
/// - `registry.add('key', () => ...)` of `@DynamicPropertySource` and
///   `dynamicProperties:`;
/// - `ApplicationContextRunner().withPropertyValues(['key=value'])`;
/// - the properties of a `@ServiceConnection` container field
///   (`PostgresContainer`: `spring.datasource.url|username|password`,
///   `KeycloakContainer`: the `issuer-uri` keys), placed at the field and
///   marked with the container that provides them.
///
/// Only keys written as string literals count. Files outside a `test/` or
/// `integration_test/` directory give an empty list. The result is cached
/// for each parsed file.
List<PropertyEntry> testProperties(DartFile file) {
  if (!_isTest(file.path)) {
    return const [];
  }
  return _cache[file] ??= _collect(file);
}

final _cache = Expando<List<PropertyEntry>>('testProperties');

bool _isTest(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.contains('/test/') ||
      normalized.contains('/integration_test/');
}

List<PropertyEntry> _collect(DartFile file) {
  final visitor = _Collector(file);
  file.unit.accept(visitor);
  return visitor.entries;
}

final class _Collector extends RecursiveAstVisitor<void> {
  _Collector(this.file);

  final DartFile file;
  final entries = <PropertyEntry>[];

  @override
  void visitAnnotation(Annotation node) {
    switch (annotationName(node)) {
      case 'SpringBootTest':
        _map(namedArgument(node, 'properties'));
        _args(namedArgument(node, 'args'), dashes: true);
      case 'TestPropertySource':
        _map(namedArgument(node, 'properties'));
      case 'TestEnvironment':
        _map(positionalArgument(node), environment: true);
    }
    super.visitAnnotation(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final info = _container(node);
    if (info != null && info.connection) {
      final provided = _provided[info.type];
      if (provided != null) {
        final variable = node.fields.variables.first;
        final providerId = _providerId(variable.initializer) ?? 'keycloak';
        for (final key in provided) {
          _entry(
            variable,
            key.replaceAll('<id>', providerId),
            variable.name.offset,
            variable.name.end,
            provider: '${info.type} ${variable.name.lexeme}',
          );
        }
      }
    }
    super.visitFieldDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final arguments = node.argumentList.arguments;
    Expression? named(String name) {
      for (final argument in arguments) {
        if (argument is NamedArgument && argument.name.lexeme == name) {
          return argument.argumentExpression;
        }
      }
      return null;
    }

    switch (node.methodName.name) {
      case 'springBootTest':
        _map(named('properties'));
        _args(named('args'), dashes: true);
        _map(named('systemEnvironment'), environment: true);
      case 'withPropertyValues':
        if (arguments.firstOrNull?.argumentExpression case final list?) {
          _args(list, dashes: false);
        }
      case 'withSystemEnvironment':
        _map(arguments.firstOrNull?.argumentExpression, environment: true);
      case 'add'
          when arguments.length == 2 &&
              arguments[1].argumentExpression is FunctionExpression:
        if (arguments[0].argumentExpression
            case final SimpleStringLiteral key) {
          _entry(key, key.value, key.contentsOffset, key.contentsEnd);
        }
    }
    super.visitMethodInvocation(node);
  }

  void _map(Expression? expression, {bool environment = false}) {
    if (expression is! SetOrMapLiteral) {
      return;
    }
    for (final element in expression.elements) {
      if (element is MapLiteralEntry && element.key is SimpleStringLiteral) {
        final key = element.key as SimpleStringLiteral;
        _entry(
          key,
          key.value,
          key.contentsOffset,
          key.contentsEnd,
          value: element.value.toSource(),
          environment: environment,
        );
      }
    }
  }

  // `['--key=value', '--flag']` (dashes, as on a command line) or
  // `['key=value', 'key: value', 'flag']` (withPropertyValues: split at the
  // first `=` or `:`, trimmed).
  void _args(Expression? expression, {required bool dashes}) {
    if (expression is! ListLiteral) {
      return;
    }
    for (final element in expression.elements) {
      if (element is! SimpleStringLiteral) {
        continue;
      }
      final text = element.value;
      if (dashes && !text.startsWith('--')) {
        continue;
      }
      final start = dashes ? 2 : 0;
      final separator = dashes
          ? text.indexOf('=')
          : text.indexOf(RegExp('[=:]'));
      final end = separator < 0 ? text.length : separator;
      final raw = text.substring(start, end);
      final key = raw.trim();
      if (key.isEmpty) {
        continue;
      }
      final keyStart = start + raw.indexOf(key);
      _entry(
        element,
        key,
        element.contentsOffset + keyStart,
        element.contentsOffset + keyStart + key.length,
        value: separator < 0 ? '' : text.substring(separator + 1).trim(),
      );
    }
  }

  void _entry(
    AstNode node,
    String key,
    int start,
    int end, {
    String value = '',
    bool environment = false,
    String? provider,
  }) {
    final from = file.lineInfo.getLocation(start);
    final to = file.lineInfo.getLocation(end);
    entries.add(
      PropertyEntry(
        path: file.path,
        key: key,
        value: value,
        line: from.lineNumber - 1,
        keyStart: from.columnNumber - 1,
        keyEnd: from.lineNumber == to.lineNumber
            ? to.columnNumber - 1
            : from.columnNumber - 1 + key.length,
        environment: environment,
        provider: provider,
      ),
    );
  }
}

// What a container module provides as a `@ServiceConnection`.
const _provided = {
  'PostgresContainer': [
    'spring.datasource.url',
    'spring.datasource.username',
    'spring.datasource.password',
  ],
  'KeycloakContainer': [
    'spring.security.oauth2.resourceserver.jwt.issuer-uri',
    'spring.security.oauth2.client.provider.<id>.issuer-uri',
  ],
};

typedef _ContainerField = ({
  bool container,
  bool connection,
  String? type,
});

// The container annotations of a field and its container type: the type
// the initializer creates (`PostgresContainer('...')..withReuse(true)`),
// else the declared type.
_ContainerField? _container(FieldDeclaration node) {
  final names = {
    for (final annotation in node.metadata) annotationName(annotation),
  };
  final container = names.contains('Container');
  final connection = names.contains('ServiceConnection');
  if (!container && !connection) {
    return null;
  }
  final initializer = node.fields.variables.first.initializer;
  return (
    container: container,
    connection: connection,
    type: _createdType(initializer) ?? typeName(node.fields.type),
  );
}

String? _createdType(Expression? expression) {
  var current = expression;
  while (current != null) {
    switch (current) {
      case CascadeExpression(:final target):
        current = target;
      case InstanceCreationExpression(:final constructorName):
        return constructorName.type.name.lexeme;
      case MethodInvocation(:final target?):
        current = target;
      case MethodInvocation(:final methodName):
        final name = methodName.name;
        return name.isNotEmpty && name[0].toUpperCase() == name[0]
            ? name
            : null;
      case ParenthesizedExpression(:final expression):
        current = expression;
      default:
        return null;
    }
  }
  return null;
}

// The literal of `withProviderId('x')` in the chain or cascade of a
// KeycloakContainer initializer.
String? _providerId(Expression? expression) {
  final finder = _ProviderIdFinder();
  expression?.accept(finder);
  return finder.found;
}

final class _ProviderIdFinder extends RecursiveAstVisitor<void> {
  String? found;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'withProviderId') {
      found ??= stringValue(
        node.argumentList.arguments.firstOrNull?.argumentExpression,
      );
    }
    super.visitMethodInvocation(node);
  }
}

/// A mistake in how a test uses containers, at `start` to `end`.
typedef ContainerProblem = ({int start, int end, String message});

/// The container mistakes of a test file, as the generator reports them at
/// build time and `@ServiceConnection` does at run time:
///
/// - a `@Container` field that is not `static`;
/// - `@ServiceConnection` on a `GenericContainer`, which cannot say how to
///   connect to it (`PostgresContainer` and `KeycloakContainer` can).
///
/// Other files give an empty list.
List<ContainerProblem> containerProblems(DartFile file) {
  if (!_isTest(file.path)) {
    return const [];
  }
  final problems = <ContainerProblem>[];
  file.unit.accept(_ContainerChecker(problems));
  return problems;
}

final class _ContainerChecker extends RecursiveAstVisitor<void> {
  _ContainerChecker(this.problems);

  final List<ContainerProblem> problems;

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final info = _container(node);
    if (info != null) {
      final name = node.fields.variables.first.name;
      if (info.container && !node.isStatic) {
        problems.add((
          start: name.offset,
          end: name.end,
          message:
              "@Container field '${name.lexeme}' must be static: the "
              'containers start before the test class is created',
        ));
      }
      if (info.connection && info.type == 'GenericContainer') {
        problems.add((
          start: name.offset,
          end: name.end,
          message:
              "@ServiceConnection on '${name.lexeme}': GenericContainer "
              'cannot say how to connect to it. Use PostgresContainer or '
              'KeycloakContainer, or a container that implements '
              'ServiceConnectionProperties',
        ));
      }
    }
    super.visitFieldDeclaration(node);
  }
}
