import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_test/src/bean_override.dart';
import 'package:spring_boot_starter_test/src/dynamic_property_registry.dart';
import 'package:spring_boot_starter_test/src/mock_mvc.dart';
import 'package:test_api/scaffolding.dart';

/// Starts the whole application for the tests of the enclosing `main` or
/// `group`, and returns a handle to reach its beans.
///
/// Use it for tests that need the real wiring: services with their
/// repositories, properties bound from the config files, controllers
/// behind [SpringBootTestContext.mockMvc]. The context starts once, in a
/// `setUpAll`, before the first test, and does everything
/// `runApplication` does (config files, auto-configuration,
/// `@ConfigurationProperties`, runners). It is closed with `closeAsync()`
/// in a `tearDownAll` after the last test, so asynchronous `@PreDestroy`
/// methods and lifecycle stops are awaited. Test classes marked
/// `@SpringBootTest()` are generated into a call of this function.
///
/// The options change the application for these tests only:
/// - [args]: command-line arguments.
/// - [properties]: properties that win over every other source, the
///   command line and [propertyFiles] included (Spring's
///   `@SpringBootTest(properties = ...)`).
/// - [propertyFiles]: resource locations of `.properties` files; later
///   files win (`@TestPropertySource(locations = ...)`). A missing file
///   fails the start with a [StateError].
/// - [dynamicProperties]: properties whose values are known only when the
///   tests run, such as the port of a server started in a `setUpAll`
///   declared before this call (`@DynamicPropertySource`). It is called at
///   every start of the context, and each value supplier whenever the
///   property is read. These values win over [properties].
/// - [resourceDirectories]: directories first on the classpath during the
///   tests, like `src/test/resources` (default `test/resources`). Put
///   `application-test.properties` (with `profiles: ['test']`) or test
///   data read as `classpath:...` there. Relative paths are resolved
///   against the package of the calling test file, wherever the tests are
///   started from. They are never embedded into the application. A file
///   with the same path as one in `lib/resources/` replaces it entirely,
///   as in Spring.
/// - [profiles]: become `spring.profiles.active`, replacing the value of
///   the config files (`@ActiveProfiles`).
/// - [systemEnvironment]: replaces the OS environment, which is empty by
///   default so that tests do not depend on the machine.
/// - [overrides]: replace beans with fakes or mocks before any bean is
///   created (`@MockitoBean`, `@TestBean`).
/// - [initializers]: run on the context before it is refreshed
///   (`@ContextConfiguration(initializers = ...)`).
/// - [webEnvironment]: which web server starts; none by default.
///
/// After [SpringBootTestContext.markDirty] the context is closed at the
/// end of the current test, and the next test starts a new one. The
/// `SpringLog` levels and handler are restored after the last test.
///
/// ```dart
/// import '../bin/shop.spring.dart'; // the generated springApplication
///
/// void main() {
///   // The real shop, with a fake payment gateway and test settings.
///   final app = springBootTest(
///     springApplication,
///     properties: {'shop.name': 'Test Books'},
///     profiles: ['test'],
///     overrides: [BeanOverride<PaymentGateway>(FakeGateway())],
///   );
///
///   test('checkout uses the fake', () {
///     expect(app.getBean<Checkout>().pay(10), 'fake: 10');
///   });
/// }
/// ```
///
/// Works the same under `flutter_test`.
///
/// Spring (Java):
/// ```java
/// @SpringBootTest(properties = "shop.name=Test Books")
/// @ActiveProfiles("test")
/// class CheckoutTest { @Autowired Checkout checkout; ... }
/// ```
SpringBootTestContext springBootTest(
  SpringApplication application, {
  List<String> args = const [],
  Map<String, Object?> properties = const {},
  void Function(DynamicPropertyRegistry registry)? dynamicProperties,
  List<String> propertyFiles = const [],
  List<String> resourceDirectories = const ['test/resources'],
  List<String> profiles = const [],
  Map<String, String> systemEnvironment = const {},
  List<BeanOverride<Object>> overrides = const [],
  List<ApplicationContextInitializer> initializers = const [],
  WebEnvironment webEnvironment = WebEnvironment.mock,
}) {
  final test = SpringBootTestContext._(
    application,
    args: List.unmodifiable(args),
    webEnvironment: webEnvironment,
    properties: {
      'spring.test.web-environment': webEnvironment._value,
      ...properties,
      if (profiles.isNotEmpty) 'spring.profiles.active': profiles.join(','),
    },
    systemEnvironment: systemEnvironment,
    propertyFiles: List.unmodifiable(propertyFiles),
    resourceDirectories: List.unmodifiable(
      _resolveAgainst(_packageRootOf(StackTrace.current), resourceDirectories),
    ),
    initializers: [
      if (dynamicProperties != null)
        ApplicationContextInitializer.of((context) {
          final source = DynamicValuesPropertySource();
          dynamicProperties(source);
          context.environment.propertySources.addFirst(source);
        }),
      if (overrides.isNotEmpty)
        ApplicationContextInitializer.of(
          (context) => context.addBeanFactoryPostProcessor(
            BeanOverrideProcessor(overrides),
          ),
        ),
      ...initializers,
    ],
  );
  setUpAll(test._start);
  setUp(() async {
    if (test._context == null) {
      await test._start();
    }
  });
  tearDown(() async {
    if (test._dirty) {
      await test._close();
    }
  });
  tearDownAll(test._finish);
  return test;
}

