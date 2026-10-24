import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

/// Like a Flutter asset: readable asynchronously only.
final class AsyncOnly extends AbstractResource {
  AsyncOnly(this.text);

  final String text;

  @override
  bool exists() => true;

  @override
  String get description => 'asset [banner.txt]';

  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(utf8.encode(text));
}

final class Recording implements ApplicationContextInitializer, Ordered {
  Recording(this.name, this.order, this.seen);

  final String name;
  final List<String> seen;

  @override
  final int order;

  @override
  void initialize(ConfigurableApplicationContext context) => seen.add(name);
}

class Warmer {}

class Plain {}

void main() {
  final created = <String>[];

  BeanModule module([List<BeanDefinition<Object>> extra = const []]) =>
      BeanModule('app', [
        BeanDefinition<Warmer>(
          name: 'warmer',
          create: (_) {
            created.add('warmer');
            return Warmer();
          },
        ),
        BeanDefinition<Plain>(
          name: 'plain',
          create: (_) {
            created.add('plain');
            return Plain();
          },
        ),
        ...extra,
      ]);

  ConfigurableApplicationContext run(
    List<String> args, {
    List<BeanDefinition<Object>> beans = const [],
    List<ApplicationContextInitializer> initializers = const [],
    Map<String, String> env = const {},
  }) {
    created.clear();
    final context = SpringApplication(
      [module(beans)],
      initializers: initializers,
      bannerMode: BannerMode.off,
      out: (_) {},
    ).run(args, systemEnvironment: env);
    addTearDown(context.close);
    return context;
  }

  test('initializers are classes, run sorted by order', () {
    final seen = <String>[];
    run(
      const [],
      initializers: [
        Recording('last', Ordered.lowestPrecedence, seen),
        ApplicationContextInitializer.of((_) => seen.add('lambda')),
        Recording('first', Ordered.highestPrecedence, seen),
        ApplicationContextInitializer.of((_) => seen.add('second'), order: 0),
      ],
    );
    expect(seen, ['first', 'second', 'last', 'lambda']);
  });

  group('LazyInitializationExcludeFilter', () {
    test('beans it excludes stay eager with lazy initialization', () {
      run(
        ['--spring.main.lazy-initialization=true'],
        beans: [
          BeanDefinition<LazyInitializationExcludeFilter>(
            name: 'eagerWarmers',
            create: (_) =>
                const LazyInitializationExcludeFilter.forBeanTypes([Warmer]),
          ),
        ],
      );
      expect(created, ['warmer']);
    });

    test('a function filter sees the name', () {
      run(
        ['--spring.main.lazy-initialization=true'],
        beans: [
          BeanDefinition<LazyInitializationExcludeFilter>(
            name: 'byName',
            create: (_) => LazyInitializationExcludeFilter.of(
              (name, definition, type) => name == 'plain',
            ),
          ),
        ],
      );
      expect(created, ['plain']);
    });

    test('without a filter everything is lazy', () {
      run(['--spring.main.lazy-initialization=true']);
      expect(created, isEmpty);
    });
  });

  group('SPRING_APPLICATION_JSON / spring.application.json', () {
    test('the environment variable: nested objects and arrays', () {
      final environment = run(
        const [],
        env: {
          'SPRING_APPLICATION_JSON':
              '{"app":{"name":"json","hosts":["a","b"],"port":8080}}',
        },
      ).environment;
      expect(environment.getProperty('app.name'), 'json');
      expect(environment.getProperty('app.hosts[1]'), 'b');
      expect(environment.getPropertyAs<int>('app.port'), 8080);
    });

    test('below the command line, above the OS environment', () {
      final environment = run(
        [
          '--spring.application.json={"a":"json","b":"json","c":"json"}',
          '--a=cli',
        ],
        env: {'B': 'env', 'D': 'env'},
      ).environment;
      expect(environment.getProperty('a'), 'cli');
      expect(environment.getProperty('b'), 'json');
      expect(environment.getProperty('c'), 'json');
      expect(environment.getProperty('d'), 'env');
    });

    test('seen by config data (spring.config.import, profiles)', () {
      final environment = run(
        const [],
        env: {
          'SPRING_APPLICATION_JSON': '{"spring":{"profiles":{"active":"x"}}}',
        },
      ).environment;
      expect(environment.activeProfiles, ['x']);
    });

    test('invalid JSON fails the start', () {
      expect(
        () => run(['--spring.application.json={nope']),
        throwsA(isA<StateError>()),
      );
    });
  });

  test(
    'runAsync prints a banner.txt that is readable asynchronously only',
    () async {
      final saved = SpringLog.level;
      SpringLog.level = SpringLogLevel.info;
      final logged = <String>[];
      final stop = SpringLog.listen((record) => logged.add(record.message));
      addTearDown(() {
        stop();
        SpringLog.level = saved;
      });
      final context =
          await SpringApplication(
            [module()],
            resourceLoader: DefaultResourceLoader(
              protocolResolvers: [
                FunctionProtocolResolver(
                  (location, _) => location == 'classpath:banner.txt'
                      ? AsyncOnly(r'Hello ${app.who}')
                      : null,
                ),
              ],
            ),
            out: (_) {},
          ).runAsync([
            '--spring.main.banner-mode=log',
            '--app.who=asset',
          ], systemEnvironment: const {});
      addTearDown(context.close);
      expect(logged, contains(contains('Hello asset')));
    },
  );

  group('spring.messages.*', () {
    ConfigurableApplicationContext start(List<String> args) {
      final context = SpringApplication(
        [module()],
        autoConfigurations: [springBootAutoConfiguration],
        bannerMode: BannerMode.off,
        out: (_) {},
      ).run(args, systemEnvironment: const {});
      addTearDown(context.close);
      return context;
    }

    setUpAll(
      () => ClasspathResources.registerAll({
        'fixes_messages/latin.properties': EmbeddedResource.base64(
          base64Encode(latin1.encode('greeting=Grüße')),
        ),
        'fixes_messages/plain.properties': const EmbeddedResource.text(
          "quoted=It''s\nown=mine",
        ),
        'fixes_messages/common.properties': const EmbeddedResource.text(
          'shared=common\nown=common',
        ),
      }),
    );

    test('encoding', () {
      final context = start([
        '--spring.messages.basename=fixes_messages/latin',
        '--spring.messages.encoding=ISO-8859-1',
      ]);
      expect(context.getMessage('greeting', locale: 'en'), 'Grüße');
    });

    test('always-use-message-format and common-messages', () {
      final context = start([
        '--spring.messages.basename=fixes_messages/plain',
        '--spring.messages.always-use-message-format=true',
        '--spring.messages.common-messages=classpath:fixes_messages/common.properties',
      ]);
      expect(context.getMessage('quoted', locale: 'en'), "It's");
      expect(context.getMessage('shared', locale: 'en'), 'common');
      expect(context.getMessage('own', locale: 'en'), 'mine');
      final plain = start(['--spring.messages.basename=fixes_messages/plain']);
      expect(plain.getMessage('quoted', locale: 'en'), "It''s");
    });
  });

  test('ApplicationFailedEvent reaches listeners added to the context', () {
    final failed = <ApplicationFailedEvent>[];
    expect(
      () => run(
        const [],
        beans: [
          BeanDefinition<Object>(
            name: 'broken',
            create: (_) => throw StateError('broken'),
          ),
        ],
        initializers: [
          ApplicationContextInitializer.of(
            (context) => context.addApplicationListener(
              ApplicationListenerAdapter.of<ApplicationFailedEvent>(failed.add),
            ),
          ),
        ],
      ),
      throwsA(anything),
    );
    expect(failed, hasLength(1));
  });
}
