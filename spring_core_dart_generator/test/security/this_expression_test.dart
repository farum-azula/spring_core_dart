// `this` in a security expression is the bean: the generated code describes
// it for what the expression reads, without @Introspected. The application
// is built, written out and run in its own process.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

const _library = '''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_security_core/spring_security_core.dart';

abstract class Owned {
  String get owner => 'ada';
}

class OwnerOnly extends PreAuthorize {
  const OwnerOnly() : super('this.owner == authentication.name');
}

@Service()
class Documents extends Owned {
  String tenant = 'acme';

  bool allows(String who) => who == authenticatedName;

  String get authenticatedName => 'ada';

  @PreAuthorize('this.owner == authentication.name')
  String inherited() => 'inherited';

  @PreAuthorize('this.tenant == "acme"')
  String field() => 'field';

  @PreAuthorize('this.allows(#who)')
  String method(String who) => 'method';

  @PreAuthorize('#root.this.tenant == "acme"')
  String throughRoot() => 'root';

  @OwnerOnly()
  String composed() => 'composed';
}
''';

const _main = r'''
import 'dart:convert';

import 'package:pkg/app.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/spring_security_core.dart';

import 'spring_gen/main.spring.dart';

String call(String Function() body) {
  try {
    return body();
  } on AuthorizationDeniedException {
    return 'denied';
  }
}

T as<T>(String name, T Function() body) {
  final user = User.withUsername(name).password(null).roles(['USER']).build();
  return SecurityContextHolder.runWithContext(
    body,
    SecurityContextImpl(
      UsernamePasswordAuthenticationToken.authenticated(
        user,
        null,
        user.authorities,
      ),
    ),
  );
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await runApplicationAsync([
    '--spring.main.banner-mode=off',
    '--logging.level.root=off',
    '--spring.main.web-application-type=none',
  ]);
  final docs = context.getBean<Documents>();
  List<String> all() => [
    call(docs.inherited),
    call(docs.field),
    call(() => docs.method('ada')),
    call(() => docs.method('bob')),
    call(docs.throughRoot),
    call(docs.composed),
  ];
  print('RESULT ${jsonEncode({'ada': as('ada', all), 'bob': as('bob', all)})}');
  context.close();
}
''';

Future<Object?> _run() async {
  final sources = {'lib/app.dart': _library, 'bin/main.dart': _main};
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(generations: packageGenerations),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final directory = await Directory.systemTemp.createTemp('spring_this_');
  addTearDown(() => directory.delete(recursive: true));
  final files = {
    ...sources,
    for (final output in result.outputs)
      output.path: readerWriter.testing.readString(output),
  };
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File('${directory.path}/$key');
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }
  final workspace = await loadPackageConfigUri((await Isolate.packageConfig)!);
  await savePackageConfig(
    PackageConfig([
      ...workspace.packages,
      Package(
        'pkg',
        directory.uri,
        packageUriRoot: directory.uri.resolve('lib/'),
      ),
    ]),
    directory,
  );
  final process = await Process.run(Platform.resolvedExecutable, [
    '--packages=${directory.path}/.dart_tool/package_config.json',
    '${directory.path}/bin/main.dart',
  ]);
  final output = '${process.stdout}';
  final line = LineSplitter.split(
    output,
  ).where((line) => line.startsWith('RESULT ')).firstOrNull;
  expect(line, isNotNull, reason: '$output\n${process.stderr}');
  return jsonDecode(line!.substring('RESULT '.length));
}

void main() {
  test('this reads the bean, with no @Introspected on it', () async {
    expect(await _run(), {
      'ada': ['inherited', 'field', 'method', 'denied', 'root', 'composed'],
      'bob': ['denied', 'field', 'method', 'denied', 'root', 'denied'],
    });
  });
}
