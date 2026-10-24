import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/aop/proxy.dart';

/// The advisors of one aspect, in Spring's order within an aspect (around,
/// before, after, afterReturning, afterThrowing, then declaration order).
///
/// Shared by the `AspectAutoProxyCreator` and `AspectJProxyFactory`; not
/// exported. [aspect] returns the aspect (looked up per call, so lazy and
/// prototype aspects work; called once per proxy or target for a
/// `perthis` / `pertarget` aspect). [named] are the named pointcuts the
/// advice may refer to, [typeTests] / [argumentAnnotations] the runtime
/// type tests (see `ExpressionPointcut`). [singleton] tells whether the
/// aspect is one shared instance: a per-clause aspect must not be.
List<PointcutAdvisor> aspectAdvisors(
  AspectMetadata<Object> metadata, {
  required Object Function() aspect,
  required int order,
  required bool singleton,
  String? beanName,
  Map<String, String> named = const {},
  Map<String, bool Function(Object? value)> typeTests = const {},
  Map<String, Object? Function(Object? value)> argumentAnnotations = const {},
}) {
  final perClause = _perClause(metadata, beanName, singleton);
  final MethodInterceptor Function(AspectAdvice<Object> advice) interceptor;
  if (perClause == null) {
    interceptor = (advice) => AspectAdviceInterceptor(advice, aspect);
  } else {
    // One instance per proxy (`perthis`) or target (`pertarget`), shared
    // by all advice of the aspect, created on the first matching call.
    final instances = Expando<Object>('${metadata.typeName} instances');
    Object instanceFor(MethodInvocation invocation) =>
        instances[perClause.perTarget
                ? invocation.target
                : invocation.proxy] ??=
            aspect();
    interceptor = (advice) =>
        AspectAdviceInterceptor.forInvocation(advice, instanceFor);
  }
  final advice = [...metadata.advice]
    ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return [
    for (final item in advice)
      DefaultPointcutAdvisor(
        ExpressionPointcut(
          // Spring's PerThis/PerTargetInstantiationModelPointcut: the advice
          // applies where the per-clause pointcut matches too.
          perClause == null
              ? item.pointcut
              : '(${perClause.pointcut}) && (${item.pointcut})',
          namedPointcuts: named,
          bindings: item.bindings,
          owner: metadata.typeName,
          typeTests: typeTests,
          argumentAnnotations: argumentAnnotations,
        ),
        interceptor(item),
        order: order,
      ),
  ];
}

// `perthis(pointcut)` / `pertarget(pointcut)`; `null` for a singleton
// aspect. Other AspectJ instantiation models fail, as in Spring AOP.
({bool perTarget, String pointcut})? _perClause(
  AspectMetadata<Object> metadata,
  String? beanName,
  bool singleton,
) {
  final clause = metadata.perClause?.trim() ?? '';
  if (clause.isEmpty) {
    return null;
  }
  final match = RegExp(
    r'^([A-Za-z]+)\s*\((.*)\)$',
    dotAll: true,
  ).firstMatch(clause);
  final kind = match?[1];
  if (kind != 'perthis' && kind != 'pertarget') {
    throw AopConfigException(
      "Aspect ${metadata.typeName}: instantiation model '$clause' is not "
      'supported; Spring AOP supports perthis(...) and pertarget(...) '
      '(percflow, percflowbelow and pertypewithin need AspectJ weaving, '
      'which Spring AOP does not do either).',
    );
  }
  if (singleton) {
    throw AopConfigException(
      "Bean with name '${beanName ?? metadata.typeName}' is a singleton, but "
      'aspect instantiation model is not singleton: a $kind aspect needs '
      "one instance per ${kind == 'perthis' ? 'proxy' : 'target'}; make it "
      "a prototype bean (@Scope('prototype')).",
    );
  }
  return (perTarget: kind == 'pertarget', pointcut: match![2]!);
}
