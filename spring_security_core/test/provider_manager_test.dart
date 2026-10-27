// ProviderManager's rules: which provider is asked, which failures end the
// loop (an existing account that may not log in, an internal error) and
// which only move on to the next provider, how the parent is consulted,
// what is published and erased; and DaoAuthenticationProvider's handling of
// requests it cannot check.
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

/// A provider whose answer is scripted; it remembers being asked.
final class ScriptedProvider implements AuthenticationProvider {
  ScriptedProvider(this._answer, {this.handles = true});

  /// Always succeeds as [name].
  factory ScriptedProvider.accepts(String name) => ScriptedProvider(
    (_) async => UsernamePasswordAuthenticationToken.authenticated(
      name,
      'secret',
      AuthorityUtils.createAuthorityList(['ROLE_USER']),
    ),
  );

  /// Always fails with [failure].
  factory ScriptedProvider.fails(AuthenticationException failure) =>
      ScriptedProvider((_) async => throw failure);

  /// Cannot decide.
  factory ScriptedProvider.abstains() => ScriptedProvider((_) async => null);

  final Future<Authentication?> Function(Authentication request) _answer;
  final bool handles;
  int asked = 0;

  @override
  bool supports(Authentication authentication) => handles;

  @override
  Future<Authentication?> authenticate(Authentication authentication) {
    asked++;
    return _answer(authentication);
  }
}

/// A manager answering with [answer] (a parent).
final class ScriptedManager implements AuthenticationManager {
  ScriptedManager(this.answer);

  final Future<Authentication> Function(Authentication request) answer;
  int asked = 0;

  @override
  Future<Authentication> authenticate(Authentication authentication) {
    asked++;
    return answer(authentication);
  }
}

final class RecordingEvents implements AuthenticationEventPublisher {
  final successes = <Authentication>[];
  final failures = <AuthenticationException>[];

  @override
  void publishAuthenticationSuccess(Authentication authentication) =>
      successes.add(authentication);

  @override
  void publishAuthenticationFailure(
    AuthenticationException exception,
    Authentication authentication,
  ) => failures.add(exception);
}

UsernamePasswordAuthenticationToken request([String name = 'ada']) =>
    UsernamePasswordAuthenticationToken.unauthenticated(name, 'secret');

Future<AuthenticationException> failureOf(
  AuthenticationManager manager, [
  Authentication? authentication,
]) async {
  try {
    await manager.authenticate(authentication ?? request());
  } on AuthenticationException catch (e) {
    return e;
  }
  throw StateError('authentication succeeded');
}

