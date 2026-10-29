// Sign in with Apple's sheet in the app login: the plugin channel (mocked
// as the Swift side answers), the `native-sign-in` properties, and the
// login: the identity token verified with Apple's keys (a real
// JwkSetOidcIdTokenDecoder over a mocked JWK Set, ES256 test keys), the
// state, the nonce, the user, the code exchanged at the app's server, the
// first sign-in's name kept; and the attacks: a forged, foreign, replayed
// or stale identity token, another state, another user, a server that
// answers for someone else, a refused client.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show MockHttpTransport;

const _jwks = 'https://appleid.apple.com/auth/keys';
const _tokenUri = 'https://api.neon.test/oauth2/apple/token';
const _bundleId = 'books.neon.app';
const _sub = '000123.abcdef';

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Matcher _failsWith(String code) => throwsA(
  isA<OAuth2AuthenticationException>().having(
    (e) => e.error.errorCode,
    'errorCode',
    code,
  ),
);

/// Apple: its key signs the identity tokens, its sheet answers.
final class _FakeApple implements AppleIdSignIn {
  _FakeApple(this.now);

  DateTime now;
  final SoftwareDPoPKey key = SoftwareDPoPKey.generate();
  SoftwareDPoPKey? signWith; // another key: a forged token
  String audience = _bundleId;
  String issuer = 'https://appleid.apple.com';
  String user = _sub;
  String? tokenSubject;
  String? nonceOverride;
  String? stateOverride;
  bool dropState = false;
  bool firstAuthorization = true;
  bool cancel = false;
  Duration age = Duration.zero;
  final List<({Set<String> scopes, String nonce, String state})> requests = [];

  Map<String, Object?> get jwks => {
    'keys': [
      {...key.publicJwk, 'kid': 'apple-1', 'use': 'sig', 'alg': 'ES256'},
    ],
  };

  Future<String> identityToken(String nonce) async {
    final iat = now.subtract(age).millisecondsSinceEpoch ~/ 1000;
    final input =
        '${_b64(utf8.encode(jsonEncode({'alg': 'ES256', 'kid': 'apple-1'})))}.'
        '${_b64(utf8.encode(jsonEncode({'iss': issuer, 'aud': audience, 'sub': tokenSubject ?? user, 'iat': iat, 'exp': iat + 600, 'nonce': nonce, 'email': 'ada@privaterelay.appleid.com', 'email_verified': 'true'})))}';
    final signature = await (signWith ?? key).sign(
      Uint8List.fromList(ascii.encode(input)),
    );
    return '$input.${_b64(signature)}';
  }

  @override
  Future<AppleIdCredential> signIn({
    required Set<String> scopes,
    required String nonce,
    required String state,
  }) async {
    requests.add((scopes: scopes, nonce: nonce, state: state));
    if (cancel) {
      throw const AuthorizationCancelledException('closed');
    }
    return AppleIdCredential(
      user: user,
      authorizationCode: 'apple-code-${requests.length}',
      identityToken: await identityToken(nonceOverride ?? nonce),
      state: dropState ? null : (stateOverride ?? state),
      email: firstAuthorization ? 'ada@privaterelay.appleid.com' : null,
      givenName: firstAuthorization ? 'Ada' : null,
      familyName: firstAuthorization ? 'Lovelace' : null,
    );
  }
}

/// The app's server: its token endpoint exchanges Apple's codes.
final class _Server {
  _Server(this.transport) {
    transport.when(HttpMethod.post, _tokenUri).respondWith((request) {
      final form = Uri.splitQueryString(utf8.decode(request.body!));
      requests.add(form);
      if (error != null) {
        return _json(400, {'error': error});
      }
      return _json(200, {
        'access_token': 'server-access-${requests.length}',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'refresh_token': 'server-refresh',
        'id_token': ?idToken,
      });
    });
  }

  final MockHttpTransport transport;
  final List<Map<String, String>> requests = [];
  String? error;
  String? idToken;
}

HttpResponse _json(int status, Object body) => HttpResponse(
  status,
  headers: HttpHeaders({HttpHeaders.contentTypeHeader: 'application/json'}),
  body: utf8.encode(jsonEncode(body)),
);

