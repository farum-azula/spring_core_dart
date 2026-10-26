// Annotations of test classes, Spring's way of writing tests:
//
//   @SpringBootTest()
//   class CheckoutTest {
//     @Autowired()
//     late Checkout checkout;
//
//     @Test()
//     void pays() => ...;
//   }
//
//   void main() => runSpringTests();
//
// They carry no behaviour: spring_core_dart_generator reads them from the
// test file and writes `<name>.test.spring.dart` with `runSpringTests()`,
// which declares the tests with springBootTest, group, test, setUp and
// tearDown (see docs/testing.md).

import 'package:test_api/scaffolding.dart' show Timeout;

/// A class of tests run against the application, like Spring's
/// `@SpringBootTest`: the context starts once for the class and its
/// `@Autowired` fields are set from it.
///
/// ```dart
/// @SpringBootTest(args: ['--shop.name=Night Books'])
/// class CheckoutTest { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @SpringBootTest(args = "--shop.name=Night Books")
/// class CheckoutTest { ... }
/// ```
final class SpringBootTest {
  /// The test class's application and how it starts.
  const SpringBootTest({
    this.application,
    this.args = const [],
    this.properties = const {},
    this.resourceDirectories = const ['test/resources'],
  });

  /// The entry point of the application, relative to the package
  /// (`bin/admin.dart`, `lib/main.dart`); only needed when the package has
  /// several `@SpringBootApplication` entry points. Spring names the
  /// application's class (`classes`); an annotation argument must be a
  /// constant, so here it is the file.
  final String? application;

  /// The command-line arguments.
  final List<String> args;

  /// Properties that win over every config file
  /// (`@SpringBootTest(properties = ...)`).
  final Map<String, Object?> properties;

  /// Directories first on the classpath during the tests, like
  /// `src/test/resources`.
  final List<String> resourceDirectories;
}

/// The profiles of the test class's context (`spring.profiles.active`),
/// like Spring's `@ActiveProfiles`.
///
/// ```dart
/// @SpringBootTest()
/// @ActiveProfiles(['dev', 'test'])
/// class CheckoutTest { ... }
/// ```
final class ActiveProfiles {
  /// Activates [profiles].
  const ActiveProfiles(this.profiles);

  /// The profiles, in order.
  final List<String> profiles;
}

/// Test properties, inline or from files, like Spring's
/// `@TestPropertySource`.
///
/// ```dart
/// @TestPropertySource(
///   locations: ['test/resources/big-shop.properties'],
///   properties: {'shop.max-basket-size': 100},
/// )
/// ```
final class TestPropertySource {
  /// Adds [properties] and the files at [locations].
  const TestPropertySource({
    this.properties = const {},
    this.locations = const [],
  });

  /// Properties that win over every config file.
  final Map<String, Object?> properties;

  /// `.properties` files (resource locations, later ones win).
  final List<String> locations;
}

/// The environment variables of the test class's context, in place of the
/// machine's (which tests never see). Spring has no such annotation.
///
/// ```dart
/// @TestEnvironment({'SHOP_MAX_BASKET_SIZE': '25'})
/// ```
final class TestEnvironment {
  /// Uses [variables] as the environment.
  const TestEnvironment(this.variables);

  /// The variables by name.
  final Map<String, String> variables;
}

/// A static method adding properties whose values are known only when the
/// context starts, like Spring's `@DynamicPropertySource`. It takes a
/// `DynamicPropertyRegistry`.
///
/// ```dart
/// @DynamicPropertySource()
/// static void serverUrl(DynamicPropertyRegistry registry) =>
///     registry.add('shop.payments.url', () => server.url);
/// ```
final class DynamicPropertySource {
  /// Marks the method.
  const DynamicPropertySource();
}

/// A static method run on the context before it is refreshed, like an
/// `ApplicationContextInitializer` of Spring's `@ContextConfiguration`. It
/// takes a `ConfigurableApplicationContext`.
///
/// ```dart
/// @ContextInitializer()
/// static void register(ConfigurableApplicationContext context) => ...;
/// ```
final class ContextInitializer {
  /// Marks the method.
  const ContextInitializer();
}

