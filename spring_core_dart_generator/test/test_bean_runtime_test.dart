// `@TestBean(name: ...)` fakes in a test that really runs: the application
// and the test file are generated, written to a package on disk and the
// test file is run in a separate process, so the bean types the
// generated overrides give are those the context really sees.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart' show AssetId;
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/test_builder.dart';
import 'package:test/test.dart';

const _app = r'''
import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class PaymentGateway {
  String charge(double amount);
}

abstract interface class Auditable {
  String audit();
}

// The bean the tests replace: also an Auditable, which most fakes are not.
@Component('sandbox')
class RealGateway implements PaymentGateway, Auditable {
  @override
  String charge(double amount) => 'real $amount';

  @override
  String audit() => 'real';
}

@Component()
class Checkout {
  Checkout(this.gateway);

  final PaymentGateway gateway;
}

@Component()
class AuditLog {
  AuditLog(this.auditables);

  final List<Auditable> auditables;
}

class FakeGateway extends RealGateway {
  @override
  String charge(double amount) => 'fake $amount';
}

class PlainFake implements PaymentGateway {
  @override
  String charge(double amount) => 'plain $amount';
}
''';

const _main = '''
import 'package:pkg/app.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

// The reviewer's cases: each test class replaces 'sandbox' with a fake
// that is no Auditable (but the last), so the AuditLog must not get it.
const _test = r'''
import 'package:pkg/app.dart';
import 'package:pkg/app.dart' as p;
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'spring/shop.test.spring.dart';

// A dart:core supertype: the generated file imported dart:core with a
// prefix only and did not compile ('dynamic' isn't a type).
class RecordingGateway implements PaymentGateway, Sink<String> {
  final lines = <String>[];

  @override
  String charge(double amount) => 'recorded $amount';

  @override
  void add(String data) => lines.add(data);

  @override
  void close() {}
}

class _PrivateFake implements PaymentGateway {
  @override
  String charge(double amount) => 'private $amount';
}

abstract final class Fakes {
  // A static factory: its class is not known at build time.
  static PaymentGateway auditable() => FakeGateway();
}

@SpringBootTest()
class CoreSupertypeTest {
  @TestBean(name: 'sandbox')
  final PaymentGateway gateway = RecordingGateway();

  @Autowired()
  late Checkout checkout;

  @Autowired()
  late AuditLog log;

  @Test()
  void replaces() {
    expect(checkout.gateway, same(gateway));
    expect(log.auditables, isEmpty);
  }
}

@SpringBootTest()
class NullableCoreSupertypeTest {
  @TestBean(name: 'sandbox')
  final PaymentGateway? gateway = RecordingGateway();

  @Autowired()
  late Checkout checkout;

  @Autowired()
  late AuditLog log;

  @Test()
  void replaces() {
    expect(checkout.gateway, same(gateway));
    expect(log.auditables, isEmpty);
  }
}

@SpringBootTest()
class PrivateFakeTest {
  @TestBean(name: 'sandbox')
  final PaymentGateway gateway = _PrivateFake();

  @Autowired()
  late Checkout checkout;

  @Autowired()
  late AuditLog log;

  @Test()
  void replaces() {
    expect(checkout.gateway, same(gateway));
    expect(log.auditables, isEmpty);
  }
}

@SpringBootTest()
class PrefixedTest {
  @TestBean(name: 'sandbox')
  final p.PaymentGateway gateway = p.PlainFake();

  @Autowired()
  late p.AuditLog log;

  @Test()
  void replaces() => expect(log.auditables, isEmpty);
}

@SpringBootTest()
class CascadeTest {
  @TestBean(name: 'sandbox')
  final PaymentGateway gateway = (PlainFake()..charge(1));

  @Autowired()
  late AuditLog log;

  @Test()
  void replaces() => expect(log.auditables, isEmpty);
}

@SpringBootTest()
class InferredTest {
  @TestBean(name: 'sandbox')
  final gateway = PlainFake();

  @Autowired()
  late AuditLog log;

  @Test()
  void replaces() => expect(log.auditables, isEmpty);
}

// Keeps the replaced bean's types: the fake is an Auditable here.
@SpringBootTest()
class StaticFactoryTest {
  @TestBean(name: 'sandbox')
  final PaymentGateway gateway = Fakes.auditable();

  @Autowired()
  late AuditLog log;

  @Test()
  void keepsTheReplacedTypes() => expect(log.auditables, [same(gateway)]);
}

// A nullable type alias: the override did not compile (its nullability
// was read from the text); it replaces the bean of the alias's type.
typedef MaybeGateway = PaymentGateway?;

@SpringBootTest()
class NullableAliasTest {
  @TestBean()
  final MaybeGateway gateway = PlainFake();

  @Autowired()
  late Checkout checkout;

  @Autowired()
  late AuditLog log;

  @Test()
  void replaces() {
    expect(checkout.gateway, same(gateway));
    expect(log.auditables, isEmpty);
  }
}

