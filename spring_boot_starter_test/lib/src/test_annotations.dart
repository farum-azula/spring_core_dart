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

import 'package:spring_boot_starter_test/src/spring_boot_test.dart'
    show WebEnvironment;
import 'package:test_api/scaffolding.dart' show Timeout;

/// Marks a class whose tests run against the whole application: the
/// application starts before the first test, and the class's
/// `@Autowired()` fields are set from it.
///
/// Use it when a test needs the real wiring: a service with its
/// repositories, properties bound from the config files, controllers
/// behind `MockMvc`. The context starts once and all tests of the class
/// share it (see [DirtiesContext] to restart it). A unit test that creates
/// its objects by hand needs no annotation.
///
/// The annotation does nothing at run time. `spring_core_dart_generator`
/// reads the class and writes `test/spring/<name>.test.spring.dart`, whose
/// `runSpringTests()` declares the tests with `springBootTest`; the test
/// file's `main` calls it. The other annotations of this file set the
/// remaining options: [ActiveProfiles], [TestPropertySource], [TestBean],
/// [Test] and so on.
///
/// ```dart
/// import 'spring/checkout.test.spring.dart'; // generated
///
/// // The shop starts with a test name; the test uses its real Checkout.
/// @SpringBootTest(args: ['--shop.name=Night Books'])
/// class CheckoutTest {
///   @Autowired()
///   late Checkout checkout;
///
///   @Test()
///   void paysThroughTheGateway() => expect(checkout.pay(3), isNotNull);
/// }
///
/// void main() => runSpringTests();
/// ```
///
/// Spring (Java):
/// ```java
/// @SpringBootTest(args = "--shop.name=Night Books")
/// class CheckoutTest { ... }
/// ```
final class SpringBootTest {
  /// Every option has a default: `@SpringBootTest()` alone starts the
  /// package's only application, without arguments, with
  /// `test/resources/` on the classpath and no web server.
  const SpringBootTest({
    this.application,
    this.args = const [],
    this.properties = const {},
    this.resourceDirectories = const ['test/resources'],
    this.webEnvironment = WebEnvironment.mock,
  });

  /// Which web server the tests get when the application uses
  /// `spring_boot_starter_web`.
  ///
  /// [WebEnvironment.mock] (the default) starts none: the tests call the
  /// controllers in memory through an `@Autowired() late MockMvc mvc;`
  /// field. [WebEnvironment.randomPort] starts a real server on a free
  /// port, for clients that need a socket; a [LocalServerPort] field
  /// receives the port.
  final WebEnvironment webEnvironment;

  /// The entry point of the application to start, as a path in the package
  /// (`bin/admin.dart`, `lib/main.dart`).
  ///
  /// Leave it `null` when the package has one `@SpringBootApplication`
  /// entry point. With several, the build fails and asks for it; it also
  /// fails when the path is not such an entry point. Spring names the
  /// application's class (`classes`); an annotation argument must be a
  /// constant, and the generated `springApplication` is not, so here it is
  /// the file.
  final String? application;

  /// The command-line arguments the application starts with, such as
  /// `--shop.name=Night Books`. They win over the config files and the
  /// environment, not over [properties]. Empty by default.
  final List<String> args;

  /// Properties for the tests, which win over the config files, the
  /// environment and [args] (Spring's `@SpringBootTest(properties = ...)`).
  ///
  /// Only `@DynamicPropertySource` values win over them. Merged with the
  /// `properties` of a [TestPropertySource]; on the same key, those win.
  /// Empty by default.
  final Map<String, Object?> properties;

  /// Directories put first on the classpath while the tests run, like
  /// `src/test/resources` in a Java project.
  ///
  /// Config files and `classpath:` resources are looked up there before
  /// the application's `lib/resources/`: put `application-test.properties`
  /// or test data there. A file with the same path as one in
  /// `lib/resources/` hides it entirely. Relative paths are resolved
  /// against the package of the test file; the first directory listed
  /// comes first. They are never embedded into the application. Default:
  /// `['test/resources']`.
  final List<String> resourceDirectories;
}

