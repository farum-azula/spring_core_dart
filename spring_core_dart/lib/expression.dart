/// Spring Expression Language (SpEL) for Dart.
///
/// ```dart
/// final parser = SpelExpressionParser();
/// final context = StandardEvaluationContext({'items': [1, 2, 3]});
/// parser.parseExpression('items.?[#this > 1].size()').getValue(context); // 2
/// ```
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
export 'package:spring_core_dart/src/expression/spel_type.dart';
