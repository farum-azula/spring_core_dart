// Where the SQLite databases of a Flutter app live: the directory the starter
// picks from path_provider by `spring.datasource.sqlite.location`, and the
// worker isolate it asks for. A fake PathProviderPlatform and a pretended
// platform stand in for the devices.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/bound_properties.dart';
import 'package:spring_boot_starter_flutter/src/sqlite_directories.dart';

const _baseDirectory = 'spring.datasource.sqlite.base-directory';
const _isolate = 'spring.datasource.sqlite.isolate';
const _location = 'spring.datasource.sqlite.location';
const _url = 'spring.datasource.url=sqlite:file:books.db';
const _urlArg = '--$_url';

/// A PathProviderPlatform that returns the given paths, null for the rest
/// (path_provider then throws a MissingPlatformDirectoryException), and
/// notes which it was asked for.
class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths({this.support, this.cache, this.documents});

  final String? support;
  final String? cache;
  final String? documents;
  final asked = <String>[];

  @override
  Future<String?> getApplicationSupportPath() async {
    asked.add('support');
    return support;
  }

  @override
  Future<String?> getApplicationCachePath() async {
    asked.add('cache');
    return cache;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    asked.add('documents');
    return documents;
  }
}

/// An application of nothing but the property files [resources] (and
/// [defaults], the application's own `defaultProperties`).
SpringApplication _app({
  Map<String, String> resources = const {},
  Map<String, Object?> defaults = const {},
  String? fingerprint,
}) => SpringApplication(
  [
    BeanModule(
      'test',
      const [],
      resources: {
        for (final MapEntry(:key, :value) in resources.entries)
          key: EmbeddedResource.text(value),
      },
    ),
  ],
  defaultProperties: defaults,
  fingerprint: fingerprint,
  bannerMode: BannerMode.off,
);