void main() {
  late RecordingEvents events;

  setUp(() => events = RecordingEvents());

  group('construction', () {
    test('a manager needs a provider or a parent', () {
      expect(
        () => ProviderManager([]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('provider or a parent'),
          ),
        ),
      );
    });

    test('a parent alone is enough', () async {
      final parent = ScriptedManager(
        (r) async => TestingAuthenticationToken('ada', null),
      );
      final manager = ProviderManager([], parent: parent);
      expect((await manager.authenticate(request())).name, 'ada');
    });

    test('the providers cannot be changed afterwards', () {
      final given = <AuthenticationProvider>[ScriptedProvider.accepts('ada')];
      final manager = ProviderManager(given);
      given.clear();
      expect(manager.providers, hasLength(1));
      expect(
        () => manager.providers.add(ScriptedProvider.accepts('bob')),
        throwsUnsupportedError,
      );
    });
  });

  group('the loop over the providers', () {
    test('providers that do not support the request are not asked', () async {
      final supported = ScriptedProvider.accepts('skipped');
      final unsupported = ScriptedProvider(
        (_) async => fail('must not be asked'),
        handles: false,
      );
      final manager = ProviderManager([unsupported, supported]);

      expect((await manager.authenticate(request())).name, 'skipped');
      expect(unsupported.asked, 0);
    });

    test('a provider that abstains passes to the next one', () async {
      final abstaining = ScriptedProvider.abstains();
      final accepting = ScriptedProvider.accepts('ada');
      final manager = ProviderManager([
        abstaining,
        accepting,
      ], eventPublisher: events);

      final result = await manager.authenticate(request());

      expect(result.name, 'ada');
      expect([abstaining.asked, accepting.asked], [1, 1]);
      expect(events.successes, [result]);
      expect(events.failures, isEmpty);
    });

    test('the first success wins; later providers are not asked', () async {
      final later = ScriptedProvider.accepts('later');
      final manager = ProviderManager([
        ScriptedProvider.accepts('first'),
        later,
      ]);

      expect((await manager.authenticate(request())).name, 'first');
      expect(later.asked, 0);
    });

    test('a plain failure moves on; a later success makes the login '
        'succeed and publishes no failure', () async {
      final manager = ProviderManager([
        ScriptedProvider.fails(BadCredentialsException()),
        ScriptedProvider.accepts('ada'),
      ], eventPublisher: events);

      expect((await manager.authenticate(request())).name, 'ada');
      expect(events.failures, isEmpty);
      expect(events.successes, hasLength(1));
    });

    test('when every provider fails or abstains, the last failure is '
        'thrown', () async {
      final last = UsernameNotFoundException('last');
      final manager = ProviderManager([
        ScriptedProvider.fails(BadCredentialsException('first')),
        ScriptedProvider.abstains(),
        ScriptedProvider.fails(last),
      ], eventPublisher: events);

      expect(await failureOf(manager), same(last));
      expect(events.failures, [same(last)]);
      expect(last.authenticationRequest, isA<Authentication>());
    });

    test('providers that all abstain: ProviderNotFound for the request '
        'type', () async {
      final manager = ProviderManager([
        ScriptedProvider.abstains(),
      ], eventPublisher: events);

      final failure = await failureOf(manager);

      expect(failure, isA<ProviderNotFoundException>());
      expect(failure.message, contains('UsernamePasswordAuthenticationToken'));
      expect(events.failures, [same(failure)]);
    });

    for (final (name, failure) in <(String, AuthenticationException)>[
      ('locked account', LockedException()),
      ('disabled account', DisabledException()),
      ('expired account', AccountExpiredException()),
      ('expired credentials', CredentialsExpiredException()),
      (
        'internal error',
        InternalAuthenticationServiceException('the store broke'),
      ),
    ]) {
      test('a $name stops the loop: no other provider may let the user in, '
          'and it is published once', () async {
        final next = ScriptedProvider.accepts('ada');
        final manager = ProviderManager([
          ScriptedProvider.fails(failure),
          next,
        ], eventPublisher: events);
        final attempt = request();

        expect(await failureOf(manager, attempt), same(failure));

        expect(next.asked, 0);
        expect(failure.authenticationRequest, same(attempt));
        expect(events.failures, [same(failure)]);
        expect(events.successes, isEmpty);
      });
    }

    test('a stopping failure does not ask the parent either', () async {
      final parent = ScriptedManager((_) async => fail('must not be asked'));
      final manager = ProviderManager([
        ScriptedProvider.fails(LockedException()),
      ], parent: parent);

      expect(await failureOf(manager), isA<LockedException>());
      expect(parent.asked, 0);
    });

    test(
      'an AuthenticationServiceException (not internal) only moves on',
      () async {
        final manager = ProviderManager([
          ScriptedProvider.fails(AuthenticationServiceException('flaky')),
          ScriptedProvider.accepts('ada'),
        ]);

        expect((await manager.authenticate(request())).name, 'ada');
      },
    );
  });

  group('the parent', () {
    test('is asked when no provider succeeded, and its success is '
        'published by this manager too', () async {
      final parent = ScriptedManager(
        (_) async => TestingAuthenticationToken('bob', null),
      );
      final manager = ProviderManager(
        [ScriptedProvider.fails(BadCredentialsException())],
        parent: parent,
        eventPublisher: events,
      );

      final result = await manager.authenticate(request('bob'));

      expect(result.name, 'bob');
      expect(parent.asked, 1);
      expect(events.successes, [result]);
      expect(events.failures, isEmpty);
    });

    test('is not asked after a success', () async {
      final parent = ScriptedManager((_) async => fail('must not be asked'));
      final manager = ProviderManager([
        ScriptedProvider.accepts('ada'),
      ], parent: parent);

      await manager.authenticate(request());

      expect(parent.asked, 0);
    });

    test("ProviderNotFound from the parent leaves this manager's own "
        'failure standing, published once', () async {
      final own = BadCredentialsException('own');
      final parent = ScriptedManager(
        (_) async => throw ProviderNotFoundException('parent knows none'),
      );
      final manager = ProviderManager(
        [ScriptedProvider.fails(own)],
        parent: parent,
        eventPublisher: events,
      );

      expect(await failureOf(manager), same(own));
      expect(events.failures, [same(own)]);
    });

    test('ProviderNotFound from the parent with nothing of our own: '
        'ProviderNotFound, published', () async {
      final parent = ScriptedManager(
        (_) async => throw ProviderNotFoundException('parent knows none'),
      );
      final manager = ProviderManager(
        [ScriptedProvider.abstains()],
        parent: parent,
        eventPublisher: events,
      );

      final failure = await failureOf(manager);

      expect(failure, isA<ProviderNotFoundException>());
      expect(failure.message, isNot('parent knows none'));
      expect(events.failures, [same(failure)]);
    });

    test('another failure of the parent replaces ours and is not '
        'published again (the parent published it)', () async {
      final parentEvents = RecordingEvents();
      final parentFailure = BadCredentialsException('parent says no');
      final parent = ProviderManager([
        ScriptedProvider.fails(parentFailure),
      ], eventPublisher: parentEvents);
      final manager = ProviderManager(
        [ScriptedProvider.fails(BadCredentialsException('own'))],
        parent: parent,
        eventPublisher: events,
      );

      expect(await failureOf(manager), same(parentFailure));
      expect(parentEvents.failures, [same(parentFailure)]);
      expect(events.failures, isEmpty);
    });

    test(
      'a failure of the parent with no provider of our own is thrown',
      () async {
        final locked = LockedException();
        final manager = ProviderManager(
          [],
          parent: ScriptedManager((_) async => throw locked),
        );

        expect(await failureOf(manager), same(locked));
      },
    );
  });

  group('the result', () {
    UsernamePasswordAuthenticationToken Function(Authentication) withSecrets(
      User user,
    ) =>
        (_) => UsernamePasswordAuthenticationToken.authenticated(
          user,
          'secret',
          [],
        )..details = 'detail';

    test('is stripped of credentials, also of the principal', () async {
      final user = User.withUsername('ada').password('{noop}secret').build();
      final manager = ProviderManager([
        ScriptedProvider((r) async => withSecrets(user)(r)),
      ]);

      final result = await manager.authenticate(request());

      expect(result.credentials, isNull);
      expect(user.password, isNull);
    });

    test('keeps them when asked to', () async {
      final user = User.withUsername('ada').password('{noop}secret').build();
      final manager = ProviderManager([
        ScriptedProvider((r) async => withSecrets(user)(r)),
      ], eraseCredentialsAfterAuthentication: false);

      final result = await manager.authenticate(request());

      expect(result.credentials, 'secret');
      expect(user.password, '{noop}secret');
    });

    test('a result that holds no secrets is returned as it is', () async {
      final token = TestingAuthenticationToken('ada', 'kept');
      final manager = ProviderManager([
        ScriptedProvider((_) async => token),
      ], eraseCredentialsAfterAuthentication: false);

      expect(await manager.authenticate(request()), same(token));
    });

    test(
      'without a publisher nothing is published and nothing breaks',
      () async {
        final manager = ProviderManager([
          ScriptedProvider.fails(BadCredentialsException()),
        ]);

        expect(await failureOf(manager), isA<BadCredentialsException>());
      },
    );
  });

  group('DaoAuthenticationProvider and requests it cannot check', () {
    late InMemoryUserDetailsManager users;

    DaoAuthenticationProvider provider({bool hide = true}) =>
        DaoAuthenticationProvider(
          users,
          passwordEncoder: const NoOpPasswordEncoder(),
          offloadPasswordChecks: false,
          hideUserNotFoundExceptions: hide,
        );

    setUp(() {
      users = InMemoryUserDetailsManager([
        User.withUsername('ada').password('secret').build(),
        User.withUsername('nopass').password(null).build(),
      ]);
    });

    test('supports only username/password requests', () {
      expect(provider().supports(request()), isTrue);
      expect(
        provider().supports(TestingAuthenticationToken('ada', 'secret')),
        isFalse,
      );
    });

    test('credentials that are not a string are bad credentials, for a '
        'known user', () async {
      final attempt = UsernamePasswordAuthenticationToken.unauthenticated(
        'ada',
        42,
      );
      await expectLater(
        provider().authenticate(attempt),
        throwsA(
          isA<BadCredentialsException>().having(
            (e) => e.message,
            'message',
            'Bad credentials',
          ),
        ),
      );
    });

    test('credentials that are not a string are bad credentials, for an '
        'unknown user too (the same answer)', () async {
      final attempt = UsernamePasswordAuthenticationToken.unauthenticated(
        'nobody',
        null,
      );
      await expectLater(
        provider().authenticate(attempt),
        throwsA(isA<BadCredentialsException>()),
      );
    });

    test('a user without a stored password never logs in', () async {
      await expectLater(
        provider().authenticate(
          UsernamePasswordAuthenticationToken.unauthenticated('nopass', 'x'),
        ),
        throwsA(isA<BadCredentialsException>()),
      );
    });

    test('hiding unknown users can be switched off (and keeps the cause '
        'when on)', () async {
      final unknown = UsernamePasswordAuthenticationToken.unauthenticated(
        'nobody',
        'x',
      );
      await expectLater(
        provider(hide: false).authenticate(unknown),
        throwsA(isA<UsernameNotFoundException>()),
      );
      await expectLater(
        provider().authenticate(unknown),
        throwsA(
          isA<BadCredentialsException>().having(
            (e) => e.cause,
            'cause',
            isA<UsernameNotFoundException>(),
          ),
        ),
      );
    });

    test('the details of the request move to the result', () async {
      final attempt = request()..details = {'ip': '127.0.0.1'};

      final result = (await provider().authenticate(attempt))!;

      expect(result.details, {'ip': '127.0.0.1'});
      expect(result.credentials, 'secret');
      expect(result.isAuthenticated, isTrue);
    });
  });
}
