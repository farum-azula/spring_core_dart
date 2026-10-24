/// Aspect-oriented programming with generated proxies: `@Aspect` advice,
/// pointcut expressions and advisors (Spring AOP).
///
/// ```dart
/// @Aspect()
/// @Component()
/// class Auditing {
///   @Before('execution(* OrderService.*(..))')
///   void audit(JoinPoint joinPoint) => print(joinPoint.toShortString());
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Aspect
/// @Component
/// class Auditing {
///   @Before("execution(* com.example.OrderService.*(..))")
///   void audit(JoinPoint joinPoint) { ... }
/// }
/// ```
library;

export 'package:spring_core_dart/src/aop/advisor.dart';
export 'package:spring_core_dart/src/aop/aop_context.dart' show AopContext;
export 'package:spring_core_dart/src/aop/annotations.dart';
export 'package:spring_core_dart/src/aop/aop_pointcut.dart';
export 'package:spring_core_dart/src/aop/auto_proxy_creator.dart';
export 'package:spring_core_dart/src/aop/join_point.dart';
export 'package:spring_core_dart/src/aop/proxy.dart';
export 'package:spring_core_dart/src/aop/proxy_factory.dart';