final class _Window implements AuthorizationWindow {
  final List<Uri> opened = [];

  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) async {
    opened.add(authorizationUri(redirectUri));
    throw const AuthorizationCancelledException('the test stops here');
  }
}

final class _Fixture {
  _Fixture() {
    transport
        .when(HttpMethod.get, _jwks)
        .respondWith((_) => _json(200, apple.jwks));
  }

  final DateTime now = DateTime.now().toUtc();
  final MockHttpTransport transport = MockHttpTransport();
  late final _FakeApple apple = _FakeApple(now);
  late final _Server server = _Server(transport);
  final InMemorySecretStore store = InMemorySecretStore();
  final _Window window = _Window();
  final SecurityContextHolderStrategy strategy =
      GlobalSecurityContextHolderStrategy();

  late final ClientRegistration registration = CommonOAuth2Provider.apple
      .getBuilder('apple')
      .clientId(_bundleId)
      .tokenUri(_tokenUri)
      .clientAuthenticationMethod(ClientAuthenticationMethod.none)
      .build();

  late final InMemoryClientRegistrationRepository repository =
      InMemoryClientRegistrationRepository([registration]);

  late final SecretStoreOAuth2AuthorizedClientService clients =
      SecretStoreOAuth2AuthorizedClientService(store, repository);

  NativeOAuth2LoginService service({
    bool withSheet = true,
    Map<String, NativeSignIn> nativeSignIn = const {
      'apple': NativeSignIn.apple,
    },
  }) {
    server; // the token endpoint answers
    return NativeOAuth2LoginService(
      clientRegistrationRepository: repository,
      authorizedClientService: clients,
      secretStore: store,
      accessTokenResponseClient: DefaultAuthorizationCodeTokenResponseClient(
        transport,
      ),
      userService: DefaultOAuth2UserService(transport),
      oidcUserService: OidcUserService(transport),
      authorizationWindow: window,
      appleIdSignIn: withSheet ? apple : null,
      nativeSignIn: nativeSignIn,
      nativeIdTokenDecoder: JwkSetOidcIdTokenDecoder(
        transport,
        algorithms: const {'RS256', 'ES256'},
      ),
      idTokenDecoder: TokenEndpointOidcIdTokenDecoder(),
      securityContextHolderStrategy: strategy,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the sign-in', () {
    test('verifies the identity token, exchanges the code at the app '
        'server and keeps the first sign-in name', () async {
      final f = _Fixture();
      final login = f.service();
      final authentication = await login.login('apple');

      expect(authentication.name, _sub);
      expect(authentication.authorizedClientRegistrationId, 'apple');
      final user = authentication.principal as OidcUser;
      expect(user.fullName, 'Ada Lovelace');
      expect(user.givenName, 'Ada');
      expect(user.email, 'ada@privaterelay.appleid.com');
      expect(f.window.opened, isEmpty, reason: 'no browser');

      // The sheet got the scopes, the hash of the nonce, the state.
      final sheet = f.apple.requests.single;
      expect(sheet.scopes, containsAll(['name', 'email']));
      expect(sheet.nonce, hasLength(43));
      expect(sheet.state.length, greaterThanOrEqualTo(43));

      // The app's server got the code as a public client: no secret.
      final form = f.server.requests.single;
      expect(form['grant_type'], 'authorization_code');
      expect(form['code'], 'apple-code-1');
      expect(form['client_id'], _bundleId);
      expect(form.containsKey('client_secret'), isFalse);
      expect(form.containsKey('code_verifier'), isFalse);
      expect(form.containsKey('redirect_uri'), isFalse);

      final stored = await f.clients.loadAuthorizedClient('apple', _sub);
      expect(stored!.accessToken.tokenValue, 'server-access-1');
      expect(stored.idToken?.subject, _sub);
      expect(f.strategy.getContext().authentication, same(authentication));
    });

    test('a later sign-in without the name keeps the stored one, and '
        'restore brings it back', () async {
      final f = _Fixture();
      await f.service().login('apple');
      f.apple.firstAuthorization = false;
      final again = await f.service().login('apple');
      expect((again.principal as OidcUser).fullName, 'Ada Lovelace');
      final restored = await f.service().restore();
      expect((restored!.principal as OidcUser).fullName, 'Ada Lovelace');
    });

    test('the cancelled sheet logs nobody in', () async {
      final f = _Fixture();
      f.apple.cancel = true;
      final login = f.service();
      await expectLater(
        login.login('apple'),
        throwsA(isA<AuthorizationCancelledException>()),
      );
      expect(login.isLoggedIn, isFalse);
      expect(f.server.requests, isEmpty);
    });

    test('without the sheet (Android, desktops) or with native-sign-in=none '
        'the browser opens', () async {
      final f = _Fixture();
      final apple = f.registration;
      final query = InMemoryClientRegistrationRepository([
        ClientRegistration.withClientRegistration(
          apple,
        ).responseMode(ResponseMode.query).build(),
      ]);
      for (final login in [
        f.service(withSheet: false),
        f.service(nativeSignIn: const {}),
      ]) {
        final browser = NativeOAuth2LoginService(
          clientRegistrationRepository: query,
          authorizedClientService: f.clients,
          secretStore: f.store,
          accessTokenResponseClient: login.accessTokenResponseClient,
          userService: login.userService,
          oidcUserService: login.oidcUserService,
          authorizationWindow: f.window,
          appleIdSignIn: login.appleIdSignIn,
          nativeSignIn: login.nativeSignIn,
          nativeIdTokenDecoder: login.nativeIdTokenDecoder,
        );
        await expectLater(
          browser.login('apple'),
          throwsA(isA<AuthorizationCancelledException>()),
        );
      }
      expect(f.window.opened, hasLength(2));
      expect(f.apple.requests, isEmpty);
    });

    test("an app's login window refuses a form_post registration", () async {
      final f = _Fixture();
      await expectLater(
        f.service(withSheet: false).login('apple'),
        _failsWith(OAuth2ErrorCodes.invalidRequest),
      );
      expect(f.window.opened, isEmpty);
    });
  });