void main() {
  late Directory temp;
  late PathProviderPlatform original;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('sqlite_directories_test');
    original = PathProviderPlatform.instance;
  });
  tearDown(() {
    PathProviderPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    temp.deleteSync(recursive: true);
  });

  /// The fake paths of a device whose directories are under [temp].
  _FakePaths device({String support = 'support'}) => _FakePaths(
    support: '${temp.path}/$support',
    cache: '${temp.path}/cache',
    documents: '${temp.path}/documents',
  );

  Future<SqliteDirectories> resolved(
    PathProviderPlatform paths, [
    TargetPlatform platform = TargetPlatform.iOS,
  ]) async {
    PathProviderPlatform.instance = paths;
    debugDefaultTargetPlatformOverride = platform;
    return (await SqliteDirectories.resolve())!;
  }

  /// Starts an application with the directories provided, from [args] and
  /// the application's own properties.
  Future<ConfigurableApplicationContext> start(
    SqliteDirectories directories,
    List<String> args, {
    Map<String, String> resources = const {},
    Map<String, Object?> defaults = const {},
    List<String> profiles = const [],
  }) async {
    final application = _app(resources: resources, defaults: defaults);
    directories.provideTo(application);
    final context = await application.runAsync(
      args,
      systemEnvironment: const {},
      additionalProfiles: profiles,
    );
    addTearDown(context.closeAsync);
    return context;
  }

  group('location', () {
    FlutterDataSourceProperties bind(String value) =>
        boundProperties<FlutterDataSourceProperties>(
          StandardEnvironment()
            ..propertySources.addFirst(
              MapPropertySource('test', {_location: value}),
            ),
          'flutterDataSourceProperties',
        );

    test('names the three directories, in any case', () {
      expect(bind('support').sqlite.location, SqliteLocation.support);
      expect(bind('Cache').sqlite.location, SqliteLocation.cache);
      expect(bind(' DOCUMENTS ').sqlite.location, SqliteLocation.documents);
    });

    test('an unknown one names the allowed values', () {
      expect(
        () => bind('downloads'),
        throwsA(
          isA<ConfigurationPropertiesBindException>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains(_location),
              contains('support, cache, documents'),
              contains('downloads'),
            ),
          ),
        ),
      );
    });
  });

  group('the support directory of each platform', () {
    const android = '/data/user/0/com.acme.books/files';
    const cache = '/data/user/0/com.acme.books/cache';

    test('Android: databases/, next to files/', () {
      expect(
        sqliteSupportDirectory(TargetPlatform.android, support: android),
        '/data/user/0/com.acme.books/databases',
      );
      expect(androidDatabasesDirectory('$android/'), endsWith('/databases'));
      expect(
        androidDatabasesDirectory('$android/'),
        '/data/user/0/com.acme.books/databases',
      );
      // Not a real device: inside what it gave.
      expect(
        androidDatabasesDirectory('/sandbox/data'),
        '/sandbox/data/databases',
      );
    });

    test('iOS, macOS, Linux: what path_provider gives', () {
      for (final (platform, support) in [
        (
          TargetPlatform.iOS,
          '/var/mobile/Containers/Data/Application/ID/Library/Application Support',
        ),
        (
          TargetPlatform.macOS,
          '/Users/u/Library/Containers/com.acme.books/Data/Library/'
              'Application Support/com.acme.books',
        ),
        (TargetPlatform.linux, '/home/u/.local/share/com.acme.books'),
        (TargetPlatform.fuchsia, '/data/books'),
      ]) {
        expect(
          sqliteSupportDirectory(platform, support: support, cache: cache),
          support,
          reason: '$platform',
        );
      }
    });

    test('Windows: the local directory, which path_provider calls cache', () {
      expect(
        sqliteSupportDirectory(
          TargetPlatform.windows,
          support: r'C:\Users\u\AppData\Roaming\Acme\Books',
          cache: r'C:\Users\u\AppData\Local\Acme\Books',
        ),
        r'C:\Users\u\AppData\Local\Acme\Books',
      );
    });

    test('is null when the directory it needs is', () {
      expect(sqliteSupportDirectory(TargetPlatform.android), isNull);
      expect(
        sqliteSupportDirectory(TargetPlatform.windows, support: 'roaming'),
        isNull,
      );
      expect(sqliteSupportDirectory(TargetPlatform.iOS, cache: 'c'), isNull);
    });
  });

  group('resolving the directories', () {
    test('reads the three, and Android moves support to databases/', () async {
      final paths = _FakePaths(
        support: '/data/user/0/com.acme.books/files',
        cache: '/data/user/0/com.acme.books/cache',
        documents: '/data/user/0/com.acme.books/app_flutter',
      );
      final directories = await resolved(paths, TargetPlatform.android);
      expect(
        directories.of(SqliteLocation.support),
        '/data/user/0/com.acme.books/databases',
      );
      expect(
        directories.of(SqliteLocation.cache),
        '/data/user/0/com.acme.books/cache',
      );
      expect(
        directories.of(SqliteLocation.documents),
        '/data/user/0/com.acme.books/app_flutter',
      );
      expect(paths.asked, unorderedEquals(['support', 'cache', 'documents']));
    });

    test('Windows never asks for the roaming support directory', () async {
      final paths = _FakePaths(
        support: r'C:\Users\u\AppData\Roaming\Acme\Books',
        cache: r'C:\Users\u\AppData\Local\Acme\Books',
        documents: r'C:\Users\u\Documents',
      );
      final directories = await resolved(paths, TargetPlatform.windows);
      expect(
        directories.of(SqliteLocation.support),
        r'C:\Users\u\AppData\Local\Acme\Books',
      );
      expect(directories.of(SqliteLocation.documents), r'C:\Users\u\Documents');
      // The cache is a folder of its own, never the folder of support.
      expect(
        directories.of(SqliteLocation.cache),
        r'C:\Users\u\AppData\Local\Acme\Books\cache',
      );
      expect(paths.asked, isNot(contains('support')));
    });

    test('each platform that takes support as it is', () async {
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        final directories = await resolved(device(), platform);
        expect(
          directories.of(SqliteLocation.support),
          '${temp.path}/support',
          reason: '$platform',
        );
      }
    });

    test(
      'a directory that cannot be read fails only when it is chosen',
      () async {
        final directories = await resolved(
          _FakePaths(
            support: '${temp.path}/support',
            cache: '${temp.path}/cache',
          ),
        );
        expect(directories.of(SqliteLocation.support), '${temp.path}/support');
        expect(
          () => directories.of(SqliteLocation.documents),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('documents directory of the app is not available'),
            ),
          ),
        );
      },
    );
  });

  group('the properties', () {
    test(
      'support is the default; the directory is created; isolate is on',
      () async {
        final directories = await resolved(device());
        final context = await start(directories, [_urlArg]);
        expect(
          context.environment.getProperty(_baseDirectory),
          '${temp.path}/support',
        );
        expect(context.environment.getProperty(_isolate), 'true');
        expect(Directory('${temp.path}/support').existsSync(), isTrue);
        // Only the chosen directory is made.
        expect(Directory('${temp.path}/cache').existsSync(), isFalse);
        expect(Directory('${temp.path}/documents').existsSync(), isFalse);
      },
    );

    test('location chooses among support, cache and documents', () async {
      final directories = await resolved(device());
      for (final name in ['support', 'cache', 'documents']) {
        final context = await start(directories, [
          _urlArg,
          '--$_location=$name',
        ]);
        expect(
          context.environment.getProperty(_baseDirectory),
          '${temp.path}/$name',
          reason: name,
        );
        expect(Directory('${temp.path}/$name').existsSync(), isTrue);
      }
    });

    test('location comes from the application properties files', () async {
      final directories = await resolved(device());
      final context = await start(
        directories,
        const [],
        profiles: ['ios'],
        resources: {
          'application.properties': '''
spring.datasource.url=sqlite:file:books.db
spring.datasource.sqlite.location=cache
''',
          'application-ios.properties':
              'spring.datasource.sqlite.location=documents',
        },
      );
      // The profile file, read after the plain one, has the last word.
      expect(
        context.environment.getProperty(_baseDirectory),
        '${temp.path}/documents',
      );
    });

    test('the application\'s own properties win', () async {
      final directories = await resolved(device());
      // The command line.
      var context = await start(directories, [
        '--spring.datasource.url=sqlite:file:books.db',
        '--$_baseDirectory=/explicit',
      ]);
      expect(context.environment.getProperty(_baseDirectory), '/explicit');
      expect(context.environment.getProperty(_isolate), 'true');

      // A properties file, and isolate off.
      context = await start(
        directories,
        const [],
        resources: {
          'application.properties': '''
spring.datasource.url=sqlite:file:books.db
spring.datasource.sqlite.base-directory=/from-file
spring.datasource.sqlite.isolate=false
''',
        },
      );
      expect(context.environment.getProperty(_baseDirectory), '/from-file');
      expect(context.environment.getProperty(_isolate), 'false');

      // The application's default properties, which are the lowest of the
      // application's own.
      context = await start(
        directories,
        [_urlArg],
        defaults: {_baseDirectory: '/default'},
      );
      expect(context.environment.getProperty(_baseDirectory), '/default');
    });

    test('named data sources get them too, with their own winning', () async {
      final directories = await resolved(device());
      final context = await start(
        directories,
        [
          '--spring.datasources.stats.url=sqlite:file:stats.db',
          '--spring.datasources.audit.url=sqlite:file:audit.db',
          '--spring.datasources.audit.sqlite.base-directory=/audit',
          '--$_location=cache',
        ],
      );
      final environment = context.environment;
      expect(
        environment.getProperty(
          'spring.datasources.stats.sqlite.base-directory',
        ),
        '${temp.path}/cache',
      );
      expect(
        environment.getProperty('spring.datasources.stats.sqlite.isolate'),
        'true',
      );
      expect(
        environment.getProperty(
          'spring.datasources.audit.sqlite.base-directory',
        ),
        '/audit',
      );
      // No primary data source: nothing for it.
      expect(environment.getProperty(_baseDirectory), isNull);
    });

    test('without a data source nothing is set, and nothing is made', () async {
      final directories = await resolved(device());
      final context = await start(directories, const []);
      expect(context.environment.getProperty(_baseDirectory), isNull);
      expect(context.environment.getProperty(_isolate), isNull);
      expect(temp.listSync(), isEmpty);
    });

    test('an unknown location stops the start, naming the values', () async {
      final directories = await resolved(device());
      await expectLater(
        start(directories, [_urlArg, '--$_location=downloads']),
        throwsA(
          isA<ConfigurationPropertiesBindException>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains(_location),
              contains('downloads'),
              contains('support, cache, documents'),
            ),
          ),
        ),
      );
    });

    test('a location asked for and unavailable stops the start', () async {
      final directories = await resolved(
        _FakePaths(support: '${temp.path}/support'),
      );
      await expectLater(
        start(directories, [_urlArg, '--$_location=documents']),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('documents directory of the app is not available'),
          ),
        ),
      );
    });

    test('the default unavailable leaves the directory unset, not the '
        'isolate', () async {
      final directories = await resolved(_FakePaths());
      final context = await start(directories, [_urlArg]);
      expect(context.environment.getProperty(_baseDirectory), isNull);
      // The worker isolate does not need a directory.
      expect(context.environment.getProperty(_isolate), 'true');
    });

    test(
      'the default unavailable: every data source gets the isolate',
      () async {
        final directories = await resolved(_FakePaths());
        final context = await start(directories, [
          _urlArg,
          '--spring.datasources.stats.url=sqlite:file:stats.db',
        ]);
        final environment = context.environment;
        expect(
          environment.getProperty('spring.datasources.stats.sqlite.isolate'),
          'true',
        );
        expect(
          environment.getProperty(
            'spring.datasources.stats.sqlite.base-directory',
          ),
          isNull,
        );
      },
    );

    test('an application asked twice is provided once', () async {
      final directories = await resolved(device());
      final application = _app();
      final before = application.listeners.length;
      directories
        ..provideTo(application)
        ..provideTo(application);
      expect(application.listeners.length, before + 1);
    });

    test('the data source prefixes are found like the data starter does', () {
      final environment = StandardEnvironment(systemEnvironment: const {})
        ..propertySources.addFirst(
          MapPropertySource('test', {
            'spring.datasource.url': 'sqlite:file:a.db',
            'spring.datasources.stats.url': 'sqlite:file:b.db',
            'spring.datasources.stats.pool.max-size': '1',
            'spring.datasources.audit.url': 'sqlite:file:c.db',
            'spring.datasources.x': 'no name below it',
          }),
        );
      expect(dataSourcePrefixes(environment), [
        'spring.datasource.',
        'spring.datasources.audit.',
        'spring.datasources.stats.',
      ]);
      expect(
        dataSourcePrefixes(StandardEnvironment(systemEnvironment: const {})),
        isEmpty,
      );
    });
  });

  group('in SpringApplicationWidget', () {
    // A widget test on [platform]. The framework checks its debug variables
    // when the body ends, before any tearDown: the test resets it itself.
    void onPlatform(
      String description,
      TargetPlatform platform,
      Future<void> Function(WidgetTester tester) body,
    ) => testWidgets(description, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    Future<ApplicationContext> pump(
      WidgetTester tester,
      SpringApplication Function() application,
    ) async {
      const child = Text('ready', textDirection: TextDirection.ltr);
      await tester.pumpWidget(
        SpringApplicationWidget(application: application, child: child),
      );
      await tester.pumpAndSettle();
      return SpringScope.of(tester.element(find.byWidget(child)));
    }

    onPlatform(
      'the start resolves the directories and sets the properties',
      TargetPlatform.macOS,
      (
        tester,
      ) async {
        PathProviderPlatform.instance = device();
        final context = await pump(
          tester,
          () => _app(
            resources: {
              'application.properties': '''
spring.datasource.url=sqlite:file:books.db
spring.datasource.sqlite.location=documents
''',
            },
          ),
        );
        expect(
          context.environment.getProperty(_baseDirectory),
          '${temp.path}/documents',
        );
        expect(context.environment.getProperty(_isolate), 'true');
        expect(Directory('${temp.path}/documents').existsSync(), isTrue);
      },
    );

    onPlatform(
      'an unknown location shows the failure screen',
      TargetPlatform.iOS,
      (tester) async {
        PathProviderPlatform.instance = device();
        await tester.pumpWidget(
          SpringApplicationWidget(
            application: () => _app(
              resources: {
                'application.properties': '''
spring.datasource.url=sqlite:file:books.db
spring.datasource.sqlite.location=sd-card
''',
              },
            ),
            child: const SizedBox(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('support, cache, documents'),
          findsOneWidget,
        );
      },
    );

    onPlatform(
      'an app without path_provider (a widget test) still starts',
      TargetPlatform.iOS,
      (
        tester,
      ) async {
        // The default platform answers with MissingPluginException.
        final context = await pump(
          tester,
          () => _app(
            resources: {'application.properties': _url},
          ),
        );
        expect(context.environment.getProperty(_baseDirectory), isNull);
      },
    );

    onPlatform(
      'a hot reload restart sets them on the new application',
      TargetPlatform.iOS,
      (
        tester,
      ) async {
        PathProviderPlatform.instance = device();
        var fingerprint = 'one';
        var location = 'support';
        final before = await pump(
          tester,
          () => _app(
            fingerprint: fingerprint,
            resources: {
              'application.properties':
                  '''
spring.datasource.url=sqlite:file:books.db
spring.datasource.sqlite.location=$location
''',
            },
          ),
        );
        expect(
          before.environment.getProperty(_baseDirectory),
          '${temp.path}/support',
        );

        fingerprint = 'two';
        location = 'cache';
        unawaited(tester.binding.reassembleApplication());
        await tester.pumpAndSettle();
        final after = SpringScope.of(tester.element(find.text('ready')));
        expect(after, isNot(same(before)));
        expect(
          after.environment.getProperty(_baseDirectory),
          '${temp.path}/cache',
        );
        expect(after.environment.getProperty(_isolate), 'true');
      },
    );
  });
}
