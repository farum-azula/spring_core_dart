import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';

// The package whose assets hold the templates, and the library everything
// the glue and its bean definition name is imported from.
const _starterPackage = 'spring_boot_starter_data';
const _starterUrl =
    'package:spring_boot_starter_data/spring_boot_starter_data.dart';
const _springUrl = 'package:spring_core_dart/spring_core_dart.dart';

/// A database driver package that `spring_boot_starter_data` has glue for.
///
/// The starter cannot depend on a driver package (`sqlite3` bundles a
/// native library, and pub has no optional dependencies). The application
/// lists the one it wants; seeing it among the application's dependencies,
/// the generator copies the starter's template for it into the generated
/// module, and registers a `JdbcDriver` bean made by it. Spring Boot does
/// the same with `@ConditionalOnClass` on the JDBC driver.
///
/// Spring (Java): the driver jar on the classpath that
/// `DataSourceAutoConfiguration` finds by its class.
final class DriverGlue {
  /// The glue for the package [package]: [template] is its asset in the
  /// starter, [beanName] the bean it makes and [factory] the function of
  /// the template that creates the driver.
  const DriverGlue({
    required this.package,
    required this.template,
    required this.beanName,
    required this.factory,
  });

  /// The dependency that switches it on (`sqlite3`).
  final String package;

  /// The template's path inside the starter (`lib/src/jdbc/drivers/
  /// sqlite3.dart.tmpl`).
  final String template;

  /// The name of the `JdbcDriver` bean; a module registers it only when no
  /// bean of this name exists yet, so several modules of one application
  /// may all carry the glue.
  final String beanName;

  /// The top-level function of the template returning the `JdbcDriver`.
  final String factory;
}

/// The drivers the starter has glue for. `postgres` is added here.
const driverGlues = [
  DriverGlue(
    package: 'sqlite3',
    template: 'lib/src/jdbc/drivers/sqlite3.dart.tmpl',
    beanName: 'sqlite3JdbcDriver',
    factory: r'_$sqlite3JdbcDriver',
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

// `{{package:sqlite3/sqlite3.dart#Database}}`
final _placeholder = RegExp(r'\{\{package:([^#{}\s]+)#(\w+)\}\}');

/// The glue of every driver in [driverGlues] whose package is among
/// [dependencies] (the application's own), provided the application also
/// depends on the starter and the starter has the template. Otherwise
/// nothing.
///
/// The application must depend on the starter itself (not only reach it
/// through another package): the glue imports the starter's library.
Future<List<DriverGlueOutput>> driverGlueFor(
  BuildStep buildStep,
  Set<String>? dependencies,
) async {
  if (dependencies == null || !dependencies.contains(_starterPackage)) {
    return const [];
  }
  final outputs = <DriverGlueOutput>[];
  for (final glue in driverGlues) {
    if (!dependencies.contains(glue.package)) {
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
      (match) => allocate(refer(match[2]!, 'package:${match[1]}')),
    ),
  );
}

Expression _definition(DriverGlue glue) {
  final driver = refer('JdbcDriver', _starterUrl);
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
          ..body = refer(glue.factory).call([]).code,
      ).closure,
    },
    [driver],
  );
}
