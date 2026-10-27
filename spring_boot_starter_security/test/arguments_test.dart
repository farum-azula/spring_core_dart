// What a controller parameter gets of the current user (the argument
// resolver) and what `request.principal` is (the aware request filter):
// never an anonymous user, never a principal of another type.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

final class _NoBeans implements BeanFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

MethodParameter _parameter(
  TypeInfo<Object?> type, [
  List<Object> annotations = const [],
]) => HandlerMethod(
  beanName: 'controller',
  beanTypeName: 'Controller',
  method: BeanMethod<Object>(
    'handle',
    invoke: (bean, arguments) => null,
    parameters: [BeanParameter('p', type: type, annotations: annotations)],
  ),
  classAnnotations: const [],
  beanFactory: _NoBeans(),
).parameters.single;

Authentication _user(Object? principal) =>
    UsernamePasswordAuthenticationToken.authenticated(
      principal,
      null,
      AuthorityUtils.createAuthorityList(['ROLE_USER']),
    );

final _anonymous = AnonymousAuthenticationToken(
  'key',
  'anonymousUser',
  AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
);

final User _ada = User.withUsername('ada')
    .password('{noop}x')
    .roles(['USER'])
    .build();

Object? _resolve(MethodParameter parameter, Authentication? authentication) =>
    SecurityContextHolder.runWithContext(
      () => const SecurityArgumentResolver().resolveArgument(
        parameter,
        MockServerHttpRequest(HttpMethod.get, '/'),
        MockServerHttpResponse(),
      ),
      SecurityContextImpl(authentication),
    );

final class _Chain implements WebFilterChain {
  _Chain(this.body);

  final void Function(ServerHttpRequest request) body;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async => body(request);
}

void main() {
  group('an Authentication parameter', () {
    final parameter = _parameter(const ClassType<Authentication>());

    test('gets the user', () {
      final user = _user(_ada);
      expect(_resolve(parameter, user), same(user));
    });

    test('gets null for an anonymous user or none', () {
      expect(_resolve(parameter, _anonymous), isNull);
      expect(_resolve(parameter, null), isNull);
    });

    test('gets null when the user is of another type', () {
      final jwtOnly = _parameter(const ClassType<JwtAuthenticationToken>());
      expect(_resolve(jwtOnly, _user(_ada)), isNull);
    });
  });

  group('@AuthenticationPrincipal', () {
    final parameter = _parameter(const ClassType<UserDetails>(nullable: true), [
      const AuthenticationPrincipal(),
    ]);

    test('is off by default for invalid types', () {
      expect(const AuthenticationPrincipal().errorOnInvalidType, isFalse);
    });

    test('gets the principal', () {
      expect(_resolve(parameter, _user(_ada)), same(_ada));
    });

    test('gets null for an anonymous user or none', () {
      expect(_resolve(parameter, _anonymous), isNull);
      expect(_resolve(parameter, null), isNull);
    });

    test('gets null for a principal of another type', () {
      expect(_resolve(parameter, _user('ada')), isNull);
    });

    test('errorOnInvalidType refuses a principal of another type', () {
      final strict = _parameter(const ClassType<UserDetails>(nullable: true), [
        const AuthenticationPrincipal(errorOnInvalidType: true),
      ]);
      expect(() => _resolve(strict, _user('ada')), throwsStateError);
      expect(_resolve(strict, _user(_ada)), same(_ada));
      expect(_resolve(strict, _anonymous), isNull);
    });
  });

  group('SecurityContextHolderAwareRequestFilter: request.principal', () {
    Future<T> inRequest<T>(
      Authentication? authentication,
      T Function(ServerHttpRequest request) body,
    ) async {
      late T result;
      await SecurityContextHolder.runWithContext(
        () => const SecurityContextHolderAwareRequestFilter().doFilter(
          MockServerHttpRequest(HttpMethod.get, '/'),
          MockServerHttpResponse(),
          _Chain((request) => result = body(request)),
        ),
        SecurityContextImpl(authentication),
      );
      return result;
    }

    test('is the user', () async {
      final user = _user(_ada);
      expect(await inRequest(user, (r) => r.principal), same(user));
    });

    test('is null for an anonymous user or none', () async {
      expect(await inRequest(_anonymous, (r) => r.principal), isNull);
      expect(await inRequest(null, (r) => r.principal), isNull);
    });

    test('keeps what was assigned, null included', () async {
      final user = _user(_ada);
      expect(
        await inRequest(user, (r) {
          // The getter is read back: the assignment would return the null.
          // ignore: join_return_with_assignment
          r.principal = null;
          return r.principal;
        }),
        isNull,
      );
      final other = _user('other');
      expect(
        await inRequest(user, (r) {
          // The getter is read back: the assignment would return `other`.
          // ignore: join_return_with_assignment
          r.principal = other;
          return r.principal;
        }),
        same(other),
      );
    });
  });
}
