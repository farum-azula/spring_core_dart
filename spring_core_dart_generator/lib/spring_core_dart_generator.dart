/// The code generator of `spring_core_dart`: a `build_runner` builder that
/// turns annotated classes into plain Dart code at build time.
///
/// The container needs to know which classes are beans, how to construct
/// them and what they inject. Dart has no runtime reflection on AOT or
/// Flutter, so this package reads the annotations at build time instead
/// and writes the answers down as code. A library with a `@ComponentScan()`
/// variable, or a `main` annotated with `@SpringBootApplication()`, gets a
/// sibling `<file>.spring.dart` with the bean definitions, AOP proxies and
/// accessors the runtime uses.
///
/// Applications never import this library. Add the package as a dev
/// dependency next to `build_runner`; its `build.yaml` applies the builder
/// to every package that depends on it. Then run
/// `dart run build_runner build` (or `watch`).
///
/// ```yaml
/// dev_dependencies:
///   build_runner: ^2.17.0
///   spring_core_dart_generator: ^0.4.0
/// ```
///
/// Spring (Java) has no build step: the same work happens at runtime through
/// classpath scanning and reflection, or ahead of time with Spring AOT:
/// ```java
/// var context = new AnnotationConfigApplicationContext("com.example");
/// ```
library;

export 'package:spring_core_dart_generator/builder.dart';