/// Which web server [springBootTest] starts for the tests when the
/// application uses `spring_boot_starter_web`.
///
/// Most web tests keep the default, [mock]: no socket, and requests go
/// through [SpringBootTestContext.mockMvc], fast and without port
/// conflicts. Choose [randomPort] when the client under test needs a real
/// connection, such as a Feign client, `HttpClient` or a WebSocket client.
/// The value reaches the web starter as the property
/// `spring.test.web-environment`.
///
/// ```dart
/// // A real server, for a client that opens a socket.
/// final app = springBootTest(
///   springApplication,
///   webEnvironment: WebEnvironment.randomPort,
/// );
///
/// test('over HTTP', () async {
///   final url = 'http://localhost:${app.localServerPort}/api/books';
///   ...
/// });
/// ```
///
/// Spring (Java): `SpringBootTest.WebEnvironment`, with `MOCK`,
/// `RANDOM_PORT`, `DEFINED_PORT` and `NONE`.
enum WebEnvironment {
  /// No server: [SpringBootTestContext.mockMvc] calls the controllers in
  /// memory. The default.
  mock('mock'),

  /// A real server on a free port. The context counts as started once the
  /// server listens; [SpringBootTestContext.localServerPort] gives the port.
  randomPort('random-port'),

  /// A real server on the port of the `server.port` property; the start
  /// fails when that port is taken.
  definedPort('defined-port'),

  /// No server. The web starter still creates its dispatcher, so
  /// [SpringBootTestContext.mockMvc] works as with [mock].
  none('none');

  WebEnvironment(this._value);

  final String _value;
}

/// The handle on the application that [springBootTest] started: its
/// beans, its environment, what it printed and the port of its server.
///
/// [springBootTest] returns it at once, before the context exists; the
/// context starts in `setUpAll`. So use it inside tests, `setUp`, or a
/// `setUpAll` declared after the [springBootTest] call. In a test class,
/// an `@Autowired() late SpringBootTestContext app;` field receives it.
///
/// ```dart
/// final app = springBootTest(springApplication);
///
/// test('a new basket is empty', () {
///   // The application's real Basket bean.
///   expect(app.getBean<Basket>().items, isEmpty);
/// });
/// ```
final class SpringBootTestContext {
  SpringBootTestContext._(
    this._application, {
    required this.webEnvironment,
    required this.args,
    required this._properties,
    required this._systemEnvironment,
    required this._initializers,
    required this._propertyFiles,
    required this._resourceDirectories,
  });

  final List<String> _propertyFiles;
  final List<String> _resourceDirectories;
  final List<void Function()> _removeDirectories = [];
  final SpringApplication _application;
  final Map<String, Object?> _properties;
  final Map<String, String> _systemEnvironment;
  final List<ApplicationContextInitializer> _initializers;
  final List<String> _output = [];
  ConfigurableApplicationContext? _context;
  bool _dirty = false;
  _LogState? _logState;

  /// The classpath directories of the tests: the `resourceDirectories` of
  /// [springBootTest], resolved against the test package, first one first.
  List<String> get resourceDirectories => _resourceDirectories;

  /// The command-line arguments the application starts with.
  final List<String> args;

  /// The web server the tests asked for.
  final WebEnvironment webEnvironment;

