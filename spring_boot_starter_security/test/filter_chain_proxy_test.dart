// FilterChainProxy on its own: which chain a request gets, that a request
// no chain matches goes on without security, that a request is secured only
// once however many proxies it passes, that a refused request never reaches
// a filter, and that every request has a security context of its own.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'chain_support.dart';

final class _Mark implements WebFilter {
  _Mark(this.name, this.log, {this.stop = false});

  final String name;
  final List<String> log;
  final bool stop;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    log.add(name);
    if (stop) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }
    await chain.doFilter(request, response);
  }
}

final class _Login implements WebFilter {
  _Login(this.user);

  final String user;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    SecurityContextHolder.getContext().authentication =
        UsernamePasswordAuthenticationToken.authenticated(user, null, []);
    return chain.doFilter(request, response);
  }
}

Future<Application> _run(
  FilterChainProxy proxy,
  String path, {
  MockServerHttpRequest? request,
}) async {
  final application = Application();
  await proxy.doFilter(
    request ?? MockServerHttpRequest(HttpMethod.get, path),
    MockServerHttpResponse(),
    application,
  );
  return application;
}

void main() {
  group('chain selection', () {
    test('the first chain that matches runs, the others do not', () async {
      final log = <String>[];
      final proxy = FilterChainProxy([
        DefaultSecurityFilterChain(PathPatternRequestMatcher('/api/**'), [
          _Mark('api', log),
        ]),
        DefaultSecurityFilterChain(PathPatternRequestMatcher('/api/admin'), [
          _Mark('admin', log),
        ]),
        DefaultSecurityFilterChain(AnyRequestMatcher.instance, [
          _Mark('rest', log),
        ]),
      ]);
      await _run(proxy, '/api/admin');
      await _run(proxy, '/other');
      expect(log, ['api', 'rest']);
    });

    test('the filters run in order, then the application', () async {
      final log = <String>[];
      final proxy = FilterChainProxy([
        DefaultSecurityFilterChain(AnyRequestMatcher.instance, [
          _Mark('one', log),
          _Mark('two', log),
        ]),
      ]);
      final application = await _run(proxy, '/');
      expect(log, ['one', 'two']);
      expect(application.reached, isTrue);
    });

    test('a filter that answers stops the chain', () async {
      final log = <String>[];
      final proxy = FilterChainProxy([
        DefaultSecurityFilterChain(AnyRequestMatcher.instance, [
          _Mark('gate', log, stop: true),
          _Mark('never', log),
        ]),
      ]);
      final application = await _run(proxy, '/');
      expect(log, ['gate']);
      expect(application.reached, isFalse);
    });
  });

  group('a request no chain secures', () {
    test('without chains: goes on, with no user', () async {
      final application = await _run(FilterChainProxy(const []), '/anything');
      expect(application.reached, isTrue);
      expect(application.seen, isNull);
    });

    test('with chains that do not match: goes on, with no user', () async {
      final log = <String>[];
      final proxy = FilterChainProxy([
        DefaultSecurityFilterChain(PathPatternRequestMatcher('/api/**'), [
          _Mark('api', log),
          _Login('ada'),
        ]),
      ]);
      final application = await _run(proxy, '/public');
      expect(log, isEmpty);
      expect(application.reached, isTrue);
      expect(application.seen, isNull);
    });

    test('a chain without filters lets it on as well', () async {
      final proxy = FilterChainProxy([
        DefaultSecurityFilterChain(AnyRequestMatcher.instance, const []),
      ]);
      final application = await _run(proxy, '/');
      expect(application.reached, isTrue);
      expect(application.seen, isNull);
    });
  });

  group('a request passing twice', () {
    test('is secured once: the second proxy only passes it on', () async {
      final log = <String>[];
      final chains = [
        DefaultSecurityFilterChain(AnyRequestMatcher.instance, [
          _Mark('filter', log),
        ]),
      ];
      final inner = FilterChainProxy(chains);
      final outer = FilterChainProxy(chains);
      final application = Application();
      final request = MockServerHttpRequest(HttpMethod.get, '/');
      await outer.doFilter(
        request,
        MockServerHttpResponse(),
        _Through(inner, application),
      );
      expect(log, ['filter']);
      expect(application.reached, isTrue);
    });
  });

  group('a refused request', () {
    test('is answered 400 and reaches no filter and no application', () async {
      final log = <String>[];
      final proxy = FilterChainProxy([
        DefaultSecurityFilterChain(AnyRequestMatcher.instance, [
          _Mark('filter', log),
        ]),
      ]);
      final response = MockServerHttpResponse();
      final application = Application();
      await proxy.doFilter(
        MockServerHttpRequest(HttpMethod.get, '/a;jsessionid=1'),
        response,
        application,
      );
      expect(response.statusCode, 400);
      expect(response.headers['x-frame-options'], 'DENY');
      expect(response.headers['x-content-type-options'], 'nosniff');
      expect(response.bodyText, isEmpty);
      expect(log, isEmpty);
      expect(application.reached, isFalse);
    });

    test('a handler of your own answers it', () async {
      final seen = <String>[];
      final proxy = FilterChainProxy(
        const [],
        requestRejectedHandler: _Recording(seen),
      );
      await _run(proxy, '/a;b');
      expect(seen, hasLength(1));
      expect(seen.single, contains('";"'));
    });

    test('a firewall of your own decides what is refused', () async {
      final proxy = FilterChainProxy(
        const [],
        firewall: StrictHttpFirewall(allowSemicolon: true),
      );
      expect((await _run(proxy, '/a;b')).reached, isTrue);
    });

    test('a committed response is left alone', () async {
      final response = MockServerHttpResponse();
      await response.close();
      await const HttpStatusRequestRejectedHandler().handle(
        MockServerHttpRequest(HttpMethod.get, '/'),
        response,
        RequestRejectedException('x'),
      );
      expect(response.statusCode, isNot(400));
    });
  });

  group('the security context of a request', () {
    test('is not seen by the next request', () async {
      final proxy = FilterChainProxy([
        DefaultSecurityFilterChain(PathPatternRequestMatcher('/login'), [
          _Login('ada'),
        ]),
      ]);
      expect((await _run(proxy, '/login')).seen?.name, 'ada');
      expect((await _run(proxy, '/other')).seen, isNull);
      expect(SecurityContextHolder.getContext().authentication, isNull);
    });

    test('the default position among the web filters is -100', () {
      expect(FilterChainProxy.defaultFilterOrder, -100);
      expect(FilterChainProxy(const []).order, -100);
      expect(FilterChainProxy(const [], order: 5).order, 5);
    });

    test('the chains cannot be changed afterwards', () {
      final chains = <SecurityFilterChain>[];
      final proxy = FilterChainProxy(chains);
      chains.add(DefaultSecurityFilterChain(AnyRequestMatcher.instance, []));
      expect(proxy.chains, isEmpty);
      expect(proxy.chains.clear, throwsUnsupportedError);
    });
  });
}

final class _Through implements WebFilterChain {
  _Through(this.proxy, this.next);

  final FilterChainProxy proxy;
  final WebFilterChain next;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) => proxy.doFilter(request, response, next);
}

final class _Recording implements RequestRejectedHandler {
  _Recording(this.seen);

  final List<String> seen;

  @override
  void handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    RequestRejectedException exception,
  ) => seen.add(exception.reason);
}
