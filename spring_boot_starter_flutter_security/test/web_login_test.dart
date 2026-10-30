// The web login in server mode (backend-for-frontend), on the VM: the
// page (address, cookies, navigation) is a fake, the server a
// MockHttpTransport. The properties, the CSRF transport, and the
// contracts of login (navigation), restore (the user endpoint) and logout
// (the logout answer).
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_flutter_security/src/web/browser_page.dart'
    show cookieValue;
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show MockHttpTransport;

/// The page at [location], with cookies scripts may read.
final class FakePage implements BrowserPage {
  FakePage([String location = 'http://localhost:5050/'])
    : location = Uri.parse(location);

  @override
  final Uri location;

  final cookies = <String, String>{};
  final visited = <Uri>[];

  @override
  String? cookie(String name) => cookies[name];

  @override
  void navigate(Uri url) => visited.add(url);
}

final class _Events implements ApplicationEventPublisher {
  final events = <Object>[];

  @override
  void publishEvent<T extends Object>(T event) => events.add(event);
}

FlutterWebSecurityProperties bind(Map<String, String> values) =>
    FlutterWebSecurityProperties.bind(
      StandardEnvironment()
        ..propertySources.addFirst(MapPropertySource('test', values)),
    );

void main() {
  group('properties', () {
    test('defaults: server mode, same origin, Spring paths', () {
      final properties = bind({});
      expect(properties.mode, WebLoginMode.server);
      expect(properties.serverUrl, isNull);
      expect(properties.userEndpoint, '/user');
      expect(properties.logoutUrl, '/logout');
      expect(properties.authorizationBaseUri, '/oauth2/authorization');
      final page = Uri.parse('https://shop.neon.books/app/#/basket');
      expect(properties.server(page).toString(), 'https://shop.neon.books');
      expect(properties.credentials(page), FetchCredentials.sameOrigin);
    });

    test('a server on another origin gets the cookies asked for', () {
      final properties = bind({
        'spring.flutter.security.web.server-url': 'http://localhost:8080',
        'spring.flutter.security.web.user-endpoint': '/api/me',
        'spring.flutter.security.web.logout-url': '/api/logout',
      });
      final page = Uri.parse('http://localhost:5050/');
      expect(properties.credentials(page), FetchCredentials.include);
      expect(
        properties.credentials(Uri.parse('http://localhost:8080/')),
        FetchCredentials.sameOrigin,
      );
      expect(properties.userEndpoint, '/api/me');
      expect(properties.logoutUrl, '/api/logout');
    });

    test('spa is a mode; other values stop the start', () {
      expect(
        bind({'spring.flutter.security.web.mode': 'spa'}).mode,
        WebLoginMode.spa,
      );
      expect(
        () => bind({'spring.flutter.security.web.mode': 'bff'}),
        throwsArgumentError,
      );
    });

    test('unusable URLs stop the start', () {
      for (final bad in ['localhost:8080', 'ftp://x', 'http://x/?a=1', '/']) {
        expect(
          () => bind({'spring.flutter.security.web.server-url': bad}),
          throwsArgumentError,
          reason: bad,
        );
      }
      expect(
        () => bind({'spring.flutter.security.web.logout-url': 'logout'}),
        throwsArgumentError,
      );
      expect(
        () => bind({
          'spring.flutter.security.web.logout-url': 'javascript:alert(1)',
        }),
        throwsArgumentError,
      );
    });

    test('paths go after the server path, absolute URLs stay', () {
      final server = Uri.parse('https://neon.books/bff/');
      expect(
        FlutterWebSecurityProperties.resolve(server, '/user').toString(),
        'https://neon.books/bff/user',
      );
      expect(
        FlutterWebSecurityProperties.resolve(
          server,
          'https://id.neon.books/me',
        ).toString(),
        'https://id.neon.books/me',
      );
    });

    test('cookies of document.cookie, decoded', () {
      const cookies = 'theme=dark; XSRF-TOKEN=a%2Fb%3D; other=1';
      expect(cookieValue(cookies, 'XSRF-TOKEN'), 'a/b=');
      expect(cookieValue(cookies, 'theme'), 'dark');
      expect(cookieValue(cookies, 'TOKEN'), isNull);
      expect(cookieValue('', 'XSRF-TOKEN'), isNull);
      expect(cookieValue('XSRF-TOKEN=%E0%A4%A', 'XSRF-TOKEN'), '%E0%A4%A');
    });
  });

  group('CsrfCookieHttpTransport', () {
    late MockHttpTransport network;
    late FakePage page;
    late CsrfCookieHttpTransport transport;

    setUp(() {
      network = MockHttpTransport();
      page = FakePage()..cookies['XSRF-TOKEN'] = 'token-1';
      transport = CsrfCookieHttpTransport(
        network,
        page: page,
        server: Uri.parse('http://localhost:8080'),
      );
      network
        ..when(HttpMethod.post, '/api/orders').respond(201)
        ..when(HttpMethod.get, '/api/orders').respond(200)
        ..when(HttpMethod.delete, '/api/orders/1').respond(204);
    });

    Future<HttpRequest> sent(HttpMethod method, String url) async {
      await transport.send(HttpRequest(method: method, url: Uri.parse(url)));
      return network.requests.last;
    }

    test('unsafe requests to the server carry the token', () async {
      final post = await sent(
        HttpMethod.post,
        'http://localhost:8080/api/orders',
      );
      expect(post.headers['X-XSRF-TOKEN'], 'token-1');
      final delete = await sent(
        HttpMethod.delete,
        'http://localhost:8080/api/orders/1',
      );
      expect(delete.headers['X-XSRF-TOKEN'], 'token-1');
      await transport.stream(
        HttpRequest(
          method: HttpMethod.post,
          url: Uri.parse('http://localhost:8080/api/orders'),
        ),
      );
      expect(network.requests.last.headers['X-XSRF-TOKEN'], 'token-1');
    });

    test('safe requests carry none', () async {
      final get = await sent(
        HttpMethod.get,
        'http://localhost:8080/api/orders',
      );
      expect(get.headers['X-XSRF-TOKEN'], isNull);
    });

    test('never to another origin: the provider, another port', () async {
      for (final url in [
        'http://localhost:8180/api/orders',
        'https://localhost:8080/api/orders',
        'http://evil.test:8080/api/orders',
      ]) {
        final post = await sent(HttpMethod.post, url);
        expect(post.headers['X-XSRF-TOKEN'], isNull, reason: url);
      }
    });

    test('relative URLs go to the page, which is no server here', () async {
      final post = await sent(HttpMethod.post, '/api/orders');
      expect(post.headers['X-XSRF-TOKEN'], isNull);
      final same = CsrfCookieHttpTransport(
        network,
        page: FakePage('http://localhost:8080/')
          ..cookies['XSRF-TOKEN'] = 'token-2',
        server: Uri.parse('http://localhost:8080'),
      );
      await same.send(
        HttpRequest(method: HttpMethod.post, url: Uri.parse('/api/orders')),
      );
      expect(network.requests.last.headers['X-XSRF-TOKEN'], 'token-2');
    });

    test('without the cookie, or with a header of its own: as it is', () async {
      page.cookies.clear();
      final post = await sent(
        HttpMethod.post,
        'http://localhost:8080/api/orders',
      );
      expect(post.headers['X-XSRF-TOKEN'], isNull);
      page.cookies['XSRF-TOKEN'] = 'token-1';
      await transport.send(
        HttpRequest(
          method: HttpMethod.post,
          url: Uri.parse('http://localhost:8080/api/orders'),
          headers: HttpHeaders({'X-XSRF-TOKEN': 'own'}),
        ),
      );
      expect(network.requests.last.headers['X-XSRF-TOKEN'], 'own');
    });
  });

  group('ServerCredentialsHttpTransport', () {
    late MockHttpTransport toServer;
    late MockHttpTransport toOthers;
    late ServerCredentialsHttpTransport transport;
    final created = <FetchCredentials>[];

    setUp(() {
      created.clear();
      toServer = MockHttpTransport();
      toOthers = MockHttpTransport();
      for (final network in [toServer, toOthers]) {
        network
          ..when(HttpMethod.get, '/api/books').respond(200)
          ..when(HttpMethod.get, '/v1/forecast').respond(200);
      }
      transport = ServerCredentialsHttpTransport.forPage(
        page: FakePage('http://localhost:5050/'),
        server: Uri.parse('http://localhost:8080'),
        create: (credentials) {
          created.add(credentials);
          return credentials == FetchCredentials.include ? toServer : toOthers;
        },
      );
    });

    Future<void> get(String url) => transport.send(
      HttpRequest(method: HttpMethod.get, url: Uri.parse(url)),
    );

    test('one fetch with the cookies, one without', () {
      expect(created, [FetchCredentials.include, FetchCredentials.sameOrigin]);
    });

    test("the cookies go to the server's origin only", () async {
      await get('http://localhost:8080/api/books');
      await get('HTTP://LOCALHOST:8080/api/books');
      await transport.stream(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('http://localhost:8080/api/books'),
        ),
      );
      expect(toServer.requests, hasLength(3));
      expect(toOthers.requests, isEmpty);

      // A public API (Access-Control-Allow-Origin: *), the provider,
      // another port or scheme of the server's host: no cookies.
      for (final url in [
        'https://api.open-meteo.com/v1/forecast',
        'http://localhost:8180/api/books',
        'https://localhost:8080/api/books',
      ]) {
        await get(url);
      }
      expect(toOthers.requests, hasLength(3));
      expect(toServer.requests, hasLength(3));
    });

    test("relative URLs are the page's origin", () async {
      await get('/api/books');
      expect(toOthers.requests, hasLength(1));
      final samePage = ServerCredentialsHttpTransport(
        serverTransport: toServer,
        otherTransport: toOthers,
        page: FakePage('http://localhost:8080/'),
        server: Uri.parse('http://localhost:8080'),
      );
      await samePage.send(
        HttpRequest(method: HttpMethod.get, url: Uri.parse('/api/books')),
      );
      expect(toServer.requests, hasLength(1));
    });

    test('close closes both', () {
      final closed = <String>[];
      ServerCredentialsHttpTransport(
        serverTransport: _Closing(() => closed.add('server')),
        otherTransport: _Closing(() => closed.add('other')),
        page: FakePage(),
        server: Uri.parse('http://localhost:8080'),
      ).close();
      expect(closed, ['server', 'other']);
    });
  });

  group('ServerOAuth2LoginService', () {
    late MockHttpTransport server;
    late FakePage page;
    late _Events events;
    late SecurityContextHolderStrategy strategy;

    ServerOAuth2LoginService service([
      FlutterWebSecurityProperties properties =
          const FlutterWebSecurityProperties(
            serverUrl: 'http://localhost:8080',
          ),
    ]) => ServerOAuth2LoginService(
      transport: server,
      page: page,
      properties: properties,
      eventPublisher: events,
      securityContextHolderStrategy: strategy,
    );

    setUp(() {
      server = MockHttpTransport();
      page = FakePage()..cookies['XSRF-TOKEN'] = 'csrf-1';
      events = _Events();
      strategy = GlobalSecurityContextHolderStrategy()..clearContext();
    });

    group('login', () {
      test('the page leaves for the server, nothing comes back', () async {
        final login = service();
        expect(await login.login('keycloak'), isNull);
        expect(
          page.visited.single.toString(),
          'http://localhost:8080/oauth2/authorization/keycloak',
        );
        expect(server.requests, isEmpty);
        expect(login.isLoggedIn, isFalse);
      });

      test('the same origin by default, any registration id', () async {
        final login = service(const FlutterWebSecurityProperties());
        await login.login('my idp', additionalParameters: {'prompt': 'login'});
        expect(
          page.visited.single.toString(),
          'http://localhost:5050/oauth2/authorization/my%20idp?prompt=login',
        );
        expect(() => login.login(''), throwsArgumentError);
      });

      test('a server with a context path and its own base URI', () async {
        await service(
          const FlutterWebSecurityProperties(
            serverUrl: 'https://neon.books/bff',
            authorizationBaseUri: '/login/sso',
          ),
        ).login('github');
        expect(
          page.visited.single.toString(),
          'https://neon.books/bff/login/sso/github',
        );
      });
    });

    group('restore: the user endpoint', () {
      test('an OAuth2 login of the server: name, authorities, '
          'attributes', () async {
        server
            .when(HttpMethod.get, 'http://localhost:8080/user')
            .respond(
              200,
              json: {
                'name': 'ada',
                'registrationId': 'keycloak',
                'authorities': [
                  'ROLE_USER',
                  {'authority': 'OIDC_USER'},
                  42,
                ],
                'attributes': {'email': 'ada@neon.books', 'sub': 'f81d'},
                'extra': true,
              },
            );
        final login = service();
        final changes = <Authentication?>[];
        login.authenticationChanges.listen(changes.add);

        final user = await login.restore();

        expect(user, isA<OAuth2AuthenticationToken>());
        final token = user! as OAuth2AuthenticationToken;
        expect(token.name, 'ada');
        expect(token.authorizedClientRegistrationId, 'keycloak');
        expect(token.authorities.map((a) => a.authority), [
          'ROLE_USER',
          'OIDC_USER',
        ]);
        expect(token.principal.getAttribute<String>('email'), 'ada@neon.books');
        expect(strategy.getContext().authentication, same(user));
        expect(login.authentication, same(user));
        expect(changes, [user]);
        expect(events.events.single, isA<AuthenticationSuccessEvent>());
        final request = server.requests.single;
        expect(request.followRedirects, isFalse);
        expect(request.headers['Accept'], 'application/json');
      });

      test('another login of the server: a pre-authenticated user', () async {
        server
            .when(HttpMethod.get, 'http://localhost:8080/user')
            .respond(200, json: {'name': 'root'});
        final user = await service().restore();
        expect(user, isA<PreAuthenticatedAuthenticationToken>());
        expect(user!.name, 'root');
        expect(user.authorities, isEmpty);
        expect(user.principal, isA<OAuth2User>());
      });

      test('401, 403, 204 and redirects: nobody, a stale user '
          'removed', () async {
        for (final status in [401, 403, 204, 302, 0]) {
          strategy.setContext(
            SecurityContextImpl(
              TestingAuthenticationToken('stale', null, ['ROLE_USER']),
            ),
          );
          server
            ..reset()
            ..when(HttpMethod.get, 'http://localhost:8080/user').respond(
              status,
            );
          expect(await service().restore(), isNull, reason: '$status');
          expect(strategy.getContext().authentication, isNull);
        }
        expect(events.events, isEmpty);
      });

      test('errors: nobody, the context left alone', () async {
        final kept = TestingAuthenticationToken('kept', null, ['ROLE_USER']);
        strategy.setContext(SecurityContextImpl(kept));
        server
          ..when(HttpMethod.get, 'http://localhost:8080/user').respond(500)
          ..when(HttpMethod.get, 'http://localhost:8080/user').respond(404)
          ..when(
            HttpMethod.get,
            'http://localhost:8080/user',
          ).respond(200, body: '<html>')
          ..when(
            HttpMethod.get,
            'http://localhost:8080/user',
          ).respond(200, json: {'name': ''})
          ..when(
            HttpMethod.get,
            'http://localhost:8080/user',
          ).respond(200, json: ['ada']);
        final login = service();
        for (var i = 0; i < 5; i++) {
          expect(await login.restore(), isNull);
        }
        server
          ..reset()
          ..when(
            HttpMethod.get,
            'http://localhost:8080/user',
          ).fail(HttpTransportException('connection refused'));
        expect(await login.restore(), isNull);
        expect(strategy.getContext().authentication, same(kept));
      });
    });

    group('logout: the logout answer', () {
      void loggedIn() => strategy.setContext(
        SecurityContextImpl(
          TestingAuthenticationToken('ada', null, ['ROLE_USER']),
        ),
      );

      test('JSON logoutUrl: the page goes to the provider', () async {
        loggedIn();
        server
            .when(HttpMethod.post, 'http://localhost:8080/logout')
            .respond(
              200,
              json: {
                'logoutUrl':
                    'http://localhost:8180/realms/neon/logout?id_token_hint=x',
              },
            );
        final login = service();
        final changes = <Authentication?>[];
        login.authenticationChanges.listen(changes.add);

        await login.logout();

        final post = server.requests.single;
        expect(post.headers['X-XSRF-TOKEN'], 'csrf-1');
        expect(post.followRedirects, isFalse);
        expect(strategy.getContext().authentication, isNull);
        expect(changes, [null]);
        expect(events.events.single, isA<LogoutSuccessEvent>());
        expect(
          page.visited.single.toString(),
          'http://localhost:8180/realms/neon/logout?id_token_hint=x',
        );
      });

      test('a Location on 202 Accepted: the page goes there', () async {
        loggedIn();
        server
            .when(HttpMethod.post, 'http://localhost:8080/logout')
            .respond(
              202,
              headers: {'Location': 'https://id.neon.books/logout?x=1'},
            );
        await service().logout();
        expect(
          page.visited.single.toString(),
          'https://id.neon.books/logout?x=1',
        );
      });

      test('204 or a redirect: the server session only', () async {
        for (final status in [204, 302, 0]) {
          loggedIn();
          server
            ..reset()
            ..when(
              HttpMethod.post,
              'http://localhost:8080/logout',
            ).respond(status);
          await service().logout();
          expect(strategy.getContext().authentication, isNull);
        }
        expect(page.visited, isEmpty);
        expect(events.events, hasLength(3));
      });

      test('never a javascript: or data: URL', () async {
        for (final url in ['javascript:alert(1)', 'data:text/html,x']) {
          server
            ..reset()
            ..when(
              HttpMethod.post,
              'http://localhost:8080/logout',
            ).respond(200, json: {'logoutUrl': url});
          await service().logout();
        }
        expect(page.visited, isEmpty);
      });

      test('refused or unreachable: logged out here all the same', () async {
        loggedIn();
        server
            .when(HttpMethod.post, 'http://localhost:8080/logout')
            .respond(
              403,
              json: {'logoutUrl': 'https://id.neon.books/logout'},
            );
        await service().logout();
        expect(strategy.getContext().authentication, isNull);
        expect(page.visited, isEmpty);

        loggedIn();
        server
          ..reset()
          ..when(
            HttpMethod.post,
            'http://localhost:8080/logout',
          ).fail(HttpTransportException('offline'));
        await service().logout();
        expect(strategy.getContext().authentication, isNull);
        expect(events.events, hasLength(2));
      });

      test('nobody known here: the post goes all the same, no event', () async {
        server
            .when(HttpMethod.post, 'http://localhost:8080/api/logout')
            .respond(204);
        await service(
          const FlutterWebSecurityProperties(
            serverUrl: 'http://localhost:8080',
            logoutUrl: '/api/logout',
          ),
        ).logout();
        expect(server.requests.single.url.path, '/api/logout');
        expect(events.events, isEmpty);
      });
    });

    test('one restore or logout at a time', () async {
      server.when(HttpMethod.get, 'http://localhost:8080/user').respond(401);
      final login = service();
      final first = login.restore();
      expect(login.logout, throwsStateError);
      expect(() => login.login('keycloak'), throwsStateError);
      await first;
    });
  });
}

final class _Closing implements HttpTransport {
  _Closing(this.onClose);
  final void Function() onClose;

  @override
  void close() => onClose();

  @override
  Future<HttpResponse> send(HttpRequest request) => throw UnimplementedError();

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      throw UnimplementedError();
}
