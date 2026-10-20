import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/aop/calculator.dart';

/// Shared record of advice calls.
final adviceLog = <String>[];

/// Like Spring, `@Aspect` needs `@Component` to be picked up by the scan.
@Aspect()
@Component()
@Order(1)
class AuditAspect {
  @Pointcut('execution(* Calculator.*(..))')
  void calculator() {}

  @Before('calculator()')
  void before(JoinPoint joinPoint) => adviceLog.add(
    'audit:before ${joinPoint.signature.name}${joinPoint.args}',
  );

  @AfterReturning('calculator() && !execution(* *.slowAdd(..))')
  void returned(JoinPoint joinPoint, int result) =>
      adviceLog.add('audit:returned ${joinPoint.signature.name}=$result');

  @AfterReturning('execution(Future slowAdd(int, int))')
  void asyncReturned(int result) => adviceLog.add('audit:async=$result');

  @AfterThrowing('AuditAspect.calculator()')
  void failed(UnsupportedError error) => adviceLog.add('audit:unsupported');

  @AfterThrowing('calculator()')
  void anyFailure(JoinPoint joinPoint, Object error) =>
      adviceLog.add('audit:failed ${error.runtimeType}');

  @After('calculator()')
  void after() => adviceLog.add('audit:after');
}

@Aspect()
@Component()
@Order(2)
class TimingAspect {
  @Around('@annotation(Timed)')
  Object? time(ProceedingJoinPoint joinPoint) {
    adviceLog.add('timing:start ${joinPoint.toShortString()}');
    // Arguments can be replaced before proceeding.
    final result = joinPoint.proceed([...joinPoint.args.take(1), 10]);
    adviceLog.add('timing:end');
    return result;
  }
}

@Configuration()
class AopConfig {
  @Bean()
  PointcutAdvisor upperCaseAdvisor() => DefaultPointcutAdvisor(
    ExpressionPointcut('bean(echoShouter)'),
    UpperCaseInterceptor(),
  );
}
