/// The `build_runner` entry points of `spring_core_dart_generator`.
///
/// `build_runner` finds the factories here through the package's
/// `build.yaml`; applications do not import this library. The generator
/// turns annotated Dart classes into plain Dart code at build time, because
/// Dart AOT and Flutter have no `dart:mirrors` to discover them at runtime:
///
/// - A library with a `@ComponentScan()` variable gets a sibling
///   `*.spring.dart` file with a `BeanModule`: one `BeanDefinition` per bean
///   found in its directory, plus the generated AOP proxy classes,
///   introspection metadata and `@Configurable` configurers.
/// - A `main` annotated with `@SpringBootApplication()` (from
///   `spring_boot_dart`) gets the same for the whole package, plus
///   `springApplication` and `runApplication(args)`.
/// - A test file with `@SpringBootTest` classes gets a
///   `test/spring_gen/<name>.test.spring.dart` file with `runSpringTests()`.
/// - A Flutter app with `spring.flutter.theme.*` properties or message
///   files in `lib/resources/` gets `lib/spring_gen/theme.spring.dart` and
///   `lib/spring_gen/messages.spring.dart`, parts of the `@ComponentScan`
///   library's `.spring.dart` with the typed `context.theme` and
///   `context.messages`.
/// - Every package with Spring code gets `lib/spring_gen/spring_metadata.json`:
///   properties, beans, profiles and hints for editors.
/// - A Flutter app with `spring.flutter.web.*` properties in
///   `lib/resources/` gets a `web_dev_config.yaml`, which sets the host,
///   port, headers and proxy of `flutter run` on the web.
///
/// Setup, in the application's package:
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
/// import 'package:my_app/spring_gen/src/beans.spring.dart';
///
/// // Every bean class under lib/src/ ends up in this module.
/// @ComponentScan()
/// final BeanModule appBeans = $appBeans;
/// ```
///
/// Then run `dart run build_runner build` and pass `appBeans` to the
/// application context, for example `ApplicationContext.run([appBeans])`.
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

import 'package:build/build.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/flutter_keys_builder.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/spring_metadata_builder.dart';
import 'package:spring_core_dart_generator/src/test_builder.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart';
import 'package:spring_core_dart_generator/src/web_page_loader_builder.dart';

