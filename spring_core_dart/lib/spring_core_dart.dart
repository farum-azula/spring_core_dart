/// Spring's programming model for Dart: classes declared as beans with
/// annotations are created, wired together and configured by a container,
/// instead of being built by hand in `main`.
///
/// This library exports everything: the container and its annotations,
/// the environment and config files, events, messages, resources, type
/// conversion, SpEL expressions, JSON, validation and AOP. Import it in an
/// application; import a single part (`core.dart`, `beans.dart`,
/// `context.dart`, `expression.dart`, `json.dart`, `validation.dart`,
/// `aop.dart`) to keep a library's dependencies small. The JSR-330/250
/// names live apart in `jakarta.dart`. The annotations are read at build
/// time by `spring_core_dart_generator`, which writes the wiring code
/// (`$appBeans` below); applications built on Spring Boot's conventions
/// use `spring_boot_dart` on top of this package.
///
/// ```dart
/// // A bean with a configurable greeting, and the context that runs it.
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
export 'package:spring_core_dart/json.dart';
export 'package:spring_core_dart/validation.dart';