/// Sets the profiles that are active while the test class's application
/// runs.
///
/// Use it to load test-only configuration: with `['test']`, the file
/// `application-test.properties` (or `.yml`) is read on top of
/// `application.properties`, and beans marked `@Profile(['test'])` are
/// created. The list replaces `spring.profiles.active` of the config
/// files, so name the application's own profiles too if the tests need
/// them.
///
/// ```dart
/// // The dev beans, plus the settings of application-test.yml.
/// @SpringBootTest()
/// @ActiveProfiles(['dev', 'test'])
/// class CheckoutTest { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @SpringBootTest
/// @ActiveProfiles({"dev", "test"})
/// class CheckoutTest { ... }
/// ```
final class ActiveProfiles {
  /// Activates [profiles] for the class's application.
  const ActiveProfiles(this.profiles);

  /// The profile names, in order; they become `spring.profiles.active`.
  final List<String> profiles;
}

/// Adds properties for the test class's application, written inline or
/// read from `.properties` files.
///
/// Use it for settings only the tests need, such as a smaller limit or the
/// URL of a local fake, without creating a test profile. Both kinds win
/// over the config files, the environment and the command line;
/// [properties] win over [locations]. A file that does not exist fails the
/// start of the context.
///
/// ```dart
/// // A bigger basket than in production, plus the settings of a file.
/// @SpringBootTest()
/// @TestPropertySource(
///   locations: ['classpath:big-shop.properties'], // test/resources/
///   properties: {'shop.max-basket-size': 100},
/// )
/// class BasketTest { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @SpringBootTest
/// @TestPropertySource(
///     locations = "classpath:big-shop.properties",
///     properties = "shop.max-basket-size=100")
/// class BasketTest { ... }
/// ```
final class TestPropertySource {
  /// Adds [properties] and the files at [locations]; both empty by
  /// default.
  const TestPropertySource({
    this.properties = const {},
    this.locations = const [],
  });

  /// Inline properties. They are merged with the `properties` of
  /// [SpringBootTest]; on the same key, these win.
  final Map<String, Object?> properties;

  /// Resource locations of `.properties` files, such as
  /// `classpath:big-shop.properties` (found in `test/resources/` first).
  /// When two files set the same key, the later file wins.
  final List<String> locations;
}

/// Sets the environment variables that the test class's application sees,
/// in place of the machine's.
///
/// Without it the environment is empty, so a test never depends on the
/// variables of the machine it runs on. Use it to test settings that
/// normally come from variables, such as `SHOP_MAX_BASKET_SIZE`, which
/// binds to `shop.max-basket-size`. Spring has no such annotation: its
/// tests see the real environment.
///
/// ```dart
/// // The limit comes from a variable, as on the production server.
/// @SpringBootTest()
/// @TestEnvironment({'SHOP_MAX_BASKET_SIZE': '25'})
/// class BasketLimitTest { ... }
/// ```
final class TestEnvironment {
  /// Uses [variables] as the whole environment.
  const TestEnvironment(this.variables);

  /// The variables by name, as strings, as the operating system gives
  /// them.
  final Map<String, String> variables;
}

/// Marks a static method that adds properties whose values are known only
/// when the tests run, such as the URL of a server the test started.
///
/// The method takes a `DynamicPropertyRegistry` and registers one value
/// supplier per property. It is called each time the context starts, and
/// each supplier each time the property is read, so a value can come from
/// a server started in a [BeforeAll] method. These values win over every
/// other property source. The method must be static, because it runs
/// before the test class is created. When a class has several, all of
/// them are called.
///
/// ```dart
/// static final server = FakePaymentServer();
///
/// @BeforeAll()
/// static Future<void> startServer() => server.start();
///
/// // The application calls the fake server instead of the real provider.
/// @DynamicPropertySource()
/// static void serverUrl(DynamicPropertyRegistry registry) =>
///     registry.add('shop.payments.url', () => server.url);
/// ```
///
/// Spring (Java):
/// ```java
/// @DynamicPropertySource
/// static void serverUrl(DynamicPropertyRegistry registry) {
///   registry.add("shop.payments.url", server::url);
/// }
/// ```
final class DynamicPropertySource {
  /// Marks the method.
  const DynamicPropertySource();
}

/// Marks a static method that changes the test class's context before it
/// is refreshed, that is before any bean is created.
///
/// The method takes a `ConfigurableApplicationContext`. Use it for setup
/// that the other annotations cannot express, such as adding a bean
/// factory post-processor or a property source. Most tests need
/// [TestBean] or [TestPropertySource] instead. The method must be static.
///
/// ```dart
/// // Makes the slow reports bean lazy, so the tests start faster.
/// @ContextInitializer()
/// static void lazyReports(ConfigurableApplicationContext context) =>
///     context.addBeanFactoryPostProcessor(LazyReports());
/// ```
///
/// Spring (Java): an `ApplicationContextInitializer` named in
/// `@ContextConfiguration(initializers = ...)`.
final class ContextInitializer {
  /// Marks the method.
  const ContextInitializer();
}

