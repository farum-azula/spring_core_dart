// The in-memory builds the core's tests share (test/core/): a package
// `pkg` with a scan root, built by the main builder with every starter's
// part, its output read back without the formatter's choices.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

import 'module_files.dart';

export 'module_files.dart';

/// The scan root of `pkg`: its beans are those of `lib/src/`.
const scanRoot = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

/// The import of the container's annotations a source starts with.
const coreImport = "import 'package:spring_core_dart/spring_core_dart.dart';\n";

/// Builds [sources] (paths below `pkg|`) with the main builder.
Future<TestBuilderResult> buildPackage(
  Map<String, Object> sources, {
  ProxyMode proxyMode = ProxyMode.none,
  bool prune = true,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(
      generations: packageGenerations,
      proxyMode: proxyMode,
      pruneProxies: prune,
    ),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

/// Builds a scan root plus [beans] and returns the generated source without
/// whitespace (the formatter may wrap lines).
Future<String> generateModule(
  String beans, {
  Map<String, Object> extra = const {},
  ProxyMode proxyMode = ProxyMode.none,
  bool prune = true,
}) async {
  final result = await buildPackage(
    {
      'lib/src/beans.dart': scanRoot,
      'lib/src/service.dart': '$coreImport$beans',
      ...extra,
    },
    proxyMode: proxyMode,
    prune: prune,
  );
  expect(result.errors, isEmpty);
  return normalize(moduleText(result));
}

/// Drops whitespace, trailing commas (formatter choices) and import
/// prefixes (``, whose numbers depend on the order of first use).
String normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

/// Matches an output holding [code], whitespace and trailing commas aside.
Matcher hasCode(String code) => contains(normalize(code));

/// Like [generateModule] for an application (`@SpringBootApplication` in
/// `bin/main.dart`, [beans] in `lib/src/service.dart`): the only output
/// that prunes proxies.
Future<String> generateApplication(
  String beans, {
  Map<String, Object> extra = const {},
  ProxyMode proxyMode = ProxyMode.all,
  bool prune = true,
}) async {
  final result = await buildPackage(
    {
      'bin/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''',
      'lib/src/service.dart': '$coreImport$beans',
      ...extra,
    },
    proxyMode: proxyMode,
    prune: prune,
  );
  expect(result.errors, isEmpty);
  return normalize(
    moduleText(result, AssetId('pkg', 'bin/spring_gen/main.spring.dart')),
  );
}

/// Builds the scan root plus [beans] and expects the build to fail with
/// [message].
Future<void> expectBuildError(
  String beans,
  String message, {
  ProxyMode proxyMode = ProxyMode.none,
}) async {
  final result = await buildPackage({
    'lib/src/beans.dart': scanRoot,
    'lib/src/service.dart': '$coreImport$beans',
  }, proxyMode: proxyMode);
  expect(result.succeeded, isFalse);
  expect(result.errors.join('\n'), contains(message));
}

/// Builds [files] (with the scan root) and returns the analyzer errors of
/// the generated library, resolved together with the real runtime: the
/// generated code must compile, not just look right.
Future<List<String>> compileErrors(
  Map<String, String> files, {
  ProxyMode proxyMode = ProxyMode.all,
}) async {
  final sources = {
    'lib/src/beans.dart': scanRoot,
    for (final MapEntry(:key, :value) in files.entries)
      key: '$coreImport$value',
  };
  final result = await buildPackage(sources, proxyMode: proxyMode);
  expect(result.errors, isEmpty);
  final generated = moduleFiles(result);
  return await resolveSources<List<String>>(
    {
      for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value,
      for (final file in generated)
        '$file': result.readerWriter.testing.readString(file),
    },
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('pkg', 'lib/spring_gen/src/beans.spring.dart'),
      );
      return [
        // The library, its part and the libraries of its descriptions.
        if (await moduleErrors(library) case ErrorsResult(:final diagnostics))
          for (final diagnostic in diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic.message,
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|lib/spring_gen/src/beans.spring.dart',
    readAllSourcesFromFilesystem: true,
  );
}
