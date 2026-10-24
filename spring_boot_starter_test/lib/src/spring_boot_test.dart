import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_test/src/bean_override.dart';
import 'package:spring_boot_starter_test/src/dynamic_property_registry.dart';
import 'package:test_api/scaffolding.dart';

/// Starts [application] for the tests of the enclosing `main` or `group`,
/// like `@SpringBootTest`: the context is created once before the first
/// test (config files, auto-configuration, `@ConfigurationProperties`,
/// runners: everything `runApplication` does) and closed after the last.
///
/// - [resourceDirectories] (default `test/resources/`, relative to the
///   package of the calling test file, wherever the tests are started
///   from) come first on the classpath during the tests, like `src/test/resources`: put
///   `application-test.properties` there (with `profiles: ['test']`) or
///   test data read as `classpath:...`. They are never embedded into the
///   application. A file with the same path as a `lib/resources/` file
///   replaces it entirely, as in Spring;
/// - [propertyFiles] are loaded as properties
///   (`@TestPropertySource(locations = ...)`; later files win);
/// - [properties] win over every other property source, [propertyFiles]
///   included (`@SpringBootTest(properties = ...)`);
/// - [dynamicProperties] adds properties whose values are known only when
///   the context starts, e.g. the port of a server started in an earlier
///   `setUpAll` (`@DynamicPropertySource`): it is called at every start
///   and each value supplier whenever the property is read; these win
///   over [properties];
/// - [profiles] become `spring.profiles.active` (`@ActiveProfiles`);
/// - [systemEnvironment] replaces the OS environment (empty by default, so
///   tests do not depend on the machine);
/// - [overrides] replace beans with fakes or mocks (`@MockitoBean`);
/// - [initializers] run before the refresh
///   (`@ContextConfiguration(initializers = ...)`).
///
/// Logging levels and the log handler are restored afterwards.
///
/// ```dart
/// import '../bin/shop.spring.dart'; // springApplication
///
/// void main() {
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
}) {
  final test = SpringBootTestContext._(
    application,
    args: List.unmodifiable(args),
    properties: {
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
        (context) {
          final source = DynamicValuesPropertySource();
          dynamicProperties(source);
          context.environment.propertySources.addFirst(source);
        },
      if (overrides.isNotEmpty)
        (context) => context.addBeanFactoryPostProcessor(
          BeanOverrideProcessor(overrides),
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
  tearDown(() {
    if (test._dirty) {
      test._close();
    }
  });
  tearDownAll(test._finish);
  return test;
}

/// The running context of a [springBootTest].
final class SpringBootTestContext {
  SpringBootTestContext._(
    this._application, {
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

  /// The test classpath directories (resolved [springBootTest]
  /// `resourceDirectories`), first one first.
  List<String> get resourceDirectories => _resourceDirectories;

  /// The command-line arguments the application is started with.
  final List<String> args;

  /// The application context. Available inside tests and `setUp`.
  ConfigurableApplicationContext get context =>
      _context ??
      (throw StateError(
        'The Spring context is not started: use it inside test(), setUp() '
        'or setUpAll() declared after springBootTest().',
      ));

  /// The context's environment.
  ConfigurableEnvironment get environment => context.environment;

  /// What the application printed (failure reports; the startup info is
  /// logged through `SpringLog`).
  List<String> get output => List.unmodifiable(_output);

  /// The bean of type [T] (optionally with [qualifier]).
  T getBean<T extends Object>({String? qualifier}) =>
      context.getBean<T>(qualifier: qualifier);

  /// The bean named [name].
  Object getBeanByName(String name) => context.getBeanByName(name);

  /// Closes the context after the current test; the next test gets a
  /// fresh one (Spring's `@DirtiesContext`).
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
      registerShutdownHook: false, // the test closes its context
      initializers: [..._application.initializers, ..._initializers],
      resourceLoader: _application.resourceLoader,
      out: (line) {
        _output.add(line);
        printOnFailure(line);
      },
    );
    _context = await application.runAsync(
      args,
      systemEnvironment: _systemEnvironment,
      properties: {...fromFiles, ..._properties},
    );
  }

  void _close() {
    final context = _context;
    _context = null;
    _dirty = false;
    if (context != null && context.isActive) {
      context.close();
    }
  }

  void _finish() {
    _close();
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