/// Marks a field whose value replaces one of the application's beans while
/// the test class runs: a fake gateway, a fixed clock, a mock.
///
/// Use it when the real bean talks to something a test cannot use, such as
/// a payment provider, the wall clock or a mail server. The real bean's
/// definition is removed before any bean is created, so the real object is
/// never built, and every bean that injects it gets the field's value. The
/// test reads the same object through the field, with its own class, to
/// check what happened.
///
/// Which bean is replaced:
/// - with [type]: the bean called [name] if given, else the bean of that
///   type (the `@Primary` one when there are several);
/// - with only [name]: the bean (or alias) of that name. The value is
///   registered under the field's type, as in Spring (unless it is
///   `Object`), under the class of the value, and under more types. A
///   value created with a constructor (`FakeGateway()`, also `new` or
///   `const`, a named or private class's constructor, an import prefix,
///   in parentheses or followed by a cascade `..`) adds that class and all
///   its public supertypes, whatever the field's declared type, as the
///   generator registers a bean of that class: a `SubGateway extends
///   RealGateway` stays a `RealGateway` and keeps every interface of it,
///   and a fake `HttpClient` stays an `HttpClient` (written through
///   `dart:io`, which exports it). A type with a private class as a type
///   argument cannot be written in the generated file and counts in its
///   raw form only (`FakeRepo<_Draft>()` is a `Repo<dynamic>`, not a
///   `Repo<_Draft>`). Any other value (a function or static method call
///   such as `Fakes.gateway()`, which may return any subclass, a
///   variable), a class that cannot be resolved, or another type that
///   cannot be written there (a function or record type argument) adds
///   the types the replaced bean was registered under instead, except its
///   own class (unless the field has that type);
/// - with neither: the bean of the field's declared type, which must be
///   written (`final Clock clock = ...`, not `final clock = ...`).
///
/// Without such a bean, the value is added as a new bean. The field needs
/// a value and belongs to the `@SpringBootTest()` class, not to a [Nested]
/// one; a nullable field (`final Clock? clock = ...`, also of a nullable
/// type alias such as `typedef MaybeClock = Clock?;`) that is `null` when
/// the tests are declared fails the test file with a `StateError`. The
/// value is created once with the test class: when tests change its
/// state, reset it in a [BeforeEach] method. Mocks of any library (such as
/// `mocktail`) work as values; this package has no mocking library of its
/// own.
///
/// ```dart
/// @SpringBootTest()
/// class PaymentTest {
///   // Replaces the PaymentGateway called 'sandbox': no real payment.
///   @TestBean(name: 'sandbox')
///   final gateway = FakeGateway();
///
///   // Replaces the only Clock, so the dates in the tests are fixed.
///   @TestBean()
///   final Clock clock = FixedClock(DateTime(2026));
///
///   @Autowired()
///   late Checkout checkout;
///
///   @Test()
///   void paysThroughTheFake() {
///     checkout.pay(12.5);
///     expect(gateway.charged, [12.5]);
///   }
/// }
/// ```
///
/// Spring (Java): `@TestBean` and `@MockitoBean`. Here the value is the
/// field's own initializer, and no mock is generated.
final class TestBean {
  /// Without arguments, the field's declared type chooses the bean.
  const TestBean({this.name, this.type});

  /// The name or an alias of the bean to replace. When no bean has that
  /// name, the value is added under it.
  final String? name;

  /// The type of the bean to replace, when the field is declared with
  /// another type (the field is a `FakeGateway`, the bean a
  /// `PaymentGateway`). The value is then registered under this type
  /// only.
  final Type? type;
}

