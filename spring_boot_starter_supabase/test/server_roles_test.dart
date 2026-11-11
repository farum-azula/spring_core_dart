@Tags(['supabase'])
library;

import 'package:test/test.dart';

import 'server_support.dart';

// What a user of the project may do on the server: the roles are those of
// app_metadata, which only the project writes, and of nothing a user can
// write themself. `/api/admin` is behind @PreAuthorize("hasRole('ADMIN')").
void main() {
  final keys = testKeys;

  late KeyServer project;
  late TestServer server;

  setUpAll(() async {
    project = await KeyServer.project(keys);
    server = await TestServer.start(projectUrl: project.url);
  });

  tearDownAll(() async {
    await server.close();
    await project.close();
  });

  String token(Map<String, Object?> changes) =>
      sign(keys, userClaims(project.issuer, changes: changes));

  Future<Object?> authorities(String bearer) async {
    final answer = await server.me(bearer);
    expect(answer.status, 200, reason: answer.text);
    return (answer.json! as Map<String, Object?>)['authorities'];
  }

  Future<void> forbidden(String bearer) async {
    final answer = await server.get('/api/admin', bearer: bearer);
    expect(answer.status, 403, reason: answer.text);
    expect(answer.body, isNot(contains('every report')));
    expect(await authorities(bearer), isEmpty);
  }

  test('app_metadata.roles ["ADMIN"] gives hasRole(ADMIN)', () async {
    final admin = token({
      'app_metadata': {
        'provider': 'email',
        'roles': ['ADMIN'],
      },
    });
    final answer = await server.get('/api/admin', bearer: admin);
    expect(answer.status, 200, reason: answer.text);
    expect(answer.body, 'every report');
    expect(await authorities(admin), ['ROLE_ADMIN']);
  });

  test('a user without roles is refused with 403', () async {
    await forbidden(token(const {}));
  });

  test('another role of app_metadata is not ADMIN', () async {
    final editor = token({
      'app_metadata': {
        'roles': ['EDITOR', 'admin', 'ADMINISTRATOR'],
      },
    });
    final answer = await server.get('/api/admin', bearer: editor);
    expect(answer.status, 403);
    expect(await authorities(editor), [
      'ROLE_EDITOR',
      'ROLE_admin',
      'ROLE_ADMINISTRATOR',
    ]);
  });

  test('the same roles in user_metadata give nothing', () async {
    await forbidden(
      token({
        'user_metadata': {
          'roles': ['ADMIN'],
          'role': 'ADMIN',
          'app_metadata': {
            'roles': ['ADMIN'],
          },
          'app_metadata.roles': ['ADMIN'],
          'scope': 'ADMIN',
        },
      }),
    );
  });

  test('a top-level roles claim gives nothing', () async {
    await forbidden(
      token({
        'roles': ['ADMIN'],
      }),
    );
  });

  test('scope, scp, authorities and groups claims give nothing', () async {
    await forbidden(
      token({
        'scope': 'ADMIN',
        'scp': ['ADMIN'],
        'authorities': ['ROLE_ADMIN'],
        'groups': ['ADMIN'],
      }),
    );
  });

  test('roles elsewhere in app_metadata give nothing', () async {
    await forbidden(
      token({
        'app_metadata': {
          'role': 'ADMIN',
          'claims': {
            'roles': ['ADMIN'],
          },
          'Roles': ['ADMIN'],
        },
      }),
    );
  });

  test('the role claim of the token is no role of the application', () async {
    expect(await authorities(token(const {})), isEmpty);
  });

  // Not a way in for a user: the top-level claims of a token are written
  // by Auth alone (a user writes inside user_metadata only); a project's
  // own custom access token hook could add such a claim.
  test('a top-level claim literally named app_metadata.roles is read, and '
      'before the roles inside app_metadata', () async {
    final dotted = token({
      'app_metadata.roles': ['ADMIN'],
    });
    expect(await authorities(dotted), ['ROLE_ADMIN']);
    expect((await server.get('/api/admin', bearer: dotted)).status, 200);
    final both = token({
      'app_metadata': {
        'roles': ['USER'],
      },
      'app_metadata.roles': ['ADMIN'],
    });
    expect(await authorities(both), ['ROLE_ADMIN']);
  });

  test('an anonymous sign-in (is_anonymous) is a user, without '
      'roles', () async {
    final anonymous = token({
      'is_anonymous': true,
      'email': '',
      'app_metadata': <String, Object?>{},
    });
    final answer = await server.me(anonymous);
    expect(answer.status, 200);
    expect(answer.json, {'name': userId, 'authorities': <Object?>[]});
    await forbidden(anonymous);
  });

  test('no token: 401, not 403', () async {
    expect((await server.get('/api/admin')).status, 401);
  });
}
