/// Code generator for `spring_core_dart`.
///
/// Add it as a dev dependency next to `build_runner`; `build.yaml` applies
/// the builder automatically to packages that depend on it. Each library
/// with a `@ComponentScan()` variable gets a `<file>.beans.dart` module.
///
/// ```yaml
/// dev_dependencies:
///   build_runner: ^2.17.0
///   spring_core_dart_generator: ^0.1.0
/// ```
///
/// Spring (Java) has no build step: the same work happens at runtime through
/// classpath scanning and reflection, or ahead of time with Spring AOT:
/// ```java
/// var context = new AnnotationConfigApplicationContext("com.example");
/// ```
library;

export 'package:spring_core_dart_generator/builder.dart';
