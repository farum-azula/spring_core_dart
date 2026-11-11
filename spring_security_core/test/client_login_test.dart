// The interfaces a client application's login is made of: each can be
// implemented with this package alone, and the in-memory secret store
// keeps what it is given.
import 'dart:async';

import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

final class _Token implements OAuth2Token {
  const _Token(this.tokenValue, {this.issuedAt, this.expiresAt});

  @override
  final String tokenValue;

  @override
  final DateTime? issuedAt;

  @override
  final DateTime? expiresAt;
}

// A login kept in a SecretStore: one user, one token.
final class _StoredLoginSession implements LoginSession {
  _StoredLoginSession(this.store);

  final SecretStore store;
  final _changes = StreamController<Authentication?>.broadcast();
  Authentication? _authentication;
  String? _token;

  Future<Authentication> login(String name, String token) async {
    await store.write('login.name', name);
    await store.write('login.token', token);
    return _set(name, token)!;
  }

  Authentication? _set(String? name, String? token) {
    _token = token;
    _authentication = name == null
        ? null
        : UsernamePasswordAuthenticationToken.authenticated(name, null, [
            SimpleGrantedAuthority('ROLE_USER'),
          ]);
    _changes.add(_authentication);
    return _authentication;
  }

  @override
  Authentication? get authentication => _authentication;

  @override
  bool get isLoggedIn => _authentication?.isAuthenticated ?? false;

  @override
  Stream<Authentication?> get authenticationChanges => _changes.stream;

  @override
  Future<String?> accessToken() async => _token;

  @override
  Future<Authentication?> restore() async {
    final name = await store.read('login.name');
    final token = await store.read('login.token');
    return name == null || token == null ? null : _set(name, token);
  }

  @override
  Future<void> logout() async {
    if (!isLoggedIn) {
      return;
    }
    await store.delete('login.name');
    await store.delete('login.token');
    _set(null, null);
  }
}

final class _Window implements AuthorizationWindow {
  _Window({this.cancelled = false});

  final bool cancelled;

  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) async {
    final opened = authorizationUri(redirectUri);
    if (cancelled) {
      throw const AuthorizationCancelledException('closed');
    }
    return redirectUri.replace(
      queryParameters: {
        'code': 'c0de',
        'state': ?opened.queryParameters['state'],
      },
    );
  }
}

void main() {
  group('OAuth2Token', () {
    test('a token has a value and, when known, its times', () {
      final issuedAt = DateTime.utc(2026, 11, 10, 12);
      final OAuth2Token token = _Token(
        'value',
        issuedAt: issuedAt,
        expiresAt: issuedAt.add(const Duration(hours: 1)),
      );
      expect(token.tokenValue, 'value');
      expect(token.issuedAt, issuedAt);
      expect(token.expiresAt, DateTime.utc(2026, 11, 10, 13));
      const OAuth2Token opaque = _Token('opaque');
      expect(opaque.issuedAt, isNull);
      expect(opaque.expiresAt, isNull);
    });
  });

  group('InMemorySecretStore', () {
    test('reads what was written, by key', () async {
      final SecretStore store = InMemorySecretStore();
      expect(await store.read('app.pin'), isNull);
      await store.write('app.pin', '1234');
      await store.write('oauth2.login', '{"access_token":"a"}');
      expect(await store.read('app.pin'), '1234');
      expect(await store.read('oauth2.login'), '{"access_token":"a"}');
      expect(await store.keys(), {'app.pin', 'oauth2.login'});
    });

    test('a write replaces the old value', () async {
      final store = InMemorySecretStore();
      await store.write('app.pin', '1234');
      await store.write('app.pin', '5678');
      expect(await store.read('app.pin'), '5678');
      expect(await store.keys(), {'app.pin'});
    });

    test('delete removes one key; a missing one is no error', () async {
      final store = InMemorySecretStore();
      await store.write('a', '1');
      await store.write('b', '2');
      await store.delete('a');
      await store.delete('missing');
      expect(await store.read('a'), isNull);
      expect(await store.keys(), {'b'});
    });

    test('deleteAll removes everything', () async {
      final store = InMemorySecretStore();
      await store.write('a', '1');
      await store.write('b', '2');
      await store.deleteAll();
      expect(await store.keys(), isEmpty);
      expect(await store.read('a'), isNull);
    });

    test('the keys are a copy, and two stores share nothing', () async {
      final store = InMemorySecretStore();
      await store.write('a', '1');
      final keys = await store.keys()
        ..add('b');
      expect(keys, {'a', 'b'});
      expect(await store.keys(), {'a'});
      expect(await InMemorySecretStore().read('a'), isNull);
    });
  });

  group('AuthorizationWindow', () {
    final redirectUri = Uri.parse('com.example.app:/oauth2redirect');
    Uri authorizationUri(Uri redirect) => Uri.https(
      'login.example.com',
      '/authorize',
      {'redirect_uri': '$redirect', 'state': 's1'},
    );

    test('completes with the redirect', () async {
      final AuthorizationWindow window = _Window();
      final redirect = await window.authorize(
        redirectUri: redirectUri,
        authorizationUri: authorizationUri,
      );
      expect(redirect.queryParameters, {'code': 'c0de', 'state': 's1'});
      expect(redirect.scheme, 'com.example.app');
    });

    test('a closed page is an AuthorizationCancelledException', () async {
      await expectLater(
        _Window(cancelled: true).authorize(
          redirectUri: redirectUri,
          authorizationUri: authorizationUri,
        ),
        throwsA(
          isA<AuthorizationCancelledException>().having(
            (e) => e.message,
            'message',
            'closed',
          ),
        ),
      );
    });

    test('the exception names itself, with its message when it has one', () {
      const plain = AuthorizationCancelledException();
      expect(plain.message, isNull);
      expect('$plain', 'AuthorizationCancelledException');
      expect(
        '${const AuthorizationCancelledException('the user closed the page')}',
        'AuthorizationCancelledException: the user closed the page',
      );
      expect(plain, isA<Exception>());
    });
  });

  group('LoginSession', () {
    test('a login, its token, its changes and its logout', () async {
      final store = InMemorySecretStore();
      final session = _StoredLoginSession(store);
      final LoginSession login = session;
      final changes = <String?>[];
      final subscription = login.authenticationChanges.listen(
        (authentication) => changes.add(authentication?.name),
      );
      expect(login.isLoggedIn, isFalse);
      expect(login.authentication, isNull);
      expect(await login.accessToken(), isNull);
      expect(await login.restore(), isNull);

      await session.login('ada', 'token-1');
      expect(login.isLoggedIn, isTrue);
      expect(login.authentication!.name, 'ada');
      expect(await login.accessToken(), 'token-1');

      await login.logout();
      expect(login.isLoggedIn, isFalse);
      expect(login.authentication, isNull);
      expect(await login.accessToken(), isNull);
      expect(await store.keys(), isEmpty);
      await login.logout();

      await pumpEventQueue();
      expect(changes, ['ada', null]);
      await subscription.cancel();
    });

    test('restore brings back the login of the last run', () async {
      final store = InMemorySecretStore();
      await _StoredLoginSession(store).login('ada', 'token-1');
      final LoginSession restarted = _StoredLoginSession(store);
      expect(restarted.isLoggedIn, isFalse);
      final restored = await restarted.restore();
      expect(restored!.name, 'ada');
      expect(restarted.isLoggedIn, isTrue);
      expect(await restarted.accessToken(), 'token-1');
    });
  });
}
