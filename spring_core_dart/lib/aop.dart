/// Aspect-oriented programming: code that runs before, after or around the
/// methods of other beans without editing them.
///
/// Import it to write aspects (`@Aspect`, `@Before`, `@Around`, ...),
/// pointcut expressions that pick the advised methods, and advisor beans
/// with your own `MethodInterceptor`. It is also exported by
/// `package:spring_core_dart/spring_core_dart.dart`. Use AOP for concerns
/// that cut across many classes: logging, timing, auditing, permission
/// checks, retries. The proxies that run the advice are written at build
/// time by `spring_core_dart_generator`, so the package must run it.
///
/// ```dart
/// // Logs every call to OrderService.
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
export 'package:spring_core_dart/src/aop/annotations.dart';
export 'package:spring_core_dart/src/aop/aop_context.dart' show AopContext;
export 'package:spring_core_dart/src/aop/aop_pointcut.dart';
export 'package:spring_core_dart/src/aop/auto_proxy_creator.dart';
export 'package:spring_core_dart/src/aop/join_point.dart';
export 'package:spring_core_dart/src/aop/proxy.dart';
export 'package:spring_core_dart/src/aop/proxy_factory.dart';
