part of 'bean_scanner.dart';

// The pointcut of an advisor bean, read from its `@Bean` method's body when
// the build can tell what it matches:
//
//     @Bean()
//     PointcutAdvisor metrics(Metrics m) => DefaultPointcutAdvisor(
//       ExpressionPointcut('within(*Controller)'), CountingInterceptor(m));
//
// gives the expression `within(*Controller)`, which proxy pruning matches
// like an aspect's. `AnnotationMatchingPointcut<A>()` and a pointcut class
// declaring `static const annotationTypes` give their annotations. Anything
// else (an expression from a variable, a hand-written pointcut, an advisor
// class of the application) is unknown: nothing is pruned then.

const TypeChecker _defaultPointcutAdvisorType = TypeChecker.fromUrl(
  'package:spring_core_dart/src/aop/advisor.dart#DefaultPointcutAdvisor',
);
const TypeChecker _expressionPointcutType = TypeChecker.fromUrl(
  'package:spring_core_dart/src/aop/aop_pointcut.dart#ExpressionPointcut',
);
const TypeChecker _annotationMatchingPointcutType = TypeChecker.fromUrl(
  'package:spring_core_dart/src/aop/aop_pointcut.dart'
  '#AnnotationMatchingPointcut',
);

extension _AdvisorPointcuts on BeanScanner {
  // What the advisor returned by the `@Bean` [method] matches, or `null`
  // when the build cannot tell (or the method returns no advisor).
  AdvisorPointcut? _advisorPointcutOf(MethodElement method) {
    if (!_advisor.isAssignableFromType(method.returnType)) {
      return null;
    }
    final declaration =
        _beanMethodDeclarations[_BeanTypeInference.methodKey(method)];
    final returned = switch (declaration?.body) {
      ExpressionFunctionBody(:final expression) => expression,
      BlockFunctionBody(:final block)
          when block.statements.length == 1 &&
              block.statements.single is ReturnStatement =>
        (block.statements.single as ReturnStatement).expression,
      _ => null,
    };
    if (returned is! InstanceCreationExpression ||
        !_defaultPointcutAdvisorType.isExactlyType(returned.staticType!)) {
      return null;
    }
    final arguments = returned.argumentList.arguments;
    if (arguments.isEmpty) {
      return null;
    }
    return _pointcutOf(arguments.first.argumentExpression);
  }

  static AdvisorPointcut? _pointcutOf(Expression pointcut) {
    if (pointcut is! InstanceCreationExpression) {
      return null;
    }
    final type = pointcut.staticType;
    if (type is! InterfaceType) {
      return null;
    }
    if (_expressionPointcutType.isExactlyType(type)) {
      final arguments = pointcut.argumentList.arguments;
      // Only the expression itself: named pointcuts or bindings are
      // beyond what the build follows.
      if (arguments.length != 1 || arguments.single is NamedArgument) {
        return null;
      }
      final text = arguments.single.argumentExpression;
      if (text is! StringLiteral || text.stringValue == null) {
        return null;
      }
      return AdvisorPointcut(expression: text.stringValue);
    }
    if (_annotationMatchingPointcutType.isExactlyType(type)) {
      final annotation = type.typeArguments.single;
      return annotation is InterfaceType
          ? AdvisorPointcut(annotations: {_qualifiedName(annotation)})
          : null;
    }
    final field = type.element.getField('annotationTypes');
    final values = field != null && field.isStatic && field.isConst
        ? field.computeConstantValue()?.toListValue()
        : null;
    if (values == null) {
      return null;
    }
    return AdvisorPointcut(
      annotations: {
        for (final value in values)
          if (value.toTypeValue() case final InterfaceType annotation)
            _qualifiedName(annotation),
      },
    );
  }

  static String _qualifiedName(InterfaceType type) =>
      '${type.element.library.uri}#${type.element.name}';
}
