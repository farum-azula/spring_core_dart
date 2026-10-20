/// Spring Core for Dart: IoC container, environment and config data,
/// events, messages, resources, type conversion, SpEL, validation and AOP.
///
/// Import this library for everything, or a single module: `core.dart`,
/// `beans.dart`, `context.dart`, `expression.dart`, `validation.dart`,
/// `aop.dart`. Annotations are processed by `spring_core_dart_generator`.
///
/// ```dart
/// @Service()
/// class Greeter {
///   Greeter(@Value(r'${greeting:Hello}') this.greeting);
///   final String greeting;
/// }
///
/// @ComponentScan()
/// final BeanModule appBeans = $appBeans;
///
/// void main() {
///   final context = ApplicationContext.run([appBeans]);
///   print(context.getBean<Greeter>().greeting);
///   context.close();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Greeter {
///   Greeter(@Value("${greeting:Hello}") String greeting) { ... }
/// }
///
/// var context = new AnnotationConfigApplicationContext("com.example");
/// System.out.println(context.getBean(Greeter.class).greeting);
/// context.close();
/// ```
library;

export 'package:spring_core_dart/aop.dart';
export 'package:spring_core_dart/beans.dart';
export 'package:spring_core_dart/context.dart';
export 'package:spring_core_dart/core.dart';
export 'package:spring_core_dart/expression.dart';
export 'package:spring_core_dart/validation.dart';
