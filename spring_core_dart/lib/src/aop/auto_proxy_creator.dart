import 'dart:collection';

import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/aop/aspect_advisors.dart';
import 'package:spring_core_dart/src/aop/proxy.dart';
import 'package:spring_core_dart/src/beans/bean_definition.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/beans/post_processors.dart';
import 'package:spring_core_dart/src/context/application_context.dart';
import 'package:spring_core_dart/src/core/log.dart';
import 'package:spring_core_dart/src/core/order.dart';

const _log = SpringLog('spring_core_dart.aop');

/// The bean post-processor that puts advice into effect: it replaces each
/// bean that some advice matches with the bean's generated proxy.
///
/// Aspects and advisor beans only describe advice; something has to wrap
/// the advised beans as they are created. This post-processor collects the
/// advice of every `@Aspect` and every [Advisor] bean, orders it, and after
/// each bean is initialized checks it against the pointcuts. A matched
/// bean is replaced by its proxy, which is what `getBean` and other beans
/// then receive; an unmatched bean is left as it is and costs nothing.
///
/// Applications never create it: the application context registers it as
/// soon as an `@Aspect` or an [Advisor] bean exists, here or in an
/// ancestor context (no `@EnableAspectJAutoProxy` needed). Aspects and
/// advisors of ancestor contexts apply too. Aspects, advisors and
/// post-processors are never proxied themselves, nor is a bean the
/// generator wrote no proxy class for.
///
/// The proxy implements the bean's class when that class can be
/// implemented, else its interfaces; a class that can only be extended is
/// created as a generated subclass instead. A bean proxied through its
/// interfaces only must be injected by one of them.
///
/// ```dart
/// // Defining the aspect is enough: the context wraps the Calculator.
/// @Aspect()
/// @Component()
/// @Log()
/// class AuditAspect {
///   @Before('execution(* Calculator.*(..))')
///   void before(JoinPoint joinPoint) => log.info(joinPoint.toShortString());
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
  /// A post-processor reading aspects and advisors from [beanFactory] and
  /// its ancestors.
  AspectAutoProxyCreator(this.beanFactory);

  /// The factory whose bean definitions provide the aspects and advisors,
  /// and whose beans are proxied.
  final ConfigurableListableBeanFactory beanFactory;

  // Built on first use, once all bean definitions are known; not cached
  // while an advisor bean could not be created yet.
  List<PointcutAdvisor>? _advisors;

  // Type names of the registered aspects (for `@DeclareParents`
  // introductions), set by [_buildAdvisors].
  Set<String> _aspectTypes = const {};

  /// `Ordered.highestPrecedence`: it runs first among the ordered
  /// post-processors, like Spring's auto proxy creator, so later
  /// post-processors see the proxy.
  @override
  int get order => Ordered.highestPrecedence;

  /// Every advisor that may apply, outermost first: one per aspect advice
  /// method, plus the advisor beans.
  ///
  /// They are sorted by order (`@Order` or `Ordered` of the aspect, the
  /// advisor's order), ties keeping registration order; within one aspect
  /// by advice kind. Advisor beans being created right now (or depending
  /// on a bean being created) are left out, like Spring's
  /// `BeanFactoryAdvisorRetrievalHelper`; the list is then rebuilt on the
  /// next use, else it is built once.
  List<PointcutAdvisor> get advisors => _advisors ?? _buildAdvisors();

  /// Whether [factory] or one of its ancestors declares an `@Aspect` or an
  /// [Advisor] bean (also one registered as a plain singleton), so the
  /// context must register an auto proxy creator.
  static bool isRequiredFor(ConfigurableListableBeanFactory factory) =>
      [factory, ..._ancestors(factory)].any(
        (f) =>
            f.beanDefinitionNames.any((name) {
              final definition = f.getBeanDefinition(name);
              return definition.aspect != null ||
                  definition.types.contains(Advisor) ||
                  definition.types.contains(PointcutAdvisor);
            }) ||
            _manualAdvisorNames(f).isNotEmpty,
      );

  // Advisors registered with `registerSingleton` (e.g. by a
  // BeanFactoryPostProcessor): not bean definitions, found by instance like
  // Spring's `getBeanNamesForType(Advisor.class)`, which includes manual
  // singletons.
  static List<String> _manualAdvisorNames(
    ConfigurableListableBeanFactory factory,
  ) => [
    for (final name in factory.singletonNames)
      if (!factory.containsBeanDefinition(name) &&
          factory.getSingleton(name) is Advisor)
        name,
  ];

  // The beans with a deferred placeholder [checkDeferredProxies] checked,
  // with the definition and the factory in use then, and the advisors it
  // checked them against: created later, they are not checked again while
  // all three are the same.
  List<PointcutAdvisor>? _checkedAdvisors;

  // The beans already warned about ([postProcessAfterInitialization]): a
  // prototype is made many times.
  final _unadvisedTargetClass = <String>{};
  final _checkedDeferred =
      <String, (BeanDefinition<Object>, AopProxyFactory)>{};

  /// Checks at startup that the proxies the build left out or pruned lose
  /// no advice, and throws an [AopConfigException] when they would:
  ///
  /// - advice matches a member of a bean whose own proxy factory is an
  ///   `AopProxyFactory.deferred` placeholder (a starter's bean) and the
  ///   factory in use does not intercept that member: no module of the
  ///   context brought its proxy class (a context built without the
  ///   application's generated module), or the one registered for it
  ///   leaves the member out;
  /// - a bean's factory in use was pruned by the build
  ///   (`AopProxyFactory.knownAdvisors`: no proxy class, or one for some
  ///   members only) and an aspect or advisor bean of this context or an
  ///   ancestor is not one the build knew of (registered in code, by a
  ///   registrar or with `registerSingleton`).
  ///
  /// The context calls it before it creates the singletons (after it set
  /// the `conversionService`), so a lazy bean fails at startup too, not on
  /// first use. No advisor is created when no placeholder is left.
  void checkDeferredProxies() {
    _checkedAdvisors = null;
    _checkedDeferred.clear();
    final deferred = <(String, BeanDefinition<Object>)>[];
    // Each set of known advisors in use, with a bean using it.
    final pruned = LinkedHashMap<Set<String>, String>.identity();
    for (final name in beanFactory.beanDefinitionNames) {
      final definition = beanFactory.getBeanDefinition(name);
      final own = definition.aopProxy;
      if (own == null || definition.aspect != null) {
        continue;
      }
      if (own.isDeferred) {
        deferred.add((name, definition));
      }
      if (beanFactory.aopProxyOf(definition)?.knownAdvisors case final known?) {
        pruned.putIfAbsent(known, () => name);
      }
    }
    pruned.forEach(_checkKnownAdvisors);
    if (deferred.isEmpty) {
      return;
    }
    final checked = _checkedAdvisors = advisors;
    for (final (name, definition) in deferred) {
      _checkDeferred(name, definition, checked);
      _checkedDeferred[name] = (
        definition,
        beanFactory.aopProxyOf(definition)!,
      );
    }
  }

  // Throws when an aspect or advisor bean of this factory or an ancestor
  // is not in [known], the advisors the build knew of when it pruned the
  // proxy of [beanName] (and maybe others).
  void _checkKnownAdvisors(Set<String> known, String beanName) {
    final seen = <String>{};
    for (final factory in [beanFactory, ..._ancestors(beanFactory)]) {
      final names = factory.beanDefinitionNames;
      for (final name in names) {
        if (seen.contains(name)) {
          continue;
        }
        final definition = factory.getBeanDefinition(name);
        if ((definition.aspect != null ||
                definition.types.contains(Advisor) ||
                definition.types.contains(PointcutAdvisor)) &&
            !_isKnown(known, definition.source)) {
          _unknownAdvisor(
            definition.aspect != null ? 'aspect' : 'advisor',
            name,
            definition.source,
            beanName,
          );
        }
      }
      seen.addAll(names);
      for (final name in _manualAdvisorNames(factory)) {
        if (seen.add(name)) {
          _unknownAdvisor('advisor', name, 'registerSingleton', beanName);
        }
      }
    }
  }

  // Whether [source] is one of [known]: listed, or in a package listed.
  static bool _isKnown(Set<String> known, String? source) =>
      source != null &&
      (known.contains(source) ||
          known.any(
            (entry) =>
                !entry.contains('#') &&
                (source.startsWith('$entry/') || source.startsWith('$entry#')),
          ));

  static Never _unknownAdvisor(
    String kind,
    String name,
    String? source,
    String beanName,
  ) => throw AopConfigException(
    "The $kind bean '$name' (${source ?? 'registered in code'}) is not one "
    'the build knew of when it generated the proxies of the beans for only '
    "the advice it found (bean '$beanName' and maybe others): its advice "
    'would not reach the members left out. Build the application with the '
    'option aop_prune: false, or declare the advice where the build reads '
    'it (an @Aspect, or a @Bean method returning a DefaultPointcutAdvisor '
    'with a constant pointcut).',
  );

  // Throws when an advisor matches a member of the placeholder of
  // [definition] that the factory in use does not intercept: all of them
  // when no factory was registered for it.
  void _checkDeferred(
    String name,
    BeanDefinition<Object> definition,
    List<PointcutAdvisor> advisors,
  ) {
    final placeholder = definition.aopProxy!;
    final used = beanFactory.aopProxyOf(definition)!;
    final missing = identical(used, placeholder)
        ? placeholder.signatures
        : () {
            final intercepted = {
              for (final signature in used.signatures)
                (signature.name, signature.kind),
            };
            return [
              for (final signature in placeholder.signatures)
                if (!intercepted.contains((signature.name, signature.kind)))
                  signature,
            ];
          }();
    if (missing.isEmpty) {
      return;
    }
    final aliases = [
      ...beanFactory.getAliases(name),
      ...definition.qualifiers,
    ];
    for (final advisor in advisors) {
      for (final signature in missing) {
        if (!pointcutMatchesBean(advisor.pointcut, signature, name, aliases)) {
          continue;
        }
        if (identical(used, placeholder)) {
          throw AopConfigException(
            "Advice matches bean '$name' ($advisor), but it cannot be "
            'proxied: ${AopProxyFactory.deferredReason}',
          );
        }
        throw AopConfigException(
          "Advice matches member '${signature.name}' of bean '$name' "
          '($advisor), but the proxy class registered for it '
          '(${definition.source}) does not intercept that member. Build the '
          'application with the option aop_prune: false.',
        );
      }
    }
  }

  /// Returns the proxy of [bean] when an advisor matches one of its
  /// members, or a `@DeclareParents` introduction of a registered aspect
  /// applies to it; else [bean] itself.
  ///
  /// Only beans whose definition has a generated proxy factory are
  /// proxied; aspects, advisors and post-processors are skipped. Throws an
  /// `AopConfigException` when advice matches a bean that cannot be
  /// proxied.
  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (!beanFactory.containsBeanDefinition(beanName)) {
      return bean;
    }
    final definition = beanFactory.getBeanDefinition(beanName);
    final proxyFactory = beanFactory.aopProxyOf(definition);
    if (proxyFactory == null ||
        definition.aspect != null ||
        bean is Advisor ||
        bean is BeanPostProcessor) {
      return bean;
    }
    // A starter's bean: no advice may match a member the factory in use
    // does not intercept. Checked at startup, against the same advisors and
    // factory, it is not checked again.
    if (definition.aopProxy?.isDeferred ?? false) {
      final current = advisors;
      final checked = _checkedDeferred[beanName];
      if (checked == null ||
          !identical(checked.$1, definition) ||
          !identical(checked.$2, proxyFactory) ||
          !identical(_checkedAdvisors, current)) {
        _checkDeferred(beanName, definition, current);
      }
      // A placeholder still: nothing matches it.
      if (proxyFactory.isDeferred) {
        return bean;
      }
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
    // An introduction of a registered aspect proxies the bean too
    // (Spring's DeclareParentsAdvisor is an IntroductionAdvisor).
    if (eligible.isEmpty &&
        !proxyFactory.introductions.any(
          (introduction) => _aspectTypes.contains(introduction.aspectType),
        )) {
      // A member annotated for advice on the bean's own calls, and no
      // advice for it: the annotation would do nothing without a word.
      if (proxyFactory.adviseSelfCalls && _unadvisedTargetClass.add(beanName)) {
        _log.warning(
          "The bean '$beanName' has members annotated for advice that "
          "follows the bean's own calls (an annotation marked "
          '@ProxyTargetClass), and no advice matches it: the annotations '
          'do nothing. Is the auto-configuration of the starter they come '
          'from left out of the application (spring.autoconfigure.exclude, '
          'or an application put together by hand)?',
        );
      }
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
      final manual = _manualAdvisorNames(factory);
      for (final name in manual) {
        if (!seen.contains(name)) {
          advisorNames.add((factory, name));
        }
      }
      seen.addAll(manual);
    }

    _aspectTypes = {
      for (final (_, definition) in aspects) definition.aspect!.typeName,
    };
    // Runtime type tests of every aspect; an aspect's own entries win.
    final typeTests = <String, bool Function(Object?)>{
      for (final (_, definition) in aspects) ...definition.aspect!.typeTests,
    };
    final argumentAnnotations = <String, Object? Function(Object?)>{
      for (final (_, definition) in aspects)
        ...definition.aspect!.argumentAnnotations,
    };
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
      final (order, known) = _aspectOrder(factory, definition);
      complete &= known;
      for (final advisor in aspectAdvisors(
        metadata,
        // The aspect bean is looked up per call, so lazy and prototype
        // aspects work.
        aspect: () => factory.getBeanByName(definition.name),
        order: order,
        singleton: definition.isSingleton,
        beanName: definition.name,
        named: {...qualified, ...metadata.pointcuts},
        typeTests: {...typeTests, ...metadata.typeTests},
        argumentAnnotations: {
          ...argumentAnnotations,
          ...metadata.argumentAnnotations,
        },
      )) {
        entries.add((advisor, order, sequence++));
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
        factory.containsBeanDefinition(name)
            ? factory.getBeanDefinition(name).order
            : null,
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
    // Unmodifiable: the startup check knows the list it checked against
    // by identity.
    final result = List<PointcutAdvisor>.unmodifiable([
      for (final (advisor, _, _) in entries) advisor,
    ]);
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