  /// The port the real server listens on, read from the
  /// `local.server.port` property: use it to build URLs for clients that
  /// need a socket.
  ///
  /// Only with [WebEnvironment.randomPort] or [WebEnvironment.definedPort];
  /// otherwise it throws a [StateError]. Spring's `@LocalServerPort`.
  int get localServerPort =>
      switch (environment.getProperty('local.server.port')) {
        final port? => int.parse(port),
        null => throw StateError(
          'No web server runs: use springBootTest(webEnvironment: '
          'WebEnvironment.randomPort) with spring_boot_starter_web',
        ),
      };

  /// Sends requests to the application's controllers in memory, through
  /// the dispatcher a real server would use.
  ///
  /// Needs `spring_boot_starter_web`; without it, it throws a [StateError].
  /// It is created on first use and anew after the context restarts.
  /// Spring's `@AutoConfigureMockMvc` with an injected `MockMvc`.
  MockMvc get mockMvc => _mockMvc ??= MockMvc.of(context);
  MockMvc? _mockMvc;

  /// The running application context, for what the shortcuts of this class
  /// do not cover.
  ///
  /// Throws a [StateError] before the context started or after it closed,
  /// that is outside tests, `setUp` and a `setUpAll` declared after
  /// [springBootTest].
  ConfigurableApplicationContext get context =>
      _context ??
      (throw StateError(
        'The Spring context is not started: use it inside test(), setUp() '
        'or setUpAll() declared after springBootTest().',
      ));

  /// The context's environment, to read a property as the application sees
  /// it.
  ConfigurableEnvironment get environment => context.environment;

  /// The lines the application printed, such as the failure report of a
  /// context that did not start, over all the starts of this test file.
  /// Each line is also shown when a test fails. The startup information is
  /// logged through `SpringLog` and is not here; `captureLogs` records logs.
  List<String> get output => List.unmodifiable(_output);

  /// The bean of type [T]; with [qualifier], the one it names among several.
  /// Throws when no bean matches.
  T getBean<T extends Object>({String? qualifier}) =>
      context.getBean<T>(qualifier: qualifier);

  /// The bean called [name] (or an alias of it), whatever its type. Throws
  /// when there is none.
  Object getBeanByName(String name) => context.getBeanByName(name);

  /// The bean of type [T] (with [qualifier], the one it names), or `null`
  /// when there is none: what an optional `@Autowired()` field
  /// (`late Mailer? mailer;`) receives.
  T? findBean<T extends Object>({String? qualifier}) =>
      context.getBeanProvider<T>(qualifier: qualifier).getIfAvailable();

  /// Every bean of type [T] (with [qualifier], only those it selects),
  /// sorted by `@Order`: what an `@Autowired()` `List<T>` field receives.
  List<T> getBeans<T extends Object>({String? qualifier}) =>
      context.beanFactory.getSortedBeans<T>(qualifier: qualifier);

  /// Resolves a `@Value` expression as a bean's `@Value` field would:
  /// `${...}` placeholders first, then `#{...}` expressions, converted to
  /// [T]. What a `@Value` field of a test class receives.
  ///
  /// ```dart
  /// final limit = app.value<int>(r'${shop.max-basket-size}');
  /// ```
  T value<T>(String expression) => _resolver.value<T>(expression);

  /// Like [value], but `null` when a placeholder has no value: what a
  /// nullable `@Value` field receives.
  T? optionalValue<T>(String expression) =>
      _resolver.optionalValue<T>(expression);

  DependencyResolver get _resolver => switch (context.beanFactory) {
    final DependencyResolver resolver => resolver,
    _ => throw StateError('The bean factory cannot resolve @Value'),
  };

  /// Closes the context at the end of the current test, so the next test
  /// starts a new one (Spring's `@DirtiesContext`).
  ///
  /// Call it in a test that changed the state of beans in a way later tests
  /// must not see; `setUp(app.markDirty)` gives every test a fresh context.
  void markDirty() => _dirty = true;

