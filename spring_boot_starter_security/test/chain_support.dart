// A hand-built security chain over an in-memory session store: the tests of
// the filters and of the HttpSecurity options use it to see one setting at
// work without a generated application.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';

/// What a request got: the response, and whether (and as whom) it reached
/// the application behind the chain.
final class Reply {
  /// A reply.
  Reply(this.response, this.reached, this.authentication);

  /// The response.
  final MockServerHttpResponse response;

  /// Whether the application behind the chain ran.
  final bool reached;

  /// The authentication the application saw.
  final Authentication? authentication;

  /// The status code.
  int get status => response.statusCode;

  /// A response header.
  String? header(String name) => response.headers[name];

  /// The body.
  String get body => response.bodyText;

  /// The cookie [name] set, or `null`.
  ResponseCookie? cookie(String name) =>
      response.cookies.where((c) => c.name == name).lastOrNull;

  /// The hidden `_csrf` field of the page.
  String get csrfField =>
      RegExp('name="_csrf" type="hidden" value="([^"]+)"')
          .firstMatch(body)![1]!;
}

/// A request and response with sessions of [sessions] attached.
Future<(MockServerHttpRequest, MockServerHttpResponse)> exchange(
  HttpSessionManager sessions, {
  HttpMethod method = HttpMethod.get,
  String path = '/',
  Map<String, String> headers = const {},
  Map<String, String> cookies = const {},
}) async {
  final request = MockServerHttpRequest(method, path);
  for (final MapEntry(:key, :value) in headers.entries) {
    request.headers.set(key, value);
  }
  for (final MapEntry(:key, :value) in cookies.entries) {
    request.addCookie(key, value);
  }
  final response = MockServerHttpResponse();
  await sessions.attach(request, response);
  return (request, response);
}

/// Makes [request] post [form].
void setForm(MockServerHttpRequest request, Map<String, String> form) {
  request.headers.set(
    HttpHeaders.contentTypeHeader,
    'application/x-www-form-urlencoded',
  );
  request.setBody(
    [
      for (final MapEntry(:key, :value) in form.entries)
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
    ].join('&'),
  );
}

/// A manager of in-memory sessions with the default cookie.
HttpSessionManager newSessions() => HttpSessionManager(
  InMemoryHttpSessionRepository(),
  const HttpSessionProperties(),
);

/// A browser over `chain`: keeps cookies, sends them back.
final class ChainClient {
  /// A client of [chain]; [sessions] to share them between clients. With
  /// [contextPath], requests are sent to paths under it and the chain sees
  /// them without it, as behind the web starter's dispatcher.
  ChainClient(
    SecurityFilterChain chain, {
    HttpSessionManager? sessions,
    this.contextPath = '',
  }) : sessions = sessions ?? newSessions(),
       _proxy = FilterChainProxy([chain]);

  /// The session store behind the chain.
  final HttpSessionManager sessions;

  /// The context path the chain does not see; `''` for none.
  final String contextPath;

  final FilterChainProxy _proxy;

  /// The cookies it holds.
  final cookies = <String, String>{};

  /// Performs a request; [form] is sent as a form body.
  Future<Reply> send(
    HttpMethod method,
    String path, {
    Map<String, String> headers = const {},
    Map<String, String>? form,
    bool withCookies = true,
  }) async {
    final (request, response) = await exchange(
      sessions,
      method: method,
      path: path,
      headers: headers,
      cookies: withCookies ? cookies : const {},
    );
    if (form != null) {
      setForm(request, form);
    }
    final application = Application();
    await _proxy.doFilter(
      contextPath.isEmpty ? request : ContextPathRequest(request, contextPath),
      response,
      application,
    );
    for (final cookie in response.cookies) {
      if (cookie.maxAge == Duration.zero) {
        cookies.remove(cookie.name);
      } else {
        cookies[cookie.name] = cookie.value;
      }
    }
    return Reply(response, application.reached, application.seen);
  }

  /// How many sessions the store keeps.
  int get storedSessions =>
      (sessions.repository as InMemoryHttpSessionRepository).size;

  /// Makes the application start a session for this client (the chain
  /// itself starts none before a login); returns the session id.
  Future<String> startSession() async {
    final (request, response) = await exchange(sessions, cookies: cookies);
    final id = request.getSession()!.id;
    for (final cookie in response.cookies) {
      cookies[cookie.name] = cookie.value;
    }
    return id;
  }

  /// GET [path] accepting [accept].
  Future<Reply> get(
    String path, {
    String accept = 'text/html',
    Map<String, String> headers = const {},
  }) => send(HttpMethod.get, path, headers: {'accept': accept, ...headers});

  /// POST [path] with [form].
  Future<Reply> post(
    String path,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) => send(HttpMethod.post, path, form: form, headers: headers);

  /// A login through `/login` (the page first, for its token).
  Future<Reply> login(
    String username,
    String password, {
    String page = '/login',
    String action = '/login',
    String usernameField = 'username',
    String passwordField = 'password',
  }) async {
    final token = (await get(page)).csrfField;
    return await post(action, {
      usernameField: username,
      passwordField: password,
      '_csrf': token,
    });
  }
}

/// [delegate] as the dispatcher passes it on behind [contextPath]: its
/// [path] without the context path, its `uri` whole.
final class ContextPathRequest extends ServerHttpRequestDecorator {
  /// The request [delegate] under [contextPath].
  ContextPathRequest(super.delegate, this.contextPath);

  /// The context path, such as `/shop`.
  final String contextPath;

  @override
  String get path {
    final full = delegate.path;
    if (!full.startsWith(contextPath)) {
      return full;
    }
    final rest = full.substring(contextPath.length);
    return rest.isEmpty ? '/' : rest;
  }
}

/// The application behind a chain: answers `200 ok` and notes who asked.
final class Application implements WebFilterChain {
  /// Whether a request reached it.
  bool reached = false;

  /// The authentication it saw.
  Authentication? seen;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    reached = true;
    seen = SecurityContextHolder.getContext().authentication;
    response
      ..statusCode = HttpStatus.ok
      ..write('ok');
    await response.close();
  }
}

/// `Authorization: Basic` for [user] and [password].
Map<String, String> basicHeader(String user, String password) => {
  'authorization': 'Basic ${base64.encode(utf8.encode('$user:$password'))}',
};

/// The users `ada` (USER) and `root` (ADMIN), with `-pw` passwords.
UserDetailsService testUsers() => InMemoryUserDetailsManager([
  User.withUsername('ada').password('{noop}ada-pw').roles(['USER']).build(),
  User.withUsername('root').password('{noop}root-pw').roles(['ADMIN']).build(),
]);

/// An [HttpSecurity] without beans, over [testUsers].
HttpSecurity newHttp({String contextPath = ''}) =>
    HttpSecurity(null, contextPath: contextPath)
      ..userDetailsService(testUsers());

/// The types of the filters of [chain], in order.
List<Type> filterTypes(SecurityFilterChain chain) => [
  for (final f in chain.filters) f.runtimeType,
];