/// Marks a test that leaves the application in a state that later tests
/// must not see: the context is closed after the test, and the next test
/// gets a new one.
///
/// One context serves all the tests of a class, which keeps them fast.
/// When a test changes the state of a bean (a counter, an in-memory store,
/// a cache), mark it. On a method it applies to that test; on the class,
/// to each of its tests; on a [Nested] field, to each test of the group.
/// After the restart the `@Autowired()` fields are set again with the new
/// beans. [AfterEach] methods run before the context is closed.
///
/// ```dart
/// @Test()
/// @DirtiesContext() // the next test sees a counter at zero again
/// void counts() {
///   counter.increment();
///   expect(counter.value, 1);
/// }
/// ```
///
/// Spring (Java): `@DirtiesContext`. On a class it means Spring's
/// `classMode = AFTER_EACH_TEST_METHOD`, not Spring's default
/// `AFTER_CLASS`: each test class has its own context, closed after its
/// tests anyway. In a test written as a function, call `app.markDirty()`
/// instead.
final class DirtiesContext {
  /// Marks the test or the class.
  const DirtiesContext();
}

/// Marks a method of a test class as a test.
///
/// The test is named [name], or else after the method, split into words
/// (`paysThroughTheFake` becomes `pays through the fake`). A method that
/// returns a `Future` is awaited. It takes no parameters and must not be
/// static. Tests run in the order of the methods in the class.
/// [Disabled], [Tag], [DisplayName] and [TestOptions] set the other
/// options of `package:test`'s `test()`.
///
/// ```dart
/// @Test('an empty basket costs nothing')
/// void emptyBasket() => expect(basket.total, 0);
/// ```
///
/// Spring (Java): JUnit's `@Test`.
final class Test {
  /// Without [name], the test is named after the method.
  const Test([this.name]);

  /// The name shown in the test output and matched by
  /// `dart test --name`; `null` names the test after the method. A
  /// [DisplayName] on the same method wins.
  final String? name;
}

/// Sets the remaining options of `package:test`'s `test()` for a test
/// method, or for every test of a class or [Nested] group.
///
/// `package:test`'s own `@Timeout`, `@Retry`, `@TestOn` and `@OnPlatform`
/// can only annotate a whole library; this annotation brings them to a
/// single test. An option left `null` keeps `test()`'s default.
///
/// ```dart
/// // The payment sandbox is slow and flaky: allow 5 s and two more tries.
/// @Test()
/// @TestOptions(timeout: Timeout(Duration(seconds: 5)), retry: 2)
/// Future<void> paysOnline() async => ...;
/// ```
final class TestOptions {
  /// Every option is `null` by default, which keeps `test()`'s default.
  const TestOptions({this.timeout, this.retry, this.testOn, this.onPlatform});

  /// How long the test may run before it fails (`test(timeout:)`).
  final Timeout? timeout;

  /// How many more times a failing test is run before it counts as failed
  /// (`test(retry:)`).
  final int? retry;

  /// A platform selector such as `'vm'` or `'browser'`; on the other
  /// platforms the test is skipped (`test(testOn:)`).
  final String? testOn;

  /// Options per platform selector, such as
  /// `{'browser': Timeout.factor(2)}` (`test(onPlatform:)`).
  final Map<String, Object?>? onPlatform;
}

/// Skips a test method, or every test of a class or [Nested] group. The
/// test still shows in the output, as skipped, with [reason].
///
/// ```dart
/// @Test()
/// @Disabled('the payment sandbox is down')
/// Future<void> paysOnline() async => ...;
/// ```
///
/// Spring (Java): JUnit's `@Disabled`.
final class Disabled {
  /// Skips with [reason], if given.
  const Disabled([this.reason]);

  /// Why the test is skipped, shown in the test output.
  final String? reason;
}

/// Tags a test method, or every test of a class or [Nested] group, so that
/// a run can select or leave out those tests: `dart test --tags slow`,
/// `dart test --exclude-tags slow`. Several `@Tag`s may be given.
///
/// ```dart
/// @Test()
/// @Tag('slow')
/// Future<void> importsTheWholeCatalog() async => ...;
/// ```
///
/// Spring (Java): JUnit's `@Tag`.
final class Tag {
  /// Tags with [name].
  const Tag(this.name);

  /// The tag, as written after `--tags`.
  final String name;
}

/// Names a test in the output: the same as `@Test('name')`, in JUnit's
/// spelling. When both are given, this one wins.
///
/// Spring (Java): JUnit's `@DisplayName`.
final class DisplayName {
  /// Names the test [name].
  const DisplayName(this.name);

  /// The test's name.
  final String name;
}

/// Marks a static method that runs once, before the class's context
/// starts.
///
/// Use it to start what the application needs at startup, such as a fake
/// server whose URL a [DynamicPropertySource] method hands over. It must be
/// static, since no test class or bean exists yet. A returned `Future` is
/// awaited; several such methods run in the order of the class.
///
/// Spring (Java): JUnit's `@BeforeAll`.
final class BeforeAll {
  /// Marks the method.
  const BeforeAll();
}

