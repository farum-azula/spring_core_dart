// AOP: @Aspect, @Pointcut, every advice kind, @annotation, within(),
// bean(), ordering between aspects, async methods, advisor beans.
//
// Spring (Java): @Aspect classes with AspectJ pointcut expressions.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/tour_log.dart';

/// Marks methods whose duration is logged.
class Timed {
  const Timed();
}

abstract interface class PricingService {
  @Timed()
  double quote(String isbn, int quantity);

  double refund(String isbn);

  Future<String> reserve(String isbn);
}

@Service()
class DefaultPricingService implements PricingService {
  @override
  double quote(String isbn, int quantity) => 10.0 * quantity;

  @override
  double refund(String isbn) => throw StateError('refunds are closed');

  @override
  Future<String> reserve(String isbn) async => 'reserved $isbn';
}

@Aspect()
@Component()
@Order(1)
class AuditAspect {
  @Pointcut('within(DefaultPricingService)')
  void pricing() {}

  @Before('pricing()')
  void before(JoinPoint joinPoint) =>
      tourLog.add('audit: before ${joinPoint.signature.name}${joinPoint.args}');

  @AfterReturning('pricing() && execution(double *(..))')
  void returned(JoinPoint joinPoint, double result) =>
      tourLog.add('audit: ${joinPoint.signature.name} returned $result');

  @AfterReturning('execution(Future reserve(..))')
  void reserved(String result) => tourLog.add('audit: async "$result"');

  @AfterThrowing('pricing()')
  void failed(StateError error) =>
      tourLog.add('audit: failed ${error.message}');

  @After('pricing()')
  void after(JoinPoint joinPoint) =>
      tourLog.add('audit: after ${joinPoint.signature.name}');
}

@Aspect()
@Component()
@Order(2)
class TimingAspect {
  /// Around advice for every @Timed method; may change the arguments.
  /// The pointcut binds `timed` (the annotation) and `isbn` (the first
  /// argument, when it is a String), as AspectJ does.
  @Around('@annotation(timed) && args(isbn, ..)')
  Object? time(ProceedingJoinPoint joinPoint, Timed timed, String isbn) {
    tourLog.add('timing: start ${joinPoint.toShortString()} isbn=$isbn');
    final result = joinPoint.proceed();
    tourLog.add('timing: end');
    return result;
  }
}

/// No interface and private state: the container creates it as a generated
/// subclass that runs the advice (Spring: a CGLIB proxy).
@Service()
class StockCounter {
  int _reserved = 0;

  @Timed()
  int reserve(String isbn) => ++_reserved;

  /// Calls [reserve] on itself: like a `this.` call in Spring, the advice
  /// of [reserve] does not run, although the bean is its own proxy.
  int reserveAll(List<String> isbns) {
    var last = _reserved;
    for (final isbn in isbns) {
      last = reserve(isbn);
    }
    return last;
  }
}

/// Added to [StockCounter]'s generated subclass by [SloganAudit]'s
/// `@DeclareParents`.
abstract interface class Labelled {
  String get label;
}

class StockLabel implements Labelled {
  @override
  String get label => 'stock counter';
}

/// An aspect registered by a `@Bean` method of [AopConfig] instead of
/// `@Component`, as Spring allows.
@Aspect()
class SloganAudit {
  @DeclareParents('StockCounter', defaultImpl: StockLabel)
  static Labelled? label;

  @AfterReturning('bean(slogans)')
  void returned(JoinPoint joinPoint) =>
      tourLog.add('slogan audit: ${joinPoint.signature.name}');
}

/// An advisor written by hand: upper-cases what the `slogans` bean returns.
class UpperCaseInterceptor implements MethodInterceptor {
  @override
  Object? invoke(MethodInvocation invocation) =>
      (invocation.proceed()! as String).toUpperCase();
}

abstract interface class Slogans {
  String today();
}

@Component('slogans')
class DefaultSlogans implements Slogans {
  @override
  String today() => 'read more books';
}

@Configuration()
class AopConfig {
  @Bean()
  PointcutAdvisor upperCaseAdvisor() => DefaultPointcutAdvisor(
    ExpressionPointcut('bean(slogans)'),
    UpperCaseInterceptor(),
  );

  @Bean()
  SloganAudit sloganAudit() => SloganAudit();
}
