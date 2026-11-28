// spring_boot_starter_restclient's part of the module build: the HTTP
// service interfaces of `@ImportHttpServices`, each implemented by a
// generated class of direct `RestClient` calls, and their groups.
import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/beans/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/restclient/http_service_emitter.dart';
import 'package:spring_core_dart_generator/src/restclient/http_service_model.dart';
import 'package:spring_core_dart_generator/src/restclient/http_service_scanner.dart';

/// The part of `spring_boot_starter_restclient` in the module build.
///
/// - Each `@ImportHttpServices` (on a class of a scanned library, on the
///   application's `main` or on a `@ComponentScan` variable) imports its
///   interfaces into its group, those of `types` and those the build finds
///   in the package's libraries below `basePackages` and
///   `basePackageClasses`: each becomes a bean, a generated class
///   whose methods are the `RestClient` calls of their exchange
///   annotations, written out, on the `RestClient` of the group. As any
///   bean it gets a proxy for the advice on the interface's methods
///   (`@Retryable`).
/// - What Spring's `HttpServiceProxyFactory` would refuse when the
///   application starts, or send wrong, fails the build: a `{variable}`
///   no `@PathVariable` fills, a parameter without a role, a body on a
///   `GET`, a return type no call gives, an interface with calls that no
///   `@ImportHttpServices` imports...
/// - The module gets the `HttpServiceGroup` bean of each group, from
///   which the starter's `HttpServiceGroups` makes the groups' clients.
///
/// ```dart
/// // Input:
/// @SpringBootApplication()
/// @ImportHttpServices(group: 'catalog', types: [BookService])
/// void main(List<String> args) => runApplication(args);
///
/// // Output (in the module):
/// class _$BookServiceHttpService implements BookService { ... }
///
/// BeanDefinition<BookService>(
///   name: r'bookService',
///   create: (r) => _$BookServiceHttpService(
///     r.dependency<HttpServiceGroups>().restClient(r'catalog'),
///   ), ...),
/// BeanDefinition<HttpServiceGroup>(
///   name: r'httpServiceGroup.catalog#application',
///   create: (r) => const HttpServiceGroup(r'catalog', types: [BookService]),
///   ...),
/// ```
///
/// Spring (Java): the registration of `@ImportHttpServices`
/// (`HttpServiceProxyRegistry`) and the proxies of `HttpServiceProxyFactory`,
/// here written by the build.
final class HttpServiceGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const HttpServiceGeneration();

  @override
  String get package => 'spring_boot_starter_restclient';

  @override
  List<AnnotationPlacement> get placements => const [
    ClassPlacement(
      [importHttpServicesChecker],
      instead:
          'Put it on the application class, its main or a @Configuration() '
          'class',
    ),
    _ExchangePlacement(),
    // A server reads no request attribute into a handler's parameter.
    ParameterPlacement(
      [requestAttributeChecker],
      methodNoun:
          'a method of an HTTP service interface (with @GetExchange, '
          '@PostExchange... ; a server does not read request attributes '
          'into parameters)',
      methodsWith: [httpExchangeChecker],
    ),
  ];

  // The `@ImportHttpServices` of the entry library's functions and
  // variables (the application's `main`): its classes come to [scanClass].
  @override
  Future<void> prepareModule(ModuleBuild build) async {
    final library = await build.buildStep.inputLibrary;
    final scanner = HttpServiceScanner(build);
    for (final element in [
      ...library.topLevelFunctions,
      ...library.topLevelVariables,
    ]) {
      await scanner.importFrom(element, build);
    }
  }

  @override
  void scanClass(ClassElement element, ModuleScan scan) =>
      HttpServiceScanner(
          scan,
        )
        ..remember(element)
        ..rememberImporter(element);

  // A class's `@ImportHttpServices` once every library is scanned: a
  // class is a bean (and under which conditions) only when the core has
  // read the configuration that imports it.
  @override
  Future<void> scanModule(ModuleBuild build) =>
      HttpServiceScanner(build).importClasses(build);

  // An interface with calls that no `@ImportHttpServices` imports is no
  // bean: nothing would implement it. Only an application's module says
  // so; a library's interfaces are imported by the applications using it.
  @override
  Future<void> checkModule(ModuleBuild build) async {
    final library = await build.buildStep.inputLibrary;
    final functions = library.topLevelFunctions;
    if (!functions.any(springBootApplicationOf.hasAnnotationOf)) {
      return;
    }
    final model = HttpServiceModuleModel.of(build.module);
    for (final element in model.declared) {
      if (model.groupOf.containsKey(element)) {
        continue;
      }
      final name = element.name;
      build.collectErrors(
        () => throw InvalidGenerationSource(
          '$name declares HTTP calls (exchange annotations), and no '
          '@ImportHttpServices imports it, so it is no bean and nothing '
          'implements it. Import it, on the application: '
          '@ImportHttpServices(types: [$name]) (or with the group whose '
          'spring.http.serviceclient.<group>.* it calls).',
          element: element,
        ),
      );
    }
  }

  @override
  Iterable<Spec> classes(ModuleEmission emission) =>
      _emitter(emission).serviceClasses();

  @override
  Expression? beanCreation(BeanModel bean, ModuleEmission emission) =>
      switch (bean.creation) {
        HttpServiceCreation(:final model) => _emitter(
          emission,
        ).serviceCreation(model),
        _ => null,
      };

  @override
  Iterable<Expression> beanDefinitions(ModuleEmission emission) =>
      _emitter(emission).groupDefinitions();

  static HttpServiceEmitter _emitter(ModuleEmission emission) =>
      HttpServiceEmitter(emission, HttpServiceModuleModel.of(emission.module));
}

// `@HttpExchange` and its shortcuts: on an HTTP service interface (its
// URL prefix and defaults) or on one of its methods, which the generated
// class implements; elsewhere nothing reads them.
final class _ExchangePlacement extends CheckedPlacement {
  const _ExchangePlacement() : super(const [httpExchangeChecker]);

  @override
  String? problem(AnnotationSite site) {
    final element = site.element;
    return switch (site.kind) {
      PlaceKind.classDeclaration
          when element is ClassElement && element.isAbstract =>
        null,
      PlaceKind.classDeclaration =>
        '${site.name} on ${site.subject}: it describes the calls of an HTTP '
            'service interface, whose class the build writes, and '
            '${element.displayName} is a class of its own. Declare it '
            '`abstract interface class ${element.displayName}` and import '
            'it with @ImportHttpServices.',
      PlaceKind.method when element is MethodElement && element.isAbstract =>
        null,
      PlaceKind.method =>
        '${site.name} on ${site.subject}: a method with a body is not a '
            'call; the build implements the abstract methods of an HTTP '
            'service interface. Remove the body, or the annotation.',
      _ =>
        '${site.name} on ${site.subject}: it goes on an HTTP service '
            'interface or on one of its methods.',
    };
  }
}
