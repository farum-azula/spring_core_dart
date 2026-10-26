import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/properties_index.dart';

/// The properties a test file sets for its own context, as entries at the
/// place they are written:
///
/// - `@SpringBootTest(properties: {...}, args: ['--key=value'])` and
///   `springBootTest(properties: ..., args: ...)`;
/// - `@TestPropertySource(properties: {...})`;
/// - `@TestEnvironment({...})` and `springBootTest(systemEnvironment: ...)`
///   (environment variables);
/// - `registry.add('key', () => ...)` of `@DynamicPropertySource` and
///   `dynamicProperties:`;
/// - `ApplicationContextRunner().withPropertyValues(['key=value'])`.
///
/// Only files under a `test/` directory; empty for others.
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
      ),
    );
  }
}
