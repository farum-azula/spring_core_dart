@Tags(['supabase'])
library;

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'auth_support.dart';
import 'support.dart';

void main() {
  late MockHttpTransport transport;
  late SupabaseAuthAdmin admin;

  setUp(() {
    transport = MockHttpTransport();
    admin = SupabaseAuthAdmin(
      http: http(transport, properties_: properties(serviceRole: true)),
    );
  });

  void expectServiceCall(HttpRequest request, HttpMethod method, String url) {
    expect(request.method, method);
    expect('${request.url}', url);
    expect(request.headers['apikey'], 'service-key');
    expect(request.headers['Authorization'], 'Bearer service-key');
    expect(request.followRedirects, isFalse);
  }

  test('createUser posts the user as the service role', () async {
    transport
        .when(HttpMethod.post, '/auth/v1/admin/users')
        .respond(
          200,
          json: userJson(
            appMetadata: {
              'roles': ['editor'],
            },
            userMetadata: {'name': 'Ada'},
          ),
        );
    final user = await admin.createUser(
      email: 'ada@example.com',
      password: 'correct horse',
      emailConfirm: true,
      appMetadata: {
        'roles': ['editor'],
      },
      userMetadata: {'name': 'Ada'},
    );
    final request = transport.requests.single;
    expectServiceCall(
      request,
      HttpMethod.post,
      '$projectUrl/auth/v1/admin/users',
    );
    expect(bodyOf(request), {
      'email': 'ada@example.com',
      'password': 'correct horse',
      'email_confirm': true,
      'app_metadata': {
        'roles': ['editor'],
      },
      'user_metadata': {'name': 'Ada'},
    });
    expect(user.id, userId);
    expect(user.roles, ['editor']);
    expect(user.userMetadata, {'name': 'Ada'});
  });

  test('createUser sends only what is given', () async {
    transport
        .when(HttpMethod.post, '/auth/v1/admin/users')
        .respond(200, json: userJson());
    await admin.createUser(phone: '+15550100', phoneConfirm: true);
    expect(bodyOf(transport.requests.single), {
      'phone': '+15550100',
      'phone_confirm': true,
    });
    expect(admin.createUser, throwsArgumentError);
    expect(transport.requests, hasLength(1));
  });

  test('a refused user is an AuthenticationException with the code', () async {
    transport
        .when(HttpMethod.post, '/auth/v1/admin/users')
        .respond(
          422,
          json: errorJson(422, 'email_exists', 'Email already registered'),
        );
    await expectLater(
      admin.createUser(email: 'ada@example.com'),
      throwsA(
        isA<SupabaseAuthenticationException>()
            .having((e) => e.errorCode, 'errorCode', 'email_exists')
            .having((e) => e.statusCode, 'statusCode', 422),
      ),
    );
  });

  test('user reads one user, null when there is none', () async {
    transport
        .when(HttpMethod.get, '/auth/v1/admin/users/$userId')
        .respond(200, json: userJson());
    transport
        .when(HttpMethod.get, '/auth/v1/admin/users/$userId')
        .respond(404, json: errorJson(404, 'user_not_found', 'User not found'));
    final user = await admin.user(userId);
    expectServiceCall(
      transport.requests.single,
      HttpMethod.get,
      '$projectUrl/auth/v1/admin/users/$userId',
    );
    expect(transport.requests.single.body, isNull);
    expect(user!.email, 'ada@example.com');
    expect(await admin.user(userId), isNull);
  });

  test('users reads a page', () async {
    transport
        .when(HttpMethod.get, '/auth/v1/admin/users')
        .respond(
          200,
          json: {
            'aud': 'authenticated',
            'users': [
              userJson(),
              userJson(id: '99999999-2222-3333-4444-555555555555', email: null),
              {'not': 'a user'},
            ],
          },
        );
    final users = await admin.users(page: 2, perPage: 10);
    expectServiceCall(
      transport.requests.single,
      HttpMethod.get,
      '$projectUrl/auth/v1/admin/users?page=2&per_page=10',
    );
    expect(
      [for (final user in users) user.id],
      [
        userId,
        '99999999-2222-3333-4444-555555555555',
      ],
    );
    await admin.users();
    expect(transport.requests.last.url.query, 'page=1&per_page=50');
    expect(() => admin.users(page: 0), throwsArgumentError);
    expect(() => admin.users(perPage: 0), throwsArgumentError);
    expect(transport.requests, hasLength(2));
  });

  test('updateUser puts only what is given', () async {
    transport
        .when(HttpMethod.put, '/auth/v1/admin/users/$userId')
        .respond(
          200,
          json: userJson(
            appMetadata: {
              'roles': ['admin'],
            },
          ),
        );
    final user = await admin.updateUser(
      userId,
      password: 'new correct horse',
      emailConfirm: true,
      appMetadata: {
        'roles': ['admin'],
      },
      banDuration: 'none',
    );
    final request = transport.requests.single;
    expectServiceCall(
      request,
      HttpMethod.put,
      '$projectUrl/auth/v1/admin/users/$userId',
    );
    expect(bodyOf(request), {
      'password': 'new correct horse',
      'email_confirm': true,
      'app_metadata': {
        'roles': ['admin'],
      },
      'ban_duration': 'none',
    });
    expect(user.roles, ['admin']);
  });

  test('deleteUser deletes, softly when asked', () async {
    transport
        .when(HttpMethod.delete, '/auth/v1/admin/users/$userId')
        .respond(200, json: {});
    await admin.deleteUser(userId);
    expectServiceCall(
      transport.requests.single,
      HttpMethod.delete,
      '$projectUrl/auth/v1/admin/users/$userId',
    );
    expect(bodyOf(transport.requests.single), {'should_soft_delete': false});
    await admin.deleteUser(userId, softDelete: true);
    expect(bodyOf(transport.requests.last), {'should_soft_delete': true});
  });

  test('a user that is not there is its own exception', () async {
    transport
        .when(HttpMethod.delete, '/auth/v1/admin/users/$userId')
        .respond(404, json: errorJson(404, 'user_not_found', 'User not found'));
    transport
        .when(HttpMethod.put, '/auth/v1/admin/users/$userId')
        .respond(404, json: errorJson(404, 'user_not_found', 'User not found'));
    await expectLater(
      admin.deleteUser(userId),
      throwsA(isA<UsernameNotFoundException>()),
    );
    await expectLater(
      admin.updateUser(userId, email: 'x@example.com'),
      throwsA(
        isA<SupabaseUserNotFoundException>().having(
          (e) => e.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });

  test('an id that is no UUID never becomes a path', () async {
    for (final id in [
      '',
      '1',
      '../users',
      '$userId/factors',
      '$userId?x=1',
      '$userId ',
      'generate_link',
    ]) {
      expect(() => admin.user(id), throwsArgumentError, reason: id);
      expect(() => admin.updateUser(id), throwsArgumentError, reason: id);
      expect(() => admin.deleteUser(id), throwsArgumentError, reason: id);
    }
    expect(transport.requests, isEmpty);
  });

  test(
    'without the service role key every call fails before a request',
    () async {
      final keyless = SupabaseAuthAdmin(http: http(transport));
      final names = isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('spring.supabase.service-role-key'),
      );
      for (final call in <Future<Object?> Function()>[
        () => keyless.createUser(email: 'a@b.c'),
        () => keyless.user(userId),
        keyless.users,
        () => keyless.updateUser(userId, email: 'a@b.c'),
        () => keyless.deleteUser(userId),
      ]) {
        await expectLater(call, throwsA(names));
      }
      expect(transport.requests, isEmpty);
    },
  );

  test("the anon key and a user's token are refused by Auth", () async {
    transport
        .when(HttpMethod.get, '/auth/v1/admin/users')
        .respond(403, json: errorJson(403, 'not_admin', 'User not allowed'));
    await expectLater(
      admin.users(),
      throwsA(
        isA<AuthenticationException>().having(
          (e) => (e as SupabaseAuthFailure).errorCode,
          'errorCode',
          'not_admin',
        ),
      ),
    );
  });

  test('no answer is a SupabaseUnavailableException', () async {
    transport
        .when(HttpMethod.get, '/auth/v1/admin/users')
        .fail(HttpTransportException('connection refused'));
    await expectLater(
      admin.users(),
      throwsA(isA<SupabaseUnavailableException>()),
    );
  });

  test('the calls around it stay what they were', () async {
    // The service role is for the admin call only.
    final all = properties(serviceRole: true);
    final client = http(transport, properties_: all);
    transport
        .when(HttpMethod.get, '/auth/v1/admin/users')
        .respond(200, json: {'users': <Object?>[]});
    transport.when(HttpMethod.get, '/rest/v1/todos').respond(200, json: []);
    await SupabaseAuthAdmin(http: client).users();
    await client.send(SupabaseService.rest, HttpMethod.get, '/todos');
    expect(transport.requests.last.headers['apikey'], 'anon-key');
    expect(transport.requests.last.headers['Authorization'], 'Bearer anon-key');
  });
}
