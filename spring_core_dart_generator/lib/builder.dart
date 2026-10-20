/// `build_runner` entry point of `spring_core_dart_generator`.
///
/// The generator turns annotated Dart classes into plain Dart code at build
/// time: for every library that declares a `@ComponentScan()` variable it
/// writes a sibling `*.beans.dart` file with a `BeanModule` holding one
/// `BeanDefinition` per bean, generated AOP proxy classes, introspection
/// metadata and `@Configurable` configurers. Nothing is discovered by
/// reflection at runtime (Dart AOT and Flutter have no `dart:mirrors`).
///
/// Setup (in the consuming package):
///
/// ```yaml
/// # pubspec.yaml
/// dependencies:
///   spring_core_dart: any
/// dev_dependencies:
///   build_runner: any
///   spring_core_dart_generator: any
/// ```
///
/// ```dart
/// // lib/src/beans.dart
/// import 'package:spring_core_dart/spring_core_dart.dart';
/// import 'package:my_app/src/beans.beans.dart';
///
/// @ComponentScan()
/// final BeanModule appBeans = $appBeans;
/// ```
///
/// Then run `dart run build_runner build` and register `appBeans` with an
/// application context.
///
/// Spring (Java):
///
/// ```java
/// // Spring discovers beans at runtime: ClassPathBeanDefinitionScanner
/// // reads class files, ConfigurationClassPostProcessor parses @Bean
/// // methods and reflection creates the instances.
/// var context = new AnnotationConfigApplicationContext();
/// context.scan("com.example.app");
/// context.refresh();
/// // Spring 6 AOT (BeanFactoryInitializationAotProcessor) can instead
/// // generate Java source at build time, which is what this builder
/// // always does for Dart.
/// ```
library;

import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:build/build.dart';

/// Creates the [SpringBuilder]; referenced from the package's `build.yaml`
/// (`builder_factories: ["springCoreDartBuilder"]`).
///
/// Reads the `aop_proxies` option (`all` by default, `interfaces` or
/// `none`; see [ProxyMode]) and throws an [ArgumentError] for any other
/// value.
///
/// Example `build.yaml` in a consuming package:
///
/// ```yaml
/// targets:
///   $default:
///     builders:
///       spring_core_dart_generator:spring_core_dart:
///         options:
///           aop_proxies: interfaces # JDK-proxy style: only abstract types
/// ```
///
/// Spring (Java):
///
/// ```java
/// // The closest Spring switch decides between JDK interface proxies and
/// // CGLIB class proxies for AnnotationAwareAspectJAutoProxyCreator:
/// @EnableAspectJAutoProxy(proxyTargetClass = false) // interfaces only
/// @Configuration
/// class AopConfig {}
/// ```
Builder springCoreDartBuilder(BuilderOptions options) {
  final mode = options.config['aop_proxies'] as String? ?? 'all';
  return SpringBuilder(
    proxyMode: ProxyMode.values.firstWhere(
      (m) => m.name == mode,
      orElse: () => throw ArgumentError.value(
        mode,
        'aop_proxies',
        'Expected all, interfaces or none',
      ),
    ),
  );
}
