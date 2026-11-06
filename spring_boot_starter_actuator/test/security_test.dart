// The endpoints behind the security starter: a chain of their own with
// EndpointRequest, and show-details=when-authorized with the roles of the
// request's Authentication.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'secured/secured_app.dart';
import 'support.dart';

Map<String, String> basic(String user) => {
  'Authorization': 'Basic ${base64.encode(utf8.encode('$user:$user'))}',
};

Future<void> withSecurity(
  Future<void> Function(MockMvc mvc) body, {
  List<String> properties = const [],
}) => withActuator(
  (mvc, context) => body(mvc),
  properties: [
    'management.endpoints.web.exposure.include=*',
    'management.health.diskspace.enabled=false',
    ...properties,
  ],
  setUp: (runner) => runner
      .withUserConfiguration(securedTestBeans)
      .withAutoConfiguration(springSecurityCoreAutoConfiguration)
      .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
      .withAutoConfiguration(springBootStarterSecurityAutoConfiguration),
);

void main() {
  test('health, info and the links are open; the others need ADMIN', () async {
    await withSecurity((mvc) async {
      expect((await mvc.get('/actuator/health')).response.statusCode, 200);
      expect((await mvc.get('/actuator/info')).response.statusCode, 200);
      expect((await mvc.get('/actuator')).response.statusCode, 200);
      expect((await mvc.get('/actuator/mappings')).response.statusCode, 401);
      expect(
        (await mvc.get(
          '/actuator/mappings',
          headers: basic('ada'),
        )).response.statusCode,
        403,
      );
      expect(
        (await mvc.get(
          '/actuator/mappings',
          headers: basic('root'),
        )).response.statusCode,
        200,
      );
      // The health's sub-paths are the health endpoint too.
      expect((await mvc.get('/actuator/health/ping')).response.statusCode, 404);
    });
  });

  test('other requests go to the other chain', () async {
    await withSecurity((mvc) async {
      expect((await mvc.get('/api/books/1')).response.statusCode, 401);
      expect(
        (await mvc.get(
          '/api/books/1',
          headers: basic('ada'),
        )).response.statusCode,
        200,
      );
      // Not an exposed endpoint: not EndpointRequest's.
      expect((await mvc.get('/actuator/env')).response.statusCode, 401);
    });
  });

  test('when-authorized: details for any logged-in user', () async {
    await withSecurity((mvc) async {
      expect(jsonOf(await mvc.get('/actuator/health')), {'status': 'UP'});
      expect(
        jsonOf(await mvc.get('/actuator/health', headers: basic('ada'))),
        {
          'status': 'UP',
          'components': {
            'inbox': {
              'status': 'UP',
              'details': {'pending': 3},
            },
            'ping': {'status': 'UP'},
          },
        },
      );
    }, properties: ['management.endpoint.health.show-details=when-authorized']);
  });

  test('when-authorized with roles: ROLE_ADMIN is ADMIN', () async {
    await withSecurity(
      (mvc) async {
        expect(
          jsonOf(await mvc.get('/actuator/health', headers: basic('ada'))),
          {'status': 'UP'},
        );
        final root =
            jsonOf(
                  await mvc.get('/actuator/health', headers: basic('root')),
                )!
                as Map;
        expect(root['components'], isNotNull);
        expect(
          jsonOf(await mvc.get('/actuator/whoami', headers: basic('root'))),
          {'name': 'root', 'admin': true},
        );
      },
      properties: [
        'management.endpoint.health.show-details=when-authorized',
        'management.endpoint.health.roles=ADMIN',
      ],
    );
  });
}
