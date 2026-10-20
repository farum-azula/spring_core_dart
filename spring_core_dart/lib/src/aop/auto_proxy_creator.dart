import 'package:spring_core_dart/src/aop/advisor.dart';
import 'package:spring_core_dart/src/aop/aop_pointcut.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/post_processors.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Wraps beans in generated AOP proxies when `@Aspect` advice or
/// [PointcutAdvisor] beans match them, like Spring's
/// `AnnotationAwareAspectAutoProxyCreator`.
///
/// Proxies implement the bean's interfaces (like JDK dynamic proxies), so
/// advised beans must be injected by interface type.
///
/// The application context registers it automatically as soon as an
/// `@Aspect` or a [PointcutAdvisor] bean exists (no
/// `@EnableAspectJAutoProxy` needed). Aspects, advisors and post-processors
/// are never proxied themselves.
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
  /// Creates a creator reading aspects and advisors from [beanFactory].
  AspectAutoProxyCreator(this.beanFactory);

  /// The factory whose bean definitions provide aspects and advisors.
  final ConfigurableListableBeanFactory beanFactory;

  // Built lazily on first use, once all bean definitions are known.
  List<PointcutAdvisor>? _advisors;

  /// Runs after other post-processors so proxies wrap the final beans.
  @override
  int get order => Ordered.lowestPrecedence;

  /// All advisors: generated aspect advice plus advisor beans, sorted.
  List<PointcutAdvisor> get advisors => _advisors ??= _buildAdvisors();

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
    final eligible = proxyFactory.eligibleAdvisors(advisors, beanName);
    if (eligible.isEmpty) {
      return bean;
    }
    return proxyFactory.createProxy(bean, eligible, beanName: beanName);
  }

  // Collects every aspect's advice and every advisor bean into one list:
  // - named pointcuts of all aspects are shared, by method name and by
  //   `BeanType.method`, so aspects can reference each other's pointcuts;
  // - within an aspect, advice is sorted by kind (around, before, after,
  //   afterReturning, afterThrowing), as in Spring;
  // - the list is sorted by order (aspect `@Order` / advisor order), ties
  //   keep registration order (the sequence number makes it stable).
  // The first advisor is the outermost interceptor of a call.
  List<PointcutAdvisor> _buildAdvisors() {
    final named = <String, String>{};
    final aspects = [
      for (final name in beanFactory.beanDefinitionNames)
        if (beanFactory.getBeanDefinition(name) case final definition
            when definition.aspect != null)
          definition,
    ];
    for (final definition in aspects) {
      definition.aspect!.pointcuts.forEach((method, expression) {
        named[method] = expression;
        named['${definition.beanType}.$method'] = expression;
      });
    }
    final entries = <(PointcutAdvisor, int, int)>[];
    var sequence = 0;
    for (final definition in aspects) {
      final advice = [...definition.aspect!.advice]
        ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
      final order = definition.order ?? Ordered.lowestPrecedence;
      for (final item in advice) {
        entries.add((
          DefaultPointcutAdvisor(
            ExpressionPointcut(item.pointcut, namedPointcuts: named),
            // The aspect bean is looked up per call, so lazy and
            // prototype aspects work.
            AspectAdviceInterceptor(
              item,
              () => beanFactory.getBeanByName(definition.name),
            ),
            order: order,
          ),
          order,
          sequence++,
        ));
      }
    }
    for (final name in beanFactory.getBeanNamesForType(PointcutAdvisor)) {
      final advisor = beanFactory.getBeanByName(name) as PointcutAdvisor;
      final order = OrderComparator.orderOf(
        advisor,
        beanFactory.getBeanDefinition(name).order,
      );
      entries.add((advisor, order, sequence++));
    }
    entries.sort((a, b) {
      final byOrder = a.$2.compareTo(b.$2);
      return byOrder != 0 ? byOrder : a.$3.compareTo(b.$3);
    });
    return [for (final (advisor, _, _) in entries) advisor];
  }
}