  group('the attacks', () {
    Future<void> refused(
      _Fixture f,
      String code, {
      bool exchanged = false,
    }) async {
      final login = f.service();
      await expectLater(login.login('apple'), _failsWith(code));
      expect(login.isLoggedIn, isFalse);
      expect(f.strategy.getContext().authentication, isNull);
      if (!exchanged) {
        expect(f.server.requests, isEmpty, reason: 'the code stays unused');
      }
    }

    test('another state', () async {
      final f = _Fixture()..apple.stateOverride = 'forged';
      await refused(f, OAuth2ErrorCodes.invalidStateParameter);
    });

    test('no state', () async {
      final f = _Fixture()..apple.dropState = true;
      await refused(f, OAuth2ErrorCodes.invalidStateParameter);
    });

    test('an identity token signed by another key', () async {
      final f = _Fixture()..apple.signWith = SoftwareDPoPKey.generate();
      await refused(f, OAuth2ErrorCodes.invalidIdToken);
    });

    test('an identity token of another app (audience)', () async {
      final f = _Fixture()..apple.audience = 'books.neon.other';
      await expectLater(
        f.service().login('apple'),
        throwsA(isA<OAuth2AuthenticationException>()),
      );
      expect(f.server.requests, isEmpty);
    });

    test('an identity token of another issuer', () async {
      final f = _Fixture()..apple.issuer = 'https://evil.test';
      await expectLater(
        f.service().login('apple'),
        throwsA(isA<OAuth2AuthenticationException>()),
      );
      expect(f.server.requests, isEmpty);
    });

    test('an expired identity token', () async {
      final f = _Fixture()..apple.age = const Duration(hours: 1);
      await expectLater(
        f.service().login('apple'),
        throwsA(isA<OAuth2AuthenticationException>()),
      );
      expect(f.server.requests, isEmpty);
    });

    test('a replayed identity token (another nonce)', () async {
      final f = _Fixture()..apple.nonceOverride = 'an-older-nonce';
      await refused(f, OAuth2ErrorCodes.invalidNonce);
    });

    test('an identity token about another user than the sheet', () async {
      final f = _Fixture()..apple.tokenSubject = 'someone-else';
      await refused(f, OAuth2ErrorCodes.invalidIdToken);
    });

    test('a server that answers for another user', () async {
      final f = _Fixture();
      f.server.idToken = await (_FakeApple(
        f.now,
      )..user = 'someone-else').identityToken('n');
      await refused(f, OAuth2ErrorCodes.invalidIdToken, exchanged: true);
    });

    test('a refused client (the token-uri is not the app server)', () async {
      final f = _Fixture();
      f.server.error = 'invalid_client';
      await refused(f, 'invalid_client', exchanged: true);
    });

    test('the credential never shows its code or token', () {
      const credential = AppleIdCredential(
        user: _sub,
        authorizationCode: 'secret-code',
        identityToken: 'secret.token.value',
      );
      expect('$credential', isNot(contains('secret')));
    });
  });

