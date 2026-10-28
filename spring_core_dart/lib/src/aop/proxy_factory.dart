import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/aspect_advisors.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/aop/proxy.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Builds extra proxies of a bean in code, with advice chosen by the
/// caller rather than by the context's aspects.
///
/// Use it when one object needs advice that the rest of the application
/// must not get: a test that wraps a bean with a recording interceptor, or
/// a library that hands out a guarded or logging view of a bean. Most
/// applications never need it; aspects and advisor beans cover the usual
/// cases.
///
/// Dart cannot create proxy classes at runtime, so it reuses the proxy
/// class the generator wrote for the bean ([AopProxyFactory], the bean
/// definition's `aopProxy`); [ProxyFactory.forBean] finds it. Every
/// [getProxy] call returns a new proxy of [target] with the advisors added
/// so far, outermost first; their pointcuts still decide per member. The
/// bean in the context is not changed.
///
/// ```dart
/// // A logging view of the calculator bean, for this caller only.
/// final factory = ProxyFactory.forBean(context.beanFactory, 'calculator')
///   ..addAdvice(LoggingInterceptor())
///   ..addAdvisor(DefaultPointcutAdvisor(
///     ExpressionPointcut('execution(* add(..))'),
///     CountingInterceptor(),
///   ));
/// final calculator = factory.getProxy() as Calculator;
/// ```
///
/// Spring (Java):
/// ```java
/// ProxyFactory factory = new ProxyFactory(new SimpleCalculator());
/// factory.addAdvice(new LoggingInterceptor());
/// factory.addAdvisor(new DefaultPointcutAdvisor(pointcut, counting));
/// Calculator calculator = (Calculator) factory.getProxy();
/// ```
class ProxyFactory {
  /// A factory for proxies of [target] made by [proxies], the generated
  /// proxy factory of [target]'s class; [beanName] and [beanAliases] are
  /// what `bean(...)` pointcuts match.
  ProxyFactory(
    this.target,
    this.proxies, {
    this.beanName = '',
    List<String> beanAliases = const [],
  }) : beanAliases = List.unmodifiable(beanAliases);

  /// A factory for proxies of the bean [beanName] of [factory]; when the
  /// bean is already a proxy, the new proxies wrap the object behind it.
  ///
  /// Throws an [AopConfigException] when the generator wrote no proxy for
  /// the bean (`aop_proxies: none`, an aspect, a post-processor, ...).
  factory ProxyFactory.forBean(
    ConfigurableListableBeanFactory factory,
    String beanName,
  ) {
    final (target, proxies, aliases) = _beanParts(factory, beanName);
    return ProxyFactory(
      target,
      proxies,
      beanName: beanName,
      beanAliases: aliases,
    );
  }

  /// The object the proxies call after their advice.
  final Object target;

  /// The generated proxy factory of [target]'s class, which makes the
  /// proxies.
  final AopProxyFactory proxies;

  /// The bean name `bean(...)` pointcuts match; empty when [target] is not
  /// a bean.
  final String beanName;

  /// The bean's aliases and qualifier values, which `bean(...)` pointcuts
  /// also match.
  final List<String> beanAliases;

  final List<PointcutAdvisor> _advisors = [];

  /// The advisors added so far, outermost first (a copy).
  List<PointcutAdvisor> get advisors => List.unmodifiable(_advisors);

  /// Appends [advisor] as the innermost one, for the proxies made from
  /// now on.
  void addAdvisor(PointcutAdvisor advisor) => _advisors.add(advisor);

  /// Removes [advisor]; returns `false` when it was not added. Proxies
  /// already made keep it.
  bool removeAdvisor(PointcutAdvisor advisor) => _advisors.remove(advisor);

  /// Appends [advice] as the innermost advice of every member.
  void addAdvice(MethodInterceptor advice) =>
      addAdvisor(DefaultPointcutAdvisor(const TruePointcut(), advice));

  /// Removes the first advisor whose advice is [advice] (the same object);
  /// returns `false` when there is none.
  bool removeAdvice(MethodInterceptor advice) {
    for (final advisor in _advisors) {
      if (identical(advisor.advice, advice)) {
        return _advisors.remove(advisor);
      }
    }
    return false;
  }