/// Marks a method that runs before every test, after the `@Autowired()`
/// fields were set, so it can prepare beans (empty a store, add test
/// data).
///
/// In a [Nested] class it runs after the outer class's methods. A returned
/// `Future` is awaited.
///
/// ```dart
/// @BeforeEach()
/// void clear() => orders.clear(); // each test starts without orders
/// ```
///
/// Spring (Java): JUnit's `@BeforeEach`.
final class BeforeEach {
  /// Marks the method.
  const BeforeEach();
}

/// Marks a method that runs after every test, before a restart asked for
/// by [DirtiesContext].
///
/// Use it to undo what a test changed when restarting the context would
/// be slower. A returned `Future` is awaited.
///
/// Spring (Java): JUnit's `@AfterEach`.
final class AfterEach {
  /// Marks the method.
  const AfterEach();
}

/// Marks a static method that runs once, after the class's context is
/// closed: the place to stop what a [BeforeAll] method started.
///
/// Spring (Java): JUnit's `@AfterAll`.
final class AfterAll {
  /// Marks the method.
  const AfterAll();
}

/// Marks a field that holds another class of tests, run as a group inside
/// the outer class, with the same context and beans.
///
/// Use it to group tests that share a setup, such as "with one book in the
/// basket": the nested class has its own [BeforeEach] methods, which run
/// after the outer ones. Dart has no inner classes, so the group is a
/// field whose value is an instance of a class declared in the same file.
/// [Disabled], [Tag], [TestOptions] and [DirtiesContext] on the field (or
/// on the nested class) apply to the whole group. [TestBean] fields are not
/// allowed in the nested class: the context belongs to the outer one.
///
/// ```dart
/// @SpringBootTest()
/// class BasketTest {
///   @Nested('with one book')
///   final withOneBook = WithOneBook();
/// }
///
/// class WithOneBook {
///   @Autowired()
///   late Basket basket; // the same bean as in the outer class
///
///   @BeforeEach()
///   void addBook() => basket.add('Dune', 10);
///
///   @Test()
///   void costsItsPrice() => expect(basket.total, 10);
/// }
/// ```
///
/// Spring (Java): JUnit's `@Nested` on an inner class.
final class Nested {
  /// A group named [name], or after the field.
  const Nested([this.name]);

  /// The group's name; `null` names it after the field, split into words.
  final String? name;
}

/// Marks a `late CapturedLogs` field that holds what was logged through
/// `SpringLog` during the current test.
///
/// Use it to check that code logs a warning or an error. The field is
/// emptied before every test. In tests written as functions, call
/// `captureLogs()` instead.
///
/// ```dart
/// @CapturedOutput()
/// late CapturedLogs logs;
///
/// @Test()
/// void payingIsLogged() {
///   checkout.pay(3);
///   expect(logs.messages, contains('paid 3.0'));
/// }
/// ```
///
/// Spring (Java): Spring Boot's `OutputCaptureExtension` with a
/// `CapturedOutput` parameter. Here only `SpringLog` records are captured,
/// not everything the process prints.
final class CapturedOutput {
  /// Marks the field.
  const CapturedOutput();
}

/// Marks a `late int` field that receives the port of the real server the
/// test started.
///
/// Use it with `@SpringBootTest(webEnvironment: WebEnvironment.randomPort)`
/// to call the application over a socket, for example with a Feign client
/// or `HttpClient`. When no server runs, setting the field fails the test
/// with a `StateError`.
///
/// ```dart
/// @LocalServerPort()
/// late int port; // then call http://localhost:$port/api/books
/// ```
///
/// Spring (Java): `@LocalServerPort`.
final class LocalServerPort {
  /// Marks the field.
  const LocalServerPort();
}

/// Marks a test class that calls its controllers in memory through an
/// `@Autowired() late MockMvc mvc;` field.
///
/// It is optional and changes nothing: with `spring_boot_starter_web`, a
/// `MockMvc` field works without it. It states the intent, as in Spring,
/// where the annotation is required.
///
/// Spring (Java): `@AutoConfigureMockMvc`.
final class AutoConfigureMockMvc {
  /// Marks the class.
  const AutoConfigureMockMvc();
}