  group('the properties', () {
    Environment environment(Map<String, Object> values) {
      final env = StandardEnvironment()
        ..propertySources.addFirst(MapPropertySource('test', values));
      ConfigurationPropertySources.attach(env);
      return env;
    }

    const r = 'spring.security.oauth2.client.registration';

    test('apple by default for the apple provider, explicit otherwise', () {
      expect(
        NativeSignIn.of(
          environment({
            '$r.apple.client-id': 'a',
            '$r.siwa.client-id': 'b',
            '$r.siwa.provider': 'apple',
            '$r.keycloak.client-id': 'c',
            '$r.web-apple.client-id': 'd',
            '$r.web-apple.provider': 'apple',
            '$r.web-apple.native-sign-in': 'none',
          }),
        ),
        {'apple': NativeSignIn.apple, 'siwa': NativeSignIn.apple},
      );
    });

    test('an unknown value fails', () {
      expect(
        () => NativeSignIn.of(
          environment({
            '$r.apple.client-id': 'a',
            '$r.apple.native-sign-in': 'google',
          }),
        ),
        throwsArgumentError,
      );
    });
  });

  group('the plugin channel', () {
    final calls = <MethodCall>[];
    Object? Function(MethodCall call)? answer;

    setUp(() {
      calls.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeSignInChannel, (call) async {
            calls.add(call);
            return answer?.call(call);
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeSignInChannel, null);
    });

    test('sends the scopes, nonce and state, reads the credential', () async {
      answer = (_) => {
        'user': _sub,
        'authorizationCode': 'c',
        'identityToken': 'a.b.c',
        'state': 's',
        'givenName': 'Ada',
      };
      final credential = await const PlatformAppleIdSignIn().signIn(
        scopes: {'openid', 'name', 'email'},
        nonce: 'n',
        state: 's',
      );
      expect(calls.single.method, 'appleIdSignIn');
      expect(calls.single.arguments, {
        'scopes': ['name', 'email'],
        'nonce': 'n',
        'state': 's',
      });
      expect(credential.user, _sub);
      expect(credential.givenName, 'Ada');
      expect(credential.email, isNull);
    });

    test('maps the errors', () async {
      for (final (code, matcher) in [
        ('cancelled', isA<AuthorizationCancelledException>()),
        ('in_progress', isA<StateError>()),
        ('failed', isA<AuthorizationWindowException>()),
      ]) {
        answer = (_) => throw PlatformException(code: code, message: code);
        await expectLater(
          const PlatformAppleIdSignIn().signIn(
            scopes: const {},
            nonce: 'n',
            state: 's',
          ),
          throwsA(matcher),
        );
      }
    });

    test('an answer without a code or token is refused', () async {
      answer = (_) => {'user': _sub, 'identityToken': 'a.b.c'};
      await expectLater(
        const PlatformAppleIdSignIn().signIn(
          scopes: const {},
          nonce: 'n',
          state: 's',
        ),
        throwsA(isA<AuthorizationWindowException>()),
      );
    });

    test('elsewhere than iOS and macOS there is no sheet', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlatformAppleIdSignIn.isSupported, isFalse);
      await expectLater(
        const PlatformAppleIdSignIn().signIn(
          scopes: const {},
          nonce: 'n',
          state: 's',
        ),
        throwsUnsupportedError,
      );
    });
  });
}