  /// Returns a new proxy of [target] with the advisors added so far; cast
  /// it to the bean's type.
  ///
  /// Throws an [AopConfigException] when [proxies] cannot proxy (its
  /// `unavailableReason`), or for a subclass proxy: the bean is its own
  /// proxy there, so change its advice with `Advised.addAdvisor`.
  Object getProxy() {
    if (proxies.unavailableReason case final reason?) {
      throw AopConfigException(
        'Cannot create a proxy of ${_describe()}: $reason',
      );
    }
    if (proxies.isSubclass) {
      throw AopConfigException(
        'Cannot create another proxy of ${_describe()}: it is a generated '
        'subclass proxy, i.e. its own proxy. Add advice to it with '
        '(bean as Advised).addAdvisor(...) instead.',
      );
    }
    return proxies.createProxy(
      target,
      _advisors,
      beanName: beanName,
      beanAliases: beanAliases,
    );
  }

  String _describe() =>
      beanName.isEmpty ? 'a ${target.runtimeType}' : "bean '$beanName'";

  // The target, proxy factory and aliases of the bean [beanName].
  static (Object, AopProxyFactory, List<String>) _beanParts(
    ConfigurableListableBeanFactory factory,
    String beanName,
  ) {
    final definition = factory.getBeanDefinition(beanName);
    final proxies =
        definition.aopProxy ??
        (throw AopConfigException(
          "Bean '$beanName' has no generated proxy class (aop_proxies: none, "
          'or an aspect, advisor, post-processor or @Configuration bean), so '
          'ProxyFactory cannot proxy it.',
        ));
    return (
      AopUtils.getTarget(factory.getBeanByName(beanName)),
      proxies,
      [...factory.getAliases(beanName), ...definition.qualifiers],
    );
  }
}

/// A [ProxyFactory] that also takes the advice of an `@Aspect` object.
///
/// Use it to apply an aspect to one proxy only, for example in a test that
/// checks an aspect against a real bean without registering the aspect in
/// the context. The aspect's advice methods become advisors, in the same
/// order the context would use.
///
/// ```dart
/// // Audit the orders bean through this proxy only. auditAspectMetadata
/// // describes AuditAspect (written by hand in a test).
/// final factory = AspectJProxyFactory.forBean(context.beanFactory, 'orders')
///   ..addAspect(AuditAspect(), auditAspectMetadata);
/// final orders = factory.getProxy() as Orders;
/// ```
///
/// Spring (Java):
/// ```java
/// AspectJProxyFactory factory = new AspectJProxyFactory(orders);
/// factory.addAspect(new AuditAspect());
/// Orders proxy = factory.getProxy();
/// ```
class AspectJProxyFactory extends ProxyFactory {
  /// A factory for proxies of [target] made by [proxies], the generated
  /// proxy factory of [target]'s class.
  AspectJProxyFactory(
    super.target,
    super.proxies, {
    super.beanName,
    super.beanAliases,
  });

  /// A factory for proxies of the bean [beanName] of [factory]; throws an
  /// [AopConfigException] when the generator wrote no proxy for it.
  factory AspectJProxyFactory.forBean(
    ConfigurableListableBeanFactory factory,
    String beanName,
  ) {
    final (target, proxies, aliases) = ProxyFactory._beanParts(
      factory,
      beanName,
    );
    return AspectJProxyFactory(
      target,
      proxies,
      beanName: beanName,
      beanAliases: aliases,
    );
  }

  /// Appends the advice methods of [aspect] as advisors, ordered by kind
  /// as in Spring, at the aspect's `Ordered` order (else the lowest).
  ///
  /// [metadata] describes the aspect: take it from the aspect's generated
  /// bean definition (its `aspect` field) or write it by hand. The aspect
  /// must be a singleton aspect: a `perthis` / `pertarget` one throws an
  /// [AopConfigException], as Spring's `addAspect(Object)` rejects it.
  void addAspect(Object aspect, AspectMetadata<Object> metadata) {
    final order = OrderComparator.orderOf(aspect);
    _advisors.addAll(
      aspectAdvisors(
        metadata,
        aspect: () => aspect,
        order: order,
        singleton: true,
        beanName: metadata.typeName,
        named: {
          for (final MapEntry(:key, :value) in metadata.pointcuts.entries)
            if (!key.contains('.')) '${metadata.typeName}.$key': value,
          ...metadata.pointcuts,
        },
        typeTests: metadata.typeTests,
        argumentAnnotations: metadata.argumentAnnotations,
      ),
    );
  }
}