void main() => runSpringTests();
''';

// dart:io types (declared in dart:_http) and the field's type of a
// `@TestBean(name:)` override. Every test class here failed to start:
// LoggingServer was not registered as an HttpServer, a FakeHttpClient
// not as an HttpClient, the fallback for a static factory dropped the
// replaced bean's declared type (Mailer) and a fake with a private type
// argument fell back to the replaced bean's types (Auditable).
const _ioApp = r"""
import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class Mailer {
  String send(String to);
}

class SmtpMailer implements Mailer {
  @override
  String send(String to) => 'smtp $to';
}

class LogMailer implements Mailer {
  @override
  String send(String to) => 'log $to';
}

abstract interface class Auditable {
  String audit();
}

class Book {
  const Book(this.title);

  final String title;
}

abstract interface class Repo<T> {
  List<T> all();
}

@Configuration()
class AppConfig {
  // Registered under its declared type only.
  @Bean()
  Mailer mailer(@Value(r'${mail.smtp:true}') bool smtp) =>
      smtp ? SmtpMailer() : LogMailer();

  @Bean()
  HttpClient httpClient() => HttpClient();
}

@Component()
class Shop {
  Shop(this.mailer, this.client);

  final Mailer mailer;
  final HttpClient client;
}

// A supertype declared in dart:_http.
@Component()
class LoggingServer implements HttpServer {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

@Component()
class ServerUser {
  ServerUser(this.server);

  final HttpServer server;
}

@Component('bookRepo')
class RealBookRepo implements Repo<Book>, Auditable {
  @override
  List<Book> all() => const [Book('real')];

  @override
  String audit() => 'repo';
}

@Component()
class Library {
  Library(this.repo, this.repos, this.auditables);

  final Repo<Book> repo;
  final List<Repo> repos;
  final List<Auditable> auditables;
}
""";

const _ioTest = r"""
import 'dart:io';

import 'package:pkg/app.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'spring/io.test.spring.dart';

class FakeHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeMailer implements Mailer {
  @override
  String send(String to) => 'fake $to';
}

// A supertype with a type argument declared in dart:_http.
class SinkMailer implements Mailer, Sink<HttpClientRequest> {
  @override
  String send(String to) => 'sink $to';

  @override
  void add(HttpClientRequest data) {}

  @override
  void close() {}
}

abstract final class Fakes {
  static Mailer mailer() => FakeMailer();
}

class _PrivateBook extends Book {
  const _PrivateBook() : super('private');
}

class FakeRepo<T> implements Repo<T> {
  const FakeRepo();

  @override
  List<T> all() => const [];
}

@SpringBootTest()
class HttpClientFakeTest {
  @TestBean(name: 'httpClient')
  final HttpClient client = FakeHttpClient();

  @Autowired()
  late Shop shop;

  @Autowired()
  late ServerUser user;

  @Test()
  void replaces() {
    expect(shop.client, same(client));
    expect(user.server, isA<LoggingServer>());
  }
}

@SpringBootTest()
class InternalTypeArgumentTest {
  @TestBean(name: 'mailer')
  final Mailer mailer = SinkMailer();

  @Autowired()
  late Shop shop;

  @Test()
  void replaces() => expect(shop.mailer, same(mailer));
}

@SpringBootTest()
class StaticFactoryOnBeanMethodTest {
  @TestBean(name: 'mailer')
  final Mailer mailer = Fakes.mailer();

  @Autowired()
  late Shop shop;

  @Test()
  void replaces() => expect(shop.mailer, same(mailer));
}

@SpringBootTest()
class PrivateTypeArgumentTest {
  @TestBean(name: 'bookRepo')
  final Repo<Book> repo = const FakeRepo<_PrivateBook>();

  @Autowired()
  late Library library;

  @Test()
  void replaces() {
    expect(library.repo, same(repo));
    expect(library.repos, [same(repo)]);
    expect(library.auditables, isEmpty);
  }
}

void main() => runSpringTests();
""";

// Generates the application and test of [sources], writes them to a
// package on disk and runs [testFile] in a separate process; the output.
Future<String> _runGenerated(
  Map<String, String> sources,
  String testFile,
) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilders(
    [SpringBuilder(), SpringTestBuilder()],
    {
      for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final directory = await Directory.systemTemp.createTemp('spring_fakes_');
  addTearDown(() => directory.delete(recursive: true));
  final files = {
    ...sources,
    for (final output in result.outputs)
      output.path: readerWriter.testing.readString(output),
  };
  expect(
    files.keys,
    contains(springTestOutput(AssetId('pkg', testFile)).path),
  );
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
  // package:test's runner: a test file run directly has no declarer for
  // the groups of spring_boot_starter_test.
  final runner = (await Isolate.resolvePackageUri(
    Uri.parse('package:test/test.dart'),
  ))!.resolve('../bin/test.dart');
  final process = await Process.run(
    Platform.resolvedExecutable,
    [
      '--packages=${directory.path}/.dart_tool/package_config.json',
      runner.toFilePath(),
      '--reporter=expanded',
      '--no-color',
      testFile,
    ],
    workingDirectory: directory.path,
  );
  final output = '${process.stdout}\n${process.stderr}';
  expect(process.exitCode, 0, reason: output);
  return output;
}

void main() {
  test(
    "@TestBean(name:) fakes get their class's types, run for real",
    () async {
      final output = await _runGenerated({
        'lib/app.dart': _app,
        'bin/main.dart': _main,
        'test/shop_test.dart': _test,
      }, 'test/shop_test.dart');
      expect(output, contains('+8: All tests passed!'), reason: output);
    },
  );

  test(
    "dart:io types and the field's type of a @TestBean(name:), run for real",
    () async {
      final output = await _runGenerated({
        'lib/app.dart': _ioApp,
        'bin/main.dart': _main,
        'test/io_test.dart': _ioTest,
      }, 'test/io_test.dart');
      expect(output, contains('+4: All tests passed!'), reason: output);
    },
  );
}
