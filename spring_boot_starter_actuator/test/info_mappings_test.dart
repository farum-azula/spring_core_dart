// /actuator/info with its contributors and /actuator/mappings in Spring
// WebFlux's shape, over HTTP.
import 'dart:io' as io;

import 'package:spring_boot_starter_actuator/spring_boot_starter_actuator.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late io.Directory files;

  setUpAll(() {
    files = io.Directory.systemTemp.createTempSync('actuator_info_');
    io.File('${files.path}/build-info.properties').writeAsStringSync('''
build.artifact=shop
build.group=com.example
build.name=Shop
build.time=2026-11-05T09:12:44.000Z
build.version=1.4.0
''');
    io.File('${files.path}/git.properties').writeAsStringSync('''
git.branch=main
git.commit.id=4faa522d0c1e9a6b8f00
git.commit.id.abbrev=4faa522
git.commit.time=2026-11-04T18:02:11Z
git.commit.message.short=Release 1.4.0
''');
  });

  tearDownAll(() => files.deleteSync(recursive: true));

  List<String> located() => [
    'management.endpoints.web.exposure.include=info',
    'spring.info.build.location=file:${files.path}/build-info.properties',
    'spring.info.git.location=file:${files.path}/git.properties',
  ];

  group('info', () {
    test('empty without build and git files', () async {
      await withActuator(
        (mvc, context) async {
          expect(jsonOf(await mvc.get('/actuator/info')), isEmpty);
          expect(context, doesNotHaveBean<BuildProperties>());
          expect(context, doesNotHaveBean<GitInfoContributor>());
        },
        properties: ['management.endpoints.web.exposure.include=info'],
      );
    });

    test('build and git, as Spring Boot shows them', () async {
      await withActuator((mvc, context) async {
        expect(jsonOf(await mvc.get('/actuator/info')), {
          'git': {
            'branch': 'main',
            'commit': {'id': '4faa522', 'time': '2026-11-04T18:02:11Z'},
          },
          'build': {
            'artifact': 'shop',
            'group': 'com.example',
            'name': 'Shop',
            'time': '2026-11-05T09:12:44Z',
            'version': '1.4.0',
          },
        });
        expect(context.getBean<BuildProperties>().version, '1.4.0');
      }, properties: located());
    });

    test('git in full mode; build switched off', () async {
      await withActuator(
        (mvc, context) async {
          final info = jsonOf(await mvc.get('/actuator/info'))! as Map;
          expect(info.keys, ['git']);
          expect(info['git'], {
            'branch': 'main',
            'commit': {
              'id': {'full': '4faa522d0c1e9a6b8f00', 'abbrev': '4faa522'},
              'time': '2026-11-04T18:02:11Z',
              'message': {'short': 'Release 1.4.0'},
            },
          });
        },
        properties: [
          ...located(),
          'management.info.git.mode=full',
          'management.info.build.enabled=false',
        ],
      );
    });

    test('env, os and dart when switched on; defaults.enabled', () async {
      await withActuator(
        (mvc, context) async {
          final info = jsonOf(await mvc.get('/actuator/info'))! as Map;
          expect(info['app'], {'name': 'Shop', 'team': 'books'});
          expect((info['os']! as Map).keys, ['name', 'version', 'arch']);
          expect((info['dart']! as Map)['version'], isA<String>());
          // build and git follow defaults.enabled; the others their own key.
          expect(info, isNot(contains('build')));
          expect(info, isNot(contains('git')));
        },
        properties: [
          ...located(),
          'management.info.defaults.enabled=false',
          'management.info.env.enabled=true',
          'management.info.os.enabled=true',
          'management.info.dart.enabled=true',
          'info.app.name=Shop',
          'info.app.team=books',
        ],
      );
    });

    test(
      'info.* is not shown unless env is on, as in Spring Boot 2.6',
      () async {
        await withActuator(
          (mvc, context) async {
            expect(jsonOf(await mvc.get('/actuator/info')), isEmpty);
          },
          properties: [
            'management.endpoints.web.exposure.include=info',
            'info.app.name=Shop',
          ],
        );
      },
    );
  });

  group('mappings', () {
    Future<Map<String, Object?>> mappings(
      MockMvc mvc, [
      String context = 'application',
    ]) async {
      final body = jsonOf(await mvc.get('/actuator/mappings'))! as Map;
      final contexts = body['contexts']! as Map;
      expect(contexts.keys, [context]);
      final application = contexts[context]! as Map;
      expect(application['parentId'], isNull);
      expect(application, contains('parentId'));
      return application['mappings']! as Map<String, Object?>;
    }

    test("the web server's handlers under dispatcherHandlers", () async {
      await withActuator(
        (mvc, context) async {
          final handlers =
              ((await mappings(mvc))['dispatcherHandlers']!
                      as Map)['webHandler']!
                  as List;
          final byPredicate = {
            for (final handler in handlers.cast<Map<String, Object?>>())
              handler['predicate']: handler,
          };
          expect(
            byPredicate['{GET [/api/books/{isbn}], produces [application/json]}'],
            {
              'predicate':
                  '{GET [/api/books/{isbn}], produces [application/json]}',
              'handler': 'BookController#find(String)',
              'details': {
                'handlerMethod': {
                  'className': 'BookController',
                  'name': 'find',
                  'descriptor': '(String isbn) -> Map<String, dynamic>',
                },
                'requestMappingConditions': {
                  'consumes': <Object?>[],
                  'headers': <Object?>[],
                  'methods': ['GET'],
                  'params': <Object?>[],
                  'patterns': ['/api/books/{isbn}'],
                  'produces': [
                    {'mediaType': 'application/json', 'negated': false},
                  ],
                },
              },
            },
          );
          final post =
              byPredicate['{POST [/api/books], headers [X-Api=2], consumes [application/json]}']!
                  as Map;
          expect(
            ((post['details']! as Map)['requestMappingConditions']!
                as Map)['headers'],
            [
              {'name': 'X-Api', 'value': '2', 'negated': false},
            ],
          );
          // The actuator's own endpoints.
          final health =
              byPredicate['{GET [/actuator/health], produces [application/vnd.spring-boot.actuator.v3+json || application/vnd.spring-boot.actuator.v2+json || application/json]}']!
                  as Map;
          expect(health['handler'], "Actuator web endpoint 'health'");
          expect(
            ((health['details']! as Map)['handlerMethod']! as Map)['className'],
            'HealthEndpointWebExtension',
          );
          // The static resources, after the controllers.
          expect(handlers.last, {
            'predicate': '(GET && /)',
            'handler': 'WelcomePage [index.html]',
          });
          expect(byPredicate['/**'], {
            'predicate': '/**',
            'handler':
                'ResourceWebHandler [resources:static/, resources:public/]',
          });
          // In the dispatcher's order: the actuator (-100) first.
          expect(
            (handlers.first as Map)['handler'],
            'Actuator root web endpoint',
          );
        },
        properties: ['management.endpoints.web.exposure.include=*'],
      );
    });

    test('the context is named after the application', () async {
      await withActuator(
        (mvc, context) async {
          await mappings(mvc, 'shop');
        },
        properties: [
          'management.endpoints.web.exposure.include=mappings',
          'spring.application.name=shop',
        ],
      );
    });

    test('every MappingDescriptions bean has its key', () async {
      await withActuator(
        (mvc, context) async {
          final all = await mappings(mvc);
          expect(all.keys, containsAll(['dispatcherHandlers', 'jobs']));
          expect(all['jobs'], [
            {'pattern': '/jobs/{id}'},
          ]);
        },
        properties: ['management.endpoints.web.exposure.include=mappings'],
        setUp: (runner) => runner.withBean<MappingDescriptions>(
          _Jobs.new,
          name: 'jobMappings',
        ),
      );
    });
  });
}

final class _Jobs implements MappingDescriptions {
  @override
  String get mappingsName => 'jobs';

  @override
  Object? describeMappings() => [
    {'pattern': '/jobs/{id}'},
  ];
}
