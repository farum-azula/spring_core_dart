import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';

// The package whose assets hold the templates, and the library everything
// the glue and its bean definition name is imported from.
const _starterPackage = 'spring_boot_starter_data';
const _starterUrl =
    'package:spring_boot_starter_data/spring_boot_starter_data.dart';
const _springUrl = 'package:spring_core_dart/spring_core_dart.dart';
const _webUrl = 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// A database driver package that `spring_boot_starter_data` has glue for.
///
/// The starter cannot depend on a driver package (`sqlite3` bundles a
/// native library, and pub has no optional dependencies). The application
/// lists the one it wants; seeing it among the application's own
/// dependencies ([direct]: a driver is the application's choice, never one
/// that only arrives with another package), the generator copies the
/// starter's template for it into the generated module, and registers a
/// `JdbcDriver` bean made by it. Spring Boot does the same with
/// `@ConditionalOnClass` on the JDBC driver.
///
/// The same table holds the glue between the data starter and another
/// starter it must not depend on: the web starter's, which answers data
/// errors with their HTTP status and fills `Pageable` and `Sort` controller
/// parameters (`spring_boot_starter_web`). The bean is then of a type of
/// that starter ([type] in [typeUrl]). This glue is written when the
/// application reaches the web starter, listed by it or brought by a
/// package it lists, as the data starter itself is reached.
///
/// Spring (Java): the driver jar on the classpath that
/// `DataSourceAutoConfiguration` finds by its class.
final class DriverGlue {
  /// The glue for the package [package]: [template] is its asset in the
  /// starter, [beanName] the bean it makes and [factory] the function of
  /// the template that creates it, a [type] (`JdbcDriver` of the starter's
  /// library unless said otherwise).
  const DriverGlue({
    required this.package,
    required this.template,
    required this.beanName,
    required this.factory,
    this.type = 'JdbcDriver',
    this.typeUrl = _starterUrl,
    this.takesEnvironment = false,
    this.direct = false,
  });

  /// The dependency that switches it on (`sqlite3`).
  final String package;

  /// Whether [package] must be in the application's own pubspec (a driver)
  /// rather than reached in any way (a starter).
  final bool direct;

  /// The template's path inside the starter (`lib/src/jdbc/drivers/
  /// sqlite3.dart.tmpl`).
  final String template;

  /// The name of the bean (`sqlite3JdbcDriver`); a module registers it only
  /// when no bean of this name exists yet, so several modules of one
  /// application may all carry the glue.
  final String beanName;

  /// The top-level function of the template returning the bean.
  final String factory;

  /// The type the bean is registered under (`JdbcDriver`).
  final String type;

  /// The library [type] is imported from.
  final String typeUrl;

  /// Whether [factory] takes the context's `Environment` (the glue reads
  /// properties) instead of no argument.
  final bool takesEnvironment;
}

/// The drivers the starter has glue for.
const driverGlues = [
  DriverGlue(
    package: 'sqlite3',
    template: 'lib/src/jdbc/drivers/sqlite3.dart.tmpl',
    beanName: 'sqlite3JdbcDriver',
    factory: r'_$sqlite3JdbcDriver',
    direct: true,
  ),
  DriverGlue(
    package: 'postgres',
    template: 'lib/src/jdbc/drivers/postgres.dart.tmpl',
    beanName: 'postgresJdbcDriver',
    factory: r'_$postgresJdbcDriver',
    direct: true,
  ),
  // The web starter's HandlerExceptionResolver for data errors (409, 404);
  // the template, with the exceptions' names, is the data starter's.
  DriverGlue(
    package: 'spring_boot_starter_web',
    template: 'lib/src/web/data_access_exception_resolver.dart.tmpl',
    beanName: 'dataAccessExceptionResolver',
    factory: r'_$dataAccessExceptionResolver',
    type: 'HandlerExceptionResolver',
    typeUrl: _webUrl,
  ),
  // The web starter's resolver of `Pageable` and `Sort` controller
  // parameters (Spring Data Web's argument resolvers), a `WebMvcConfigurer`
  // reading `spring.data.web.*`.
  DriverGlue(
    package: 'spring_boot_starter_web',
    template: 'lib/src/web/paging_argument_resolver.dart.tmpl',
    beanName: 'pagingArgumentResolvers',
    factory: r'_$pagingArgumentResolvers',
    type: 'WebMvcConfigurer',
    typeUrl: _webUrl,
    takesEnvironment: true,
  ),
];

