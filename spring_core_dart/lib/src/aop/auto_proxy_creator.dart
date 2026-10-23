import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/beans/bean_definition.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/beans/post_processors.dart';
import 'package:spring_core_dart/src/context/application_context.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Wraps beans in generated AOP proxies when `@Aspect` advice or
/// [Advisor] beans match them, like Spring's
/// `AnnotationAwareAspectJAutoProxyCreator`.
///
/// Proxies implement the bean's interfaces (like JDK dynamic proxies), so
/// advised beans must be injected by interface type.
///
/// The application context registers it automatically as soon as an
/// `@Aspect` or an [Advisor] bean exists, here or in an ancestor context
/// (no `@EnableAspectJAutoProxy` needed). Aspects and advisors of ancestor
/// contexts apply too. Aspects, advisors and post-processors are never
/// proxied themselves.
///
/// ```dart
/// @Aspect()
/// @Component()
/// class AuditAspect {
///   @Before('execution(* Calculator.*(..))')
///   void before(JoinPoint joinPoint) => print(joinPoint.toShortString());
/// }
///
/// final context = ApplicationContext.run([appBeans]);
/// final calculator = context.getBean<Calculator>(); // a proxy
/// calculator.add(1, 2); // prints execution(Calculator.add(..))
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// @EnableAspectJAutoProxy // registers AnnotationAwareAspectJAutoProxyCreator
/// @ComponentScan
/// class AppConfig {}
///
/// var context = new AnnotationConfigApplicationContext(AppConfig.class);
/// Calculator calculator = context.getBean(Calculator.class);
/// calculator.add(1, 2);
/// ```
class AspectAutoProxyCreator extends BeanPostProcessor implements Ordered {
  /// Creates a creator reading aspects and advisors from [beanFactory]
  /// (and its ancestors).
  AspectAutoProxyCreator(this.beanFactory);

  /// The factory whose bean definitions provide aspects and advisors.
  final ConfigurableListableBeanFactory beanFactory;

  // Built on first use, once all bean definitions are known; not cached
  // while an advisor bean could not be created yet.
  List<PointcutAdvisor>? _advisors;

  /// Runs first among the ordered post-processors, like Spring's
  /// auto proxy creator (`HIGHEST_PRECEDENCE`): later post-processors see
  /// the proxy.
  @override
  int get order => Ordered.highestPrecedence;

  /// All advisors: generated aspect advice plus advisor beans, sorted.
  ///
  /// Advisor beans being created right now (or depending on a bean being
  /// created) are left out, like Spring's
  /// `BeanFactoryAdvisorRetrievalHelper`; the list is then rebuilt on the
  /// next use.
  List<PointcutAdvisor> get advisors => _advisors ?? _buildAdvisors();

  /// Whether [factory] or one of its ancestors declares an `@Aspect` or an
  /// [Advisor] bean, i.e. whether a context needs an auto proxy creator.
  static bool isRequiredFor(ConfigurableListableBeanFactory factory) =>
      [factory, ..._ancestors(factory)].any(
        (f) => f.beanDefinitionNames.any((name) {
          final definition = f.getBeanDefinition(name);
          return definition.aspect != null ||
              definition.types.contains(Advisor) ||
              definition.types.contains(PointcutAdvisor);
        }),
      );