/// A field whose value replaces a bean of the application before the
/// context starts, like Spring's `@TestBean` and `@MockitoBean`.
///
/// Which bean: the one called [name] (keeping its types), else the only
/// bean of [type], else of the field's declared type. Without such a bean
/// the value is added as a new bean.
///
/// ```dart
/// @TestBean(name: 'sandbox')
/// final gateway = FakeGateway();
///
/// @TestBean()
/// final Clock clock = FixedClock(DateTime(2026));
/// ```
final class TestBean {
  /// Replaces the bean called [name], or the bean of [type].
  const TestBean({this.name, this.type});

  /// The bean (or alias) to replace.
  final String? name;

  /// The type of the bean to replace, when not the field's declared type.
  final Type? type;
}

/// The context is closed after the test (on a method) or after every test
/// of the class (on the class); the next test gets a new one, like
/// Spring's `@DirtiesContext`.
final class DirtiesContext {
  /// Marks the test or the class.
  const DirtiesContext();
}

/// A test method, like JUnit's `@Test`. Without [name], the test is named
/// after the method (`paysThroughTheFake` → `pays through the fake`). A
/// method returning a `Future` is awaited. `@Disabled`, `@Tag` and
/// `@TestOptions` add `test()`'s other options.
final class Test {
  /// A test named [name] (or after the method).
  const Test([this.name]);

  /// The test's name.
  final String? name;
}

/// `test()`'s remaining options for a test method (or, on the class, for
/// all its tests). `package:test`'s `@Timeout`, `@Retry`, `@TestOn` and
/// `@OnPlatform` can only annotate a library, so they are here.
///
/// ```dart
/// @Test()
/// @TestOptions(timeout: Timeout(Duration(seconds: 5)), retry: 2)
/// Future<void> paysOnline() async => ...;
/// ```
final class TestOptions {
  /// The options; `null` leaves `test()`'s default.
  const TestOptions({this.timeout, this.retry, this.testOn, this.onPlatform});

  /// How long the test may run (`test(timeout:)`).
  final Timeout? timeout;

  /// How many times a failing test is run again (`test(retry:)`).
  final int? retry;

  /// A platform selector such as `'vm'` (`test(testOn:)`).
  final String? testOn;

  /// Options per platform selector (`test(onPlatform:)`).
  final Map<String, Object?>? onPlatform;
}

/// A test (on a method) or every test of a class that is skipped, like
/// JUnit's `@Disabled`; [reason] is shown in the test output.
final class Disabled {
  /// Skips with [reason].
  const Disabled([this.reason]);

  /// Why it is skipped.
  final String? reason;
}

/// A tag of a test (on a method) or of every test of a class, for
/// `dart test --tags` / `--exclude-tags`, like JUnit's `@Tag`; several may
/// be given.
final class Tag {
  /// Tags with [name].
  const Tag(this.name);

  /// The tag.
  final String name;
}

/// The name of a test, like JUnit's `@DisplayName`; the same as
/// `@Test(name)`.
final class DisplayName {
  /// Names the test [name].
  const DisplayName(this.name);

  /// The test's name.
  final String name;
}

/// A static method run once before the class's context starts, like
/// JUnit's `@BeforeAll`.
final class BeforeAll {
  /// Marks the method.
  const BeforeAll();
}

/// A method run before every test, with the beans injected, like JUnit's
/// `@BeforeEach`.
final class BeforeEach {
  /// Marks the method.
  const BeforeEach();
}

/// A method run after every test, before a `@DirtiesContext` restart, like
/// JUnit's `@AfterEach`.
final class AfterEach {
  /// Marks the method.
  const AfterEach();
}

/// A static method run once after the class's context is closed, like
/// JUnit's `@AfterAll`.
final class AfterAll {
  /// Marks the method.
  const AfterAll();
}

/// A field holding a class of tests run as a group with the outer class's
/// context and beans, like JUnit's `@Nested` inner classes. The class must
/// be declared in the same file.
///
/// ```dart
/// @Nested('with one book')
/// final withOneBook = WithOneBook();
/// ```
final class Nested {
  /// A group named [name] (or after the field).
  const Nested([this.name]);

  /// The group's name.
  final String? name;
}

/// A `late CapturedLogs` field that records what is logged during each
/// test, like Spring Boot's `OutputCaptureExtension`.
///
/// ```dart
/// @CapturedOutput()
/// late CapturedLogs logs;
/// ```
final class CapturedOutput {
  /// Marks the field.
  const CapturedOutput();
}