/// Creates the main builder ([SpringBuilder]), which writes the
/// `*.spring.dart` files; `build.yaml` names it in `builder_factories`.
///
/// Two options tune it, set in the `build.yaml` of the application's
/// package. They only change how much code is generated: a bean without
/// matching advice is never wrapped at runtime either way.
///
/// - `aop_proxies` (see [ProxyMode]): `all` (the default) generates a proxy
///   class for every bean that can be implemented, `interfaces` proxies
///   only the abstract supertypes of a bean (a bean without one gets no
///   proxy), `none` no proxies at all. Any other value throws an
///   [ArgumentError].
/// - `aop_prune` (`true` by default; anything but a `bool` throws an
///   [ArgumentError]): the `@SpringBootApplication` output leaves out the
///   proxy classes of beans that no pointcut of the application can match.
///   `@ComponentScan` modules are never pruned, because any other module
///   may import them and bring aspects the build cannot see.
/// - `dart_defines_exclude` (a list of property name prefixes, empty by
///   default; anything but a list of strings throws an [ArgumentError]):
///   the properties under them, in both their forms (`spring.flutter.theme`
///   and `SPRING_FLUTTER_THEME`), are not offered to `--dart-define`.
///   `springApplication.dartDefines` is shorter; such properties are still
///   read from config files, the environment and the arguments.
///
/// ```yaml
/// targets:
///   $default:
///     builders:
///       spring_core_dart_generator:spring_core_dart:
///         options:
///           # Smaller output: only beans with an abstract supertype can
///           # be advised, through that type.
///           aop_proxies: interfaces
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
  final prune = options.config['aop_prune'] ?? true;
  if (prune is! bool) {
    throw ArgumentError.value(prune, 'aop_prune', 'Expected true or false');
  }
  final excluded = options.config['dart_defines_exclude'] ?? const <Object>[];
  if (excluded is! List || excluded.any((prefix) => prefix is! String)) {
    throw ArgumentError.value(
      excluded,
      'dart_defines_exclude',
      'Expected a list of property name prefixes',
    );
  }
  return SpringBuilder(
    pruneProxies: prune,
    dartDefinesExclude: excluded.cast<String>(),
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

/// Creates the main builder for the `lib/` of a package whose example
/// imports what it writes ([SpringPropertiesBuilder]); `build.yaml` names
/// it `spring_properties`. It takes the options of [springCoreDartBuilder].
Builder springPropertiesBuilder(BuilderOptions options) {
  final builder = springCoreDartBuilder(options) as SpringBuilder;
  return SpringPropertiesBuilder(
    proxyMode: builder.proxyMode,
    pruneProxies: builder.pruneProxies,
    dartDefinesExclude: builder.dartDefinesExclude,
  );
}

/// Creates the test builder ([SpringTestBuilder]), registered in
/// `build.yaml` as `spring_test`.
///
/// For every `test/<name>_test.dart` that declares `@SpringBootTest`
/// classes it writes `test/spring_gen/<name>.test.spring.dart` with a
/// `runSpringTests()` function, which the test's `main` calls to register
/// the tests of those classes. It takes no options.
Builder springTestBuilder(BuilderOptions options) => SpringTestBuilder();

/// Creates the builder of `web_dev_config.yaml` ([WebDevConfigBuilder]),
/// registered in `build.yaml` as `spring_flutter_web`.
///
/// It writes the Flutter web dev server's config file from the
/// `spring.flutter.web.*` properties of `lib/resources/` (read with the
/// `web` profile), so `flutter run -d chrome` serves the app on a fixed
/// port without flags. Without those properties it writes nothing, and it
/// never changes or deletes a hand-written `web_dev_config.yaml`. It takes
/// no options.
///
/// ```yaml
/// # lib/resources/application-web.yaml
/// spring:
///   flutter:
///     web:
///       port: 5050
/// ```
Builder springFlutterWebBuilder(BuilderOptions options) =>
    WebDevConfigBuilder();

/// Creates the builder of the page loader ([WebPageLoaderBuilder]),
/// registered in `build.yaml` as `spring_flutter_page_loader`.
///
/// For an app that depends on `spring_boot_starter_flutter` and has a
/// `web/index.html` it writes the page loader of the `splash` of the active
/// theme between `<!-- spring:loader:start -->` and
/// `<!-- spring:loader:end -->`, so the browser shows the app's look from
/// the first byte; the Flutter splash takes over without a jump. It takes
/// no options.
///
/// ```yaml
/// # lib/resources/application.yaml
/// spring.flutter.theme:
///   splash: { title: NEON, loader: dots }
///   loaders: { dots: { kind: dots } }
/// ```
Builder springFlutterPageLoaderBuilder(BuilderOptions options) =>
    WebPageLoaderBuilder();

/// Creates the builder of the typed keys, `lib/spring_gen/theme.spring.dart`
/// and `lib/spring_gen/messages.spring.dart` ([FlutterKeysBuilder]),
/// registered in `build.yaml` as `spring_flutter_keys`.
///
/// For an app that depends on `spring_boot_starter_flutter` it writes the
/// typed keys of the configuration: `context.theme.colors.surface`,
/// `context.theme.spacing.m`, `context.messages.basket.total(price)`. A key
/// renamed in `lib/resources/` is then a compile error in the widgets that
/// use it. The files are parts of the `.spring.dart` of the package's
/// `@ComponentScan` library, which a widget imports. It takes no options.
///
/// ```dart
/// import 'package:my_app/spring_gen/main.spring.dart';
///
/// Padding(
///   padding: EdgeInsets.all(context.theme.spacing.m),
///   child: Text(context.messages.basket.empty),
/// );
/// ```
Builder springFlutterKeysBuilder(BuilderOptions options) =>
    FlutterKeysBuilder();

/// Creates the builder of `lib/spring_gen/spring_metadata.json`
/// ([SpringMetadataBuilder]), registered in `build.yaml` as
/// `spring_metadata`.
///
/// For a package with Spring code it writes the configuration properties
/// (`@ConfigurationProperties` classes with their `///` descriptions and
/// literal defaults), the beans (with types, conditions, injection points
/// and the members SpEL can reach), the profiles, value hints (enum
/// constants, `@Range`, `@WarnValues` and `@PropertyValues`) and, for
/// `spring_boot_starter_flutter`, the theme schema. The language server reads the file, and `tool/spring_schema.dart` makes a
/// JSON Schema for `application.yml` from it. It takes no options.
///
/// ```json
/// {
///   "version": 1,
///   "package": "my_app",
///   "properties": [{"name": "api.host", "type": "String"}]
/// }
/// ```
Builder springMetadataBuilder(BuilderOptions options) =>
    SpringMetadataBuilder();
