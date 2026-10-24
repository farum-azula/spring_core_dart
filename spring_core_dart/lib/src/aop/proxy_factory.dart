import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/aspect_advisors.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/aop/proxy.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Creates an AOP proxy programmatically, like Spring's `ProxyFactory`.
///
/// Dart has no runtime proxy classes: the proxy class is the one the
/// generator wrote for a bean ([AopProxyFactory], reachable as the bean
/// definition's `aopProxy`), so [ProxyFactory.forBean] is the usual way
/// in. Every [getProxy] call returns a new proxy of [target] with the
/// advisors added so far (in order; pointcuts still decide per member).
///
/// ```dart
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
  /// A factory for proxies of [target] made by [proxies] (a generated
  /// proxy factory of [target]'s class); [beanName] and [beanAliases]
  /// count for `bean(...)` pointcuts.
  ProxyFactory(
    this.target,
    this.proxies, {
    this.beanName = '',
    List<String> beanAliases = const [],
  }) : beanAliases = List.unmodifiable(beanAliases);

  /// A factory for proxies of the bean [beanName] of [factory] (of its
  /// target, when the bean is already a proxy).
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

  /// The object the proxies forward to.
  final Object target;

  /// The generated proxy factory of [target]'s class.
  final AopProxyFactory proxies;

  /// The bean name, for `bean(...)` pointcuts.
  final String beanName;

  /// Aliases and qualifier values, for `bean(...)` pointcuts.
  final List<String> beanAliases;

  final List<PointcutAdvisor> _advisors = [];

  /// The advisors added so far, outermost first.
  List<PointcutAdvisor> get advisors => List.unmodifiable(_advisors);

  /// Appends [advisor] (it becomes the innermost one).
  void addAdvisor(PointcutAdvisor advisor) => _advisors.add(advisor);

  /// Removes [advisor]; `false` when it was not added.
  bool removeAdvisor(PointcutAdvisor advisor) => _advisors.remove(advisor);

  /// Appends [advice] for every member.
  void addAdvice(MethodInterceptor advice) =>
      addAdvisor(DefaultPointcutAdvisor(const TruePointcut(), advice));

  /// Removes the first advisor whose advice is [advice].
  bool removeAdvice(MethodInterceptor advice) {
    for (final advisor in _advisors) {
      if (identical(advisor.advice, advice)) {
        return _advisors.remove(advisor);
      }
    }
    return false;
  }

  /// A new proxy of [target] with the current advisors.
  ///
  /// Throws an [AopConfigException] when [proxies] cannot proxy (its
  /// `unavailableReason`), or for a subclass proxy: the bean is its own
  /// proxy there, so change its advice with `Advised.addAdvisor`.
  Object getProxy() {
    if (proxies.unavailableReason case final reason?) {
      throw AopConfigException(
        "Cannot create a proxy of ${_describe()}: $reason",
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

/// A [ProxyFactory] that also takes `@Aspect` instances, like Spring's
/// `AspectJProxyFactory`.
///
/// ```dart
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
  /// A factory for proxies of [target] made by [proxies] (see
  /// [ProxyFactory.new]).
  AspectJProxyFactory(
    super.target,
    super.proxies, {
    super.beanName,
    super.beanAliases,
  });

  /// A factory for proxies of the bean [beanName] of [factory] (see
  /// [ProxyFactory.forBean]).
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

  /// Adds the advice of [aspect], described by [metadata] (the `aspect`
  /// of its generated bean definition, or written by hand), ordered by
  /// kind as in Spring. The aspect must be a singleton aspect: Spring's
  /// `addAspect(Object)` rejects `perthis` / `pertarget` instances too.
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
