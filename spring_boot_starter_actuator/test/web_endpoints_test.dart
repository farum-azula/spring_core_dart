// The endpoints over HTTP through MockMvc: exposure, enablement, the base
// path and path mappings, the discovery page with Spring Boot's _links,
// content negotiation, methods, selectors and query parameters.
import 'package:spring_boot_starter_actuator/spring_boot_starter_actuator.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

const _v3 = 'application/vnd.spring-boot.actuator.v3+json';
const _v2 = 'application/vnd.spring-boot.actuator.v2+json';

Map<String, Object?> linksOf(MvcResult result) =>
    (jsonOf(result)! as Map)['_links']! as Map<String, Object?>;

void main() {
  group('exposure', () {
    test('only health by default, as Spring Boot', () async {
      await withActuator((mvc, context) async {
        final health = await mvc.get('/actuator/health');
        expect(health.response.statusCode, 200);
        expect(health.response.headers.contentType, _v3);
        expect(jsonOf(health), {'status': 'UP'});
        expect((await mvc.get('/actuator/info')).response.statusCode, 404);
        expect((await mvc.get('/actuator/mappings')).response.statusCode, 404);
        expect((await mvc.get('/actuator/features')).response.statusCode, 404);
        expect(linksOf(await mvc.get('/actuator')), {
          'self': {'href': 'http://localhost/actuator', 'templated': false},
          'health': {
            'href': 'http://localhost/actuator/health',
            'templated': false,
          },
          'health-path': {
            'href': 'http://localhost/actuator/health/{*path}',
            'templated': true,
          },
        });
      });
    });

    test(
      'include * exposes every enabled endpoint, sorted in the links',
      () async {
        await withActuator(
          (mvc, context) async {
            expect(linksOf(await mvc.get('/actuator')).keys, [
              'self',
              'features',
              'features-name',
              'health',
              'health-path',
              'info',
              'jsonschemas',
              'jsonschemas-path',
              'mappings',
              'whoami',
            ]);
            // The JSON Schemas: the registry's and the classes'.
            final schemas = await mvc.get('/actuator/jsonschemas');
            expect(schemas.response.statusCode, 200);
            expect((jsonOf(schemas)! as Map).keys, [
              'registry',
              'introspected',
            ]);
            // `echo` is off by default.
            expect(
              (await mvc.get(
                '/actuator/echo',
                params: {'text': 'a'},
              )).response.statusCode,
              404,
            );
          },
          properties: ['management.endpoints.web.exposure.include=*'],
        );
      },
    );

    test('exclude wins over include', () async {
      await withActuator(
        (mvc, context) async {
          expect((await mvc.get('/actuator/info')).response.statusCode, 200);
          expect(
            (await mvc.get('/actuator/mappings')).response.statusCode,
            404,
          );
        },
        properties: [
          'management.endpoints.web.exposure.include=*',
          'management.endpoints.web.exposure.exclude=mappings,features',
        ],
      );
    });

    test('a YAML-like indexed list is read too', () async {
      await withActuator(
        (mvc, context) async {
          expect((await mvc.get('/actuator/info')).response.statusCode, 200);
          expect((await mvc.get('/actuator/health')).response.statusCode, 200);
        },
        properties: [
          'management.endpoints.web.exposure.include[0]=health',
          'management.endpoints.web.exposure.include[1]=info',
        ],
      );
    });
  });

  group('enablement', () {
    test(
      'management.endpoint.<id>.enabled=false hides an exposed one',
      () async {
        await withActuator(
          (mvc, context) async {
            expect((await mvc.get('/actuator/info')).response.statusCode, 404);
            expect(
              linksOf(await mvc.get('/actuator')),
              isNot(contains('info')),
            );
          },
          properties: [
            'management.endpoints.web.exposure.include=*',
            'management.endpoint.info.enabled=false',
          ],
        );
      },
    );

    test('enabled-by-default=false, then one endpoint on', () async {
      await withActuator(
        (mvc, context) async {
          expect((await mvc.get('/actuator/health')).response.statusCode, 200);
          expect((await mvc.get('/actuator/info')).response.statusCode, 404);
        },
        properties: [
          'management.endpoints.web.exposure.include=*',
          'management.endpoints.enabled-by-default=false',
          'management.endpoint.health.enabled=true',
        ],
      );
    });

    test(
      'access=none (Spring Boot 3.4) and an endpoint off by default',
      () async {
        await withActuator(
          (mvc, context) async {
            expect(
              (await mvc.get('/actuator/health')).response.statusCode,
              404,
            );
            final echo = await mvc.get(
              '/actuator/echo',
              params: {'text': 'ab', 'times': '2'},
            );
            expect(echo.response.statusCode, 200);
            expect(jsonOf(echo), {'text': 'abab', 'suffix': null});
          },
          properties: [
            'management.endpoints.web.exposure.include=*',
            'management.endpoint.health.access=none',
            'management.endpoint.echo.enabled=true',
          ],
        );
      },
    );
  });

  group('paths', () {
    test('another base path and a path mapping', () async {
      await withActuator(
        (mvc, context) async {
          expect(
            (await mvc.get('/manage/healthcheck')).response.statusCode,
            200,
          );
          expect(
            (await mvc.get('/manage/healthcheck/ping')).response.statusCode,
            404, // components hidden
          );
          expect((await mvc.get('/actuator/health')).response.statusCode, 404);
          expect(linksOf(await mvc.get('/manage')), {
            'self': {'href': 'http://localhost/manage', 'templated': false},
            'health': {
              'href': 'http://localhost/manage/healthcheck',
              'templated': false,
            },
            'health-path': {
              'href': 'http://localhost/manage/healthcheck/{*path}',
              'templated': true,
            },
          });
        },
        properties: [
          'management.endpoints.web.base-path=manage/',
          'management.endpoints.web.path-mapping.health=healthcheck',
        ],
      );
    });

    test('the root as base path: no discovery page', () async {
      await withActuator(
        (mvc, context) async {
          expect((await mvc.get('/health')).response.statusCode, 200);
          // `/` is the welcome page's, not the links'.
          expect((await mvc.get('/')).response.statusCode, 404);
        },
        properties: ['management.endpoints.web.base-path=/'],
      );
    });

    test('discovery switched off', () async {
      await withActuator(
        (mvc, context) async {
          expect((await mvc.get('/actuator')).response.statusCode, 404);
          expect((await mvc.get('/actuator/health')).response.statusCode, 200);
        },
        properties: ['management.endpoints.web.discovery.enabled=false'],
      );
    });

    test('the server context path is in the links', () async {
      await withActuator(
        (mvc, context) async {
          final links = linksOf(await mvc.get('/shop/actuator'));
          expect(
            (links['health']! as Map)['href'],
            'http://localhost/shop/actuator/health',
          );
          expect(
            (await mvc.get('/shop/actuator/health')).response.statusCode,
            200,
          );
        },
        properties: ['server.context-path=/shop'],
      );
    });
  });

  group('content negotiation', () {
    test('application/json when asked; version 2 when asked', () async {
      await withActuator(
        (mvc, context) async {
          final json = await mvc.get(
            '/actuator/health',
            headers: {'Accept': 'application/json'},
          );
          expect(json.response.headers.contentType, 'application/json');
          final v2 = await mvc.get(
            '/actuator/health',
            headers: {'Accept': _v2},
          );
          expect(v2.response.headers.contentType, _v2);
          expect(jsonOf(v2), {
            'status': 'UP',
            'details': {
              'inbox': {'status': 'UP'},
              'ping': {'status': 'UP'},
            },
          });
          final any = await mvc.get(
            '/actuator/health',
            headers: {'Accept': 'text/html;q=0.9, */*;q=0.8'},
          );
          expect(any.response.headers.contentType, _v3);
        },
        properties: [
          'management.endpoint.health.show-components=always',
          'management.health.diskspace.enabled=false',
        ],
      );
    });

    test('a client that takes no JSON gets 406', () async {
      await withActuator((mvc, context) async {
        final html = await mvc.get(
          '/actuator/health',
          headers: {'Accept': 'text/html'},
        );
        expect(html.response.statusCode, 406);
      });
    });
  });

  group('methods', () {
    test('POST is 405 with Allow; HEAD has no body', () async {
      await withActuator((mvc, context) async {
        final post = await mvc.post('/actuator/health');
        expect(post.response.statusCode, 405);
        expect(post.response.headers['Allow'], contains('GET'));
        final head = await mvc.perform(
          MockRequestBuilder(HttpMethod.head, '/actuator/health'),
        );
        expect(head.response.statusCode, 200);
        expect(head.response.bodyText, isEmpty);
      });
    });
  });

  group('operations', () {
    test('a selector, and null is a 404', () async {
      await withActuator(
        (mvc, context) async {
          expect(jsonOf(await mvc.get('/actuator/features')), {
            'dark-mode': true,
            'beta': false,
          });
          expect(jsonOf(await mvc.get('/actuator/features/dark-mode')), {
            'name': 'dark-mode',
            'enabled': true,
          });
          final missing = await mvc.get('/actuator/features/nope');
          expect(missing.response.statusCode, 404);
          expect(missing.response.bodyText, isEmpty);
          expect(
            (await mvc.get('/actuator/features/a/b')).response.statusCode,
            404,
          );
        },
        properties: ['management.endpoints.web.exposure.include=features'],
      );
    });

    test('query parameters: missing is 400, unconvertible is 400', () async {
      await withActuator(
        (mvc, context) async {
          expect(
            jsonOf(
              await mvc.get(
                '/actuator/echo',
                params: {'text': 'x', 'suffix': '!'},
              ),
            ),
            {'text': 'x', 'suffix': '!'},
          );
          expect((await mvc.get('/actuator/echo')).response.statusCode, 400);
          expect(
            (await mvc.get(
              '/actuator/echo',
              params: {'text': 'x', 'times': 'lots'},
            )).response.statusCode,
            400,
          );
        },
        properties: [
          'management.endpoints.web.exposure.include=echo',
          'management.endpoint.echo.enabled=true',
        ],
      );
    });

    test('no user without the security starter', () async {
      await withActuator(
        (mvc, context) async {
          expect(jsonOf(await mvc.get('/actuator/whoami')), {
            'name': null,
            'admin': false,
          });
        },
        properties: ['management.endpoints.web.exposure.include=whoami'],
      );
    });
  });

  test('the beans of the starter', () async {
    await withActuator((mvc, context) async {
      expect(context, hasSingleBean<WebEndpointHandlerMapping>());
      expect(context, hasSingleBean<WebEndpointRequestFilter>());
      expect(context, hasSingleBean<HealthEndpoint>());
      expect(context, hasSingleBean<HealthEndpointWebExtension>());
      expect(context, hasSingleBean<InfoEndpoint>());
      expect(context, hasSingleBean<MappingsEndpoint>());
      expect(context, hasSingleBean<HealthContributorRegistry>());
      expect(
        context.getBean<HealthContributorRegistry>().names,
        unorderedEquals(['inbox', 'ping', 'diskSpace']),
      );
      expect(context.getBean<WebEndpointHandlerMapping>().order, -100);
    });
  });
}
