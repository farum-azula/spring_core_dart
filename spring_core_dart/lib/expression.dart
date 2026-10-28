/// The Spring Expression Language (SpEL): small expressions written as
/// strings, parsed once and evaluated against objects at run time.
///
/// Applications mostly meet SpEL inside annotations, where the framework
/// parses and evaluates it for them: `@Value('#{...}')` values, cache keys
/// and conditions (`@Cacheable('books', key: '#isbn')`), security rules
/// (`@PreAuthorize("hasRole('ADMIN')")`) and
/// `@ConditionalOnExpression`. Import this library to evaluate
/// expressions yourself (rules or templates read from configuration, for
/// example) or to extend what expressions can see: property accessors,
/// method resolvers, functions and types.
///
/// The syntax is Spring's: literals (`42`, `3.5`, `'text'`, `true`,
/// `null`), inline lists and maps (`{1, 2}`, `{name: 'Ada'}`), properties
/// and methods (`user.name`, `name.toUpperCase()`), indexing
/// (`items[0]`, `map['key']`), safe navigation (`a?.b`), variables and
/// functions (`#n`, `#this`, `#root`, `#twice(2)`), types and constructors
/// (`T(Math).max(1, 2)`, `new int[3]`), bean references (`@mailer`),
/// selection and projection (`list.?[#this > 1]`, `users.![name]`), all
/// operators (arithmetic, `==`, `<`, `and`, `!`, `instanceof`, `matches`,
/// `between`, Elvis `?:`, ternary `? :`), assignment and `++`/`--`.
/// Templates mix text and `#{...}` parts (`'Total: #{price * 2}'`).
///
/// ```dart
/// // Which items of an order pass a rule kept in configuration.
/// final parser = SpelExpressionParser();
/// final context = StandardEvaluationContext({'items': [1, 2, 3]});
/// parser.parseExpression('items.?[#this > 1].size()').getValue(context); // 2
/// ```
///
/// Differences from Java SpEL, all because Dart has no reflection: the
/// properties and methods of your classes are reached through
/// `@Introspected` metadata or accessors you register, `T(...)` and `new`
/// only know registered types, `matches` uses Dart's `RegExp`, and String
/// methods are Dart's (plus the common Java names). There is no compiler
/// mode.
///
/// Spring (Java):
/// ```java
/// ExpressionParser parser = new SpelExpressionParser();
/// parser.parseExpression("items.?[#this > 1].size()").getValue(context);
/// ```
library;

export 'package:spring_core_dart/src/expression/ast.dart'
    show ExpressionState, SpelNode, ValueRef;
export 'package:spring_core_dart/src/expression/bean_expression_resolver.dart';
export 'package:spring_core_dart/src/expression/builtins.dart';
export 'package:spring_core_dart/src/expression/evaluation_context.dart';
export 'package:spring_core_dart/src/expression/expression.dart';
export 'package:spring_core_dart/src/expression/expression_exceptions.dart';
export 'package:spring_core_dart/src/expression/introspection_access.dart';
export 'package:spring_core_dart/src/expression/spel_parser.dart';
export 'package:spring_core_dart/src/expression/spel_parser_configuration.dart';
export 'package:spring_core_dart/src/expression/spel_patterns.dart';
export 'package:spring_core_dart/src/expression/spel_type.dart';
