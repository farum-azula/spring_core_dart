// Authentication events: which failure event each exception becomes (code
// that counts failed logins or locks accounts listens for these), that a
// success is published, and that a ProviderManager wired to the publisher
// emits them on real logins.
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

/// Keeps what was published.
final class RecordingApplicationEvents implements ApplicationEventPublisher {
  final events = <Object>[];

  @override
  void publishEvent<T extends Object>(T event) => events.add(event);
}

final _request = UsernamePasswordAuthenticationToken.unauthenticated(
  'ada',
  'secret',
);

void main() {
  late RecordingApplicationEvents recorder;
  late DefaultAuthenticationEventPublisher publisher;

  setUp(() {
    recorder = RecordingApplicationEvents();
    publisher = DefaultAuthenticationEventPublisher(recorder);
  });

  group('failure events by exception', () {
    // Exact types: a subclass event would also be an instance of the
    // general one, so the runtime type is what shows the right mapping.
    final cases = <String, (AuthenticationException, Type)>{
      'BadCredentialsException': (
        BadCredentialsException(),
        AuthenticationFailureBadCredentialsEvent,
      ),
      'UsernameNotFoundException': (
        UsernameNotFoundException('ada'),
        AuthenticationFailureBadCredentialsEvent,
      ),
      'DisabledException': (
        DisabledException(),
        AuthenticationFailureDisabledEvent,
      ),
      'LockedException': (LockedException(), AuthenticationFailureLockedEvent),
      'AccountExpiredException': (
        AccountExpiredException(),
        AuthenticationFailureExpiredEvent,
      ),
      'CredentialsExpiredException': (
        CredentialsExpiredException(),
        AuthenticationFailureCredentialsExpiredEvent,
      ),
      'ProviderNotFoundException': (
        ProviderNotFoundException('none'),
        AuthenticationFailureProviderNotFoundEvent,
      ),
      'AuthenticationServiceException': (
        AuthenticationServiceException('store down'),
        AuthenticationFailureServiceExceptionEvent,
      ),
      'InternalAuthenticationServiceException': (
        InternalAuthenticationServiceException('bug'),
        AuthenticationFailureServiceExceptionEvent,
      ),
      'InsufficientAuthenticationException (the fallback)': (
        InsufficientAuthenticationException(),
        AbstractAuthenticationFailureEvent,
      ),
      'AuthenticationCredentialsNotFoundException (the fallback)': (
        AuthenticationCredentialsNotFoundException(),
        AbstractAuthenticationFailureEvent,
      ),
    };

    for (final MapEntry(key: name, value: expected) in cases.entries) {
      final (exception, eventType) = expected;
      test('$name becomes $eventType', () {
        publisher.publishAuthenticationFailure(exception, _request);

        final event =
            recorder.events.single as AbstractAuthenticationFailureEvent;
        expect(event.runtimeType, eventType);
        expect(event.exception, same(exception));
        expect(event.authentication, same(_request));
        expect(event.source, same(_request));
      });
    }
  });

  test('success publishes an AuthenticationSuccessEvent for the result', () {
    final result = UsernamePasswordAuthenticationToken.authenticated(
      'ada',
      null,
      AuthorityUtils.createAuthorityList(['ROLE_USER']),
    );

    publisher.publishAuthenticationSuccess(result);

    final event = recorder.events.single as AuthenticationSuccessEvent;
    expect(event.runtimeType, AuthenticationSuccessEvent);
    expect(event.authentication, same(result));
    expect(event, isA<AbstractAuthenticationEvent>());
    expect(event, isNot(isA<AbstractAuthenticationFailureEvent>()));
  });

  test('every specific failure event is a failure event of its request', () {
    final failure = LockedException();
    final events = <AbstractAuthenticationFailureEvent>[
      AuthenticationFailureBadCredentialsEvent(_request, failure),
      AuthenticationFailureDisabledEvent(_request, failure),
      AuthenticationFailureLockedEvent(_request, failure),
      AuthenticationFailureExpiredEvent(_request, failure),
      AuthenticationFailureCredentialsExpiredEvent(_request, failure),
      AuthenticationFailureProviderNotFoundEvent(_request, failure),
      AuthenticationFailureServiceExceptionEvent(_request, failure),
    ];
    for (final event in events) {
      expect(event.exception, same(failure), reason: '${event.runtimeType}');
      expect(event.authentication, same(_request));
    }
  });

  test('login and logout events carry their authentication', () {
    final done = TestingAuthenticationToken('ada', null);
    expect(InteractiveAuthenticationSuccessEvent(done).authentication, done);
    expect(LogoutSuccessEvent(done).authentication, done);
    expect(LogoutSuccessEvent(done).source, done);
  });

  group('a ProviderManager wired to the publisher', () {
    late ProviderManager manager;

    setUp(() {
      final users = InMemoryUserDetailsManager([
        User.withUsername('ada').password('{noop}secret').build(),
        User.withUsername('locked')
            .password('{noop}secret')
            .accountLocked(true)
            .build(),
        User.withUsername('off')
            .password('{noop}secret')
            .disabled(true)
            .build(),
        User.withUsername('gone')
            .password('{noop}secret')
            .accountExpired(true)
            .build(),
        User.withUsername('stale')
            .password('{noop}secret')
            .credentialsExpired(true)
            .build(),
      ]);
      manager = ProviderManager([
        DaoAuthenticationProvider(users, offloadPasswordChecks: false),
      ], eventPublisher: publisher);
    });

    Future<Object?> login(String name, String password) async {
      try {
        return await manager.authenticate(
          UsernamePasswordAuthenticationToken.unauthenticated(name, password),
        );
      } on AuthenticationException catch (e) {
        return e;
      }
    }

    test('a good login publishes one AuthenticationSuccessEvent', () async {
      final result = (await login('ada', 'secret'))! as Authentication;

      final event = recorder.events.single as AuthenticationSuccessEvent;
      expect(event.authentication, same(result));
      expect(event.authentication.name, 'ada');
    });

    test('a wrong password and an unknown user both publish bad credentials '
        'with the request that failed', () async {
      await login('ada', 'wrong');
      await login('nobody', 'wrong');

      expect(recorder.events, hasLength(2));
      for (final event in recorder.events) {
        event as AuthenticationFailureBadCredentialsEvent;
        expect(event.exception, isA<BadCredentialsException>());
        expect(
          event.exception.authenticationRequest,
          same(event.authentication),
        );
      }
      expect(
        recorder.events.map(
          (e) => (e as AbstractAuthenticationEvent).authentication.name,
        ),
        ['ada', 'nobody'],
      );
    });

    test('account states publish their own events, once each', () async {
      await login('locked', 'secret');
      await login('off', 'secret');
      await login('gone', 'secret');
      await login('stale', 'secret');

      expect(recorder.events.map((e) => e.runtimeType), [
        AuthenticationFailureLockedEvent,
        AuthenticationFailureDisabledEvent,
        AuthenticationFailureExpiredEvent,
        AuthenticationFailureCredentialsExpiredEvent,
      ]);
    });

    test('a request no provider supports publishes ProviderNotFound', () async {
      final failure = await manager
          .authenticate(TestingAuthenticationToken('x', null))
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(failure, isA<ProviderNotFoundException>());
      expect(
        recorder.events.single,
        isA<AuthenticationFailureProviderNotFoundEvent>(),
      );
    });
  });
}