  Future<void> _start() async {
    _logState ??= _LogState.save();
    _dirty = false;
    if (_removeDirectories.isEmpty) {
      // Reversed: the first listed directory ends up first on the classpath.
      for (final directory in _resourceDirectories.reversed) {
        _removeDirectories.add(ClasspathResources.addDirectory(directory));
      }
    }
    final loader = _application.resourceLoader ?? DefaultResourceLoader();
    final fromFiles = <String, Object?>{};
    for (final location in _propertyFiles) {
      final resource = loader.getResource(location);
      if (!resource.exists()) {
        throw StateError('Test property file not found: $location');
      }
      fromFiles.addAll(await PropertiesLoaderUtils.loadProperties(resource));
    }
    final application = SpringApplication(
      _application.modules,
      autoConfigurations: _application.autoConfigurations,
      autoConfigurationMetadata: _application.autoConfigurationMetadata,
      exclude: _application.exclude,
      excludeName: _application.excludeName,
      initializers: [..._application.initializers, ..._initializers],
      resourceLoader: _application.resourceLoader,
      // Explicit, whatever the default: the test closes its context.
      // ignore: avoid_redundant_argument_values
      registerShutdownHook: false,
      out: (line) {
        _output.add(line);
        printOnFailure(line);
      },
    );
    final context = await application.runAsync(
      args,
      systemEnvironment: _systemEnvironment,
      properties: {...fromFiles, ..._properties},
    );
    _context = context;
    _mockMvc = null;
    if (webEnvironment == WebEnvironment.randomPort ||
        webEnvironment == WebEnvironment.definedPort) {
      await _awaitServer(context);
    }
  }

  // The server binds its socket asynchronously; it publishes
  // `local.server.port` once it listens (or closes the context when it
  // cannot start).
  static Future<void> _awaitServer(
    ConfigurableApplicationContext context,
  ) async {
    final watch = Stopwatch()..start();
    while (context.environment.getProperty('local.server.port') == null) {
      if (!context.isActive) {
        throw StateError('The web server failed to start (see the log)');
      }
      if (!context.containsBean('webServerStartStopLifecycle')) {
        throw StateError(
          'webEnvironment: ${WebEnvironment.randomPort.name} needs '
          'spring_boot_starter_web',
        );
      }
      if (watch.elapsed > const Duration(seconds: 30)) {
        throw StateError('The web server did not start within 30 seconds');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  // Like SpringApplication's shutdown: closeAsync() awaits asynchronous
  // @PreDestroy methods and SmartLifecycle stops.
  Future<void> _close() async {
    final context = _context;
    _context = null;
    _dirty = false;
    if (context != null && context.isActive) {
      await context.closeAsync();
    }
  }

  Future<void> _finish() async {
    await _close();
    for (final remove in _removeDirectories) {
      remove();
    }
    _removeDirectories.clear();
    _logState?.restore();
    _logState = null;
  }
}

/// The package of the test file that called [springBootTest]: the nearest
/// directory with a `pubspec.yaml` above it, so `test/resources` is found
/// also when the tests run from a workspace root or an IDE. `null` when
/// unknown (e.g. browser tests); then paths stay relative to the working
/// directory.
String? _packageRootOf(StackTrace trace) {
  for (final match in RegExp(r'file://[^\s)]+?\.dart').allMatches('$trace')) {
    try {
      final uri = Uri.parse(match[0]!);
      if (uri.path.contains('/spring_boot_starter_test/lib/')) {
        continue;
      }
      for (var dir = uri.resolve('.'); ;) {
        if (FileSystemResource(dir.resolve('pubspec.yaml').toFilePath())
            .exists()) {
          return dir.toFilePath();
        }
        final parent = dir.resolve('..');
        if (parent == dir) {
          return null;
        }
        dir = parent;
      }
    } on Object {
      return null;
    }
  }
  return null;
}

List<String> _resolveAgainst(String? root, List<String> directories) => [
  for (final directory in directories)
    if (root == null || _isAbsolute(directory))
      directory
    else
      '$root$directory',
];

bool _isAbsolute(String path) =>
    path.startsWith('/') ||
    path.startsWith(r'\\') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

/// Global `SpringLog` settings a test application may change.
final class _LogState {
  _LogState.save()
    : level = SpringLog.level,
      levels = SpringLog.configuredLevels,
      handler = SpringLog.handler;

  final SpringLogLevel level;
  final Map<String, SpringLogLevel> levels;
  final SpringLogHandler handler;

  void restore() {
    SpringLog.level = level;
    SpringLog.resetLevels();
    levels.forEach(SpringLog.setLevel);
    SpringLog.handler = handler;
  }
}