/// What the generator adds to a module for one driver.
final class DriverGlueOutput {
  /// The template's [code] and the bean [definition] using it.
  DriverGlueOutput(this.code, this.definition);

  /// The template with its placeholders resolved, as a top-level spec.
  final Spec code;

  /// The `BeanDefinition` for the module's list.
  final Expression definition;
}

// `{{package:sqlite3/sqlite3.dart#Database}}`, `{{dart:io#SecurityContext}}`
final _placeholder = RegExp(r'\{\{((?:package|dart):[^#{}\s]+)#(\w+)\}\}');

/// The glue of every entry of [driverGlues] that applies, provided the
/// data starter is reached and has the template. Otherwise nothing.
///
/// [dependencies] are the packages of the pubspec of the package being
/// built (its own), [reachable] those with everything they bring (the
/// packages whose auto-configurations the application gets); `null` when
/// unknown, and then only [dependencies] count.
///
/// - The data starter, and the web starter of the web glue, are looked for
///   in [reachable]: an application that lists `spring_boot_starter_supabase`
///   has the data starter without naming it. The generated code imports
///   the starter's library, which resolves for any package of the package
///   config.
/// - A driver package ([DriverGlue.direct]) is looked for in
///   [dependencies]: `postgres` that only arrives with another package is
///   not the application's choice.
///
/// Pass no [reachable] for the `lib/` of a published package: pub.dev
/// refuses a package whose `lib/` imports one that is not in its
/// `dependencies`.
Future<List<DriverGlueOutput>> driverGlueFor(
  BuildStep buildStep,
  Set<String>? dependencies, {
  Set<String>? reachable,
}) async {
  if (dependencies == null) {
    return const [];
  }
  final reached = reachable ?? dependencies;
  if (!reached.contains(_starterPackage)) {
    return const [];
  }
  final outputs = <DriverGlueOutput>[];
  for (final glue in driverGlues) {
    if (!(glue.direct ? dependencies : reached).contains(glue.package)) {
      continue;
    }
    final asset = AssetId(_starterPackage, glue.template);
    if (!await buildStep.canRead(asset)) {
      continue;
    }
    outputs.add(
      DriverGlueOutput(
        _resolve(await buildStep.readAsString(asset)),
        _definition(glue),
      ),
    );
  }
  return outputs;
}

/// [template] without its leading comment block (the documentation of the
/// template, up to the first blank line), its placeholders replaced by the
/// allocator's prefixed names.
Code _resolve(String template) {
  final lines = template.split('\n');
  var start = 0;
  while (start < lines.length && lines[start].startsWith('//')) {
    start++;
  }
  final body = lines.sublist(start).join('\n').trim();
  return Code.scope(
    (allocate) => body.replaceAllMapped(
      _placeholder,
      (match) => allocate(refer(match[2]!, match[1])),
    ),
  );
}

Expression _definition(DriverGlue glue) {
  final driver = refer(glue.type, glue.typeUrl);
  return refer('BeanDefinition', _springUrl).newInstance(
    [],
    {
      'name': literalString(glue.beanName, raw: true),
      'source': literalString(
        'package:spring_boot_starter_data#${glue.package}',
        raw: true,
      ),
      'types': literalConstList([driver]),
      'conditions': literalList([
        refer(
          'ConditionalOnMissingBean',
          _starterUrl,
        ).newInstanceNamed('named', [
          literalString(glue.beanName, raw: true),
        ]),
      ]),
      'create': Method(
        (m) => m
          ..requiredParameters.add(Parameter((p) => p..name = 'r'))
          ..lambda = true
          ..body = refer(glue.factory).call([
            if (glue.takesEnvironment)
              refer('r').property('dependency').call(
                [],
                {},
                [refer('Environment', _springUrl)],
              ),
          ]).code,
      ).closure,
    },
    [driver],
  );
}