  /// Returns a proxy of [bean] when eligible advisors match one of its
  /// members, else [bean] itself.
  ///
  /// Only beans whose definition has a generated proxy factory are
  /// proxied; aspects, advisors and post-processors are skipped.
  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (!beanFactory.containsBeanDefinition(beanName)) {
      return bean;
    }
    final definition = beanFactory.getBeanDefinition(beanName);
    final proxyFactory = definition.aopProxy;
    if (proxyFactory == null ||
        definition.aspect != null ||
        bean is Advisor ||
        bean is BeanPostProcessor) {
      return bean;
    }
    // `bean(...)` also matches aliases and qualifier values.
    final aliases = [
      ...beanFactory.getAliases(beanName),
      ...definition.qualifiers,
    ];
    final eligible = proxyFactory.eligibleAdvisors(
      advisors,
      beanName,
      beanAliases: aliases,
    );
    if (eligible.isEmpty) {
      return bean;
    }
    return proxyFactory.createProxy(
      bean,
      eligible,
      beanName: beanName,
      beanAliases: aliases,
    );
  }

  // Collects every aspect's advice and every advisor bean into one list:
  // - named pointcuts are resolved per aspect: unqualified references in
  //   the aspect's own pointcuts, `Type.name()` in any aspect's (or in the
  //   holder classes the generator listed for the aspect);
  // - within an aspect, advice is sorted by kind (around, before, after,
  //   afterReturning, afterThrowing), as in Spring;
  // - the list is sorted by order (aspect `Ordered` / `@Order`, advisor
  //   order), ties keep registration order (the sequence number makes it
  //   stable); a plain [Advisor] applies to every member.
  // Aspects and advisors of ancestor contexts are included; a local bean
  // shadows an ancestor's bean with the same name.
  // The first advisor is the outermost interceptor of a call.
  List<PointcutAdvisor> _buildAdvisors() {
    var complete = true;
    final factories = [beanFactory, ..._ancestors(beanFactory)];
    final seen = <String>{};
    final aspects =
        <(ConfigurableListableBeanFactory, BeanDefinition<Object>)>[];
    final advisorNames = <(ConfigurableListableBeanFactory, String)>[];
    for (final factory in factories) {
      final names = factory.beanDefinitionNames;
      for (final name in names) {
        if (seen.contains(name)) {
          continue;
        }
        final definition = factory.getBeanDefinition(name);
        if (definition.aspect != null) {
          aspects.add((factory, definition));
        } else if (definition.types.contains(Advisor) ||
            definition.types.contains(PointcutAdvisor)) {
          advisorNames.add((factory, name));
        }
      }
      seen.addAll(names);
    }

    // Every aspect's pointcuts, qualified by the aspect's type name.
    final qualified = <String, String>{
      for (final (_, definition) in aspects)
        for (final MapEntry(key: method, value: expression)
            in definition.aspect!.pointcuts.entries)
          if (!method.contains('.'))
            '${definition.aspect!.typeName}.$method': expression,
    };

    final entries = <(PointcutAdvisor, int, int)>[];
    var sequence = 0;
    for (final (factory, definition) in aspects) {
      final metadata = definition.aspect!;
      final named = {...qualified, ...metadata.pointcuts};
      final advice = [...metadata.advice]
        ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
      final (order, known) = _aspectOrder(factory, definition);
      complete &= known;
      for (final item in advice) {
        entries.add((
          DefaultPointcutAdvisor(
            ExpressionPointcut(
              item.pointcut,
              namedPointcuts: named,
              bindings: item.bindings,
              owner: metadata.typeName,
            ),
            // The aspect bean is looked up per call, so lazy and
            // prototype aspects work.
            AspectAdviceInterceptor(
              item,
              () => factory.getBeanByName(definition.name),
            ),
            order: order,
          ),
          order,
          sequence++,
        ));
      }
    }
    for (final (factory, name) in advisorNames) {
      final advisor = _advisorBean(factory, name);
      if (advisor == null) {
        complete = false;
        continue;
      }
      final order = OrderComparator.orderOf(
        advisor,
        factory.getBeanDefinition(name).order,
      );
      entries.add((
        switch (advisor) {
          final PointcutAdvisor pointcutAdvisor => pointcutAdvisor,
          // A plain advisor applies to every member (Spring's
          // AopUtils.canApply for non-pointcut advisors).
          _ => DefaultPointcutAdvisor(
            const TruePointcut(),
            advisor.advice,
            order: order,
          ),
        },
        order,
        sequence++,
      ));
    }
    entries.sort((a, b) {
      final byOrder = a.$2.compareTo(b.$2);
      return byOrder != 0 ? byOrder : a.$3.compareTo(b.$3);
    });
    final result = [for (final (advisor, _, _) in entries) advisor];
    if (complete) {
      _advisors = result;
    }
    return result;
  }

  // The advisor bean [name], or `null` while it (or a bean it depends on)
  // is being created: it cannot advise the bean whose creation needs it.
  static Advisor? _advisorBean(
    ConfigurableListableBeanFactory factory,
    String name,
  ) {
    if (factory.isCurrentlyInCreation(name)) {
      return null;
    }
    try {
      return factory.getBeanByName(name) as Advisor;
    } on BeansException catch (error) {
      if (_isCreationCycle(error)) {
        return null;
      }
      rethrow;
    }
  }

  // An aspect implementing `Ordered` is asked for its order (Spring's
  // BeanFactoryAspectInstanceFactory.getOrder), else `@Order` counts;
  // `$2` is false when the aspect is being created and could not be asked.
  static (int, bool) _aspectOrder(
    ConfigurableListableBeanFactory factory,
    BeanDefinition<Object> definition,
  ) {
    final fallback = definition.order ?? Ordered.lowestPrecedence;
    if (!definition.isSingleton || !definition.types.contains(Ordered)) {
      return (fallback, true);
    }
    if (factory.isCurrentlyInCreation(definition.name)) {
      return (fallback, false);
    }
    try {
      final aspect = factory.getBeanByName(definition.name);
      return (OrderComparator.orderOf(aspect, definition.order), true);
    } on BeansException catch (error) {
      if (_isCreationCycle(error)) {
        return (fallback, false);
      }
      rethrow;
    }
  }

  // Whether [error] (or one of its causes) reports a bean in creation.
  static bool _isCreationCycle(Object? error) {
    var current = error;
    while (current != null) {
      if (current is BeanCurrentlyInCreationException) {
        return true;
      }
      current = current is BeansException ? current.cause : null;
    }
    return false;
  }

  // Ancestor factories: parent factories, or the factories of parent
  // contexts.
  static Iterable<ConfigurableListableBeanFactory> _ancestors(
    ConfigurableListableBeanFactory factory,
  ) sync* {
    var parent = factory.parentBeanFactory;
    while (parent != null) {
      final ConfigurableListableBeanFactory next;
      switch (parent) {
        case final ConfigurableListableBeanFactory f:
          next = f;
        case final ConfigurableApplicationContext context:
          next = context.beanFactory;
        default:
          return;
      }
      yield next;
      parent = next.parentBeanFactory;
    }
  }
}
