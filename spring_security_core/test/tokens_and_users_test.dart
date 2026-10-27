// The value types: tokens (equality that includes the credentials and the
// authorities, names, erasing, toString that hides secrets), authorities,
// users and their builder, the in-memory user store, the account checks,
// and the results of authorization managers.
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

/// `a == b` for operands the analyzer would call unrelated.
bool isEqual(Object a, Object b) => a == b;

List<GrantedAuthority> authorities(List<String> names) =>
    AuthorityUtils.createAuthorityList(names);

void main() {
  group('authorities', () {
    test('equal by name, with a hash that agrees', () {
      final a = SimpleGrantedAuthority('ROLE_A');
      final same = SimpleGrantedAuthority('ROLE_A');
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(SimpleGrantedAuthority('ROLE_B')));
      expect(isEqual(a, 'ROLE_A'), isFalse);
      expect({a, same, SimpleGrantedAuthority('ROLE_B')}, hasLength(2));
      expect('$a', 'ROLE_A');
    });

    test('names of a list: those with one, once', () {
      expect(
        AuthorityUtils.authorityListToSet([
          ...authorities(['A', 'B', 'A']),
          const _NamelessAuthority(),
        ]),
        {'A', 'B'},
      );
      expect(AuthorityUtils.noAuthorities, isEmpty);
    });
  });

  group('token equality', () {
    UsernamePasswordAuthenticationToken token({
      Object? principal = 'ada',
      Object? credentials = 'secret',
      List<String> granted = const ['ROLE_A', 'ROLE_B'],
      Object? details,
    }) => UsernamePasswordAuthenticationToken.authenticated(
      principal,
      credentials,
      authorities(granted),
    )..details = details;

    test('the same content is equal, with the same hash', () {
      expect(token(), token());
      expect(token().hashCode, token().hashCode);
      expect({token(), token()}, hasLength(1));
    });

    test('any difference makes them different', () {
      expect(token(), isNot(token(principal: 'bob')));
      expect(token(), isNot(token(credentials: 'other')));
      expect(token(), isNot(token(details: 'from here')));
      expect(token(), isNot(token(granted: ['ROLE_A'])));
      expect(token(), isNot(token(granted: ['ROLE_A', 'ROLE_C'])));
      expect(token(), isNot(token(granted: ['ROLE_B', 'ROLE_A'])));
      expect(token(), isNot(token(granted: ['ROLE_A', 'ROLE_B', 'ROLE_C'])));
    });

    test('an authenticated token is not its own request', () {
      final request = UsernamePasswordAuthenticationToken.unauthenticated(
        'ada',
        'secret',
      );
      final authenticated = UsernamePasswordAuthenticationToken.authenticated(
        'ada',
        'secret',
        const [],
      );
      expect(request, isNot(authenticated));
    });

    test('another kind of token with the same content is another token', () {
      final testing = TestingAuthenticationToken('ada', 'secret', ['ROLE_A']);
      final password = UsernamePasswordAuthenticationToken.authenticated(
        'ada',
        'secret',
        authorities(['ROLE_A']),
      );
      expect(testing, isNot(password));
      expect(isEqual(password, 'ada'), isFalse);
    });
  });

  group('tokens', () {
    test('a password request can be marked not authenticated, never '
        'authenticated', () {
      final request = UsernamePasswordAuthenticationToken.unauthenticated(
        'ada',
        'x',
      )..isAuthenticated = false;
      expect(request.isAuthenticated, isFalse);
      expect(() => request.isAuthenticated = true, throwsArgumentError);

      final authenticated = UsernamePasswordAuthenticationToken.authenticated(
        'ada',
        'x',
        const [],
      )..isAuthenticated = false;
      expect(authenticated.isAuthenticated, isFalse);
    });

    test('authorities are copied and cannot be changed', () {
      final given = authorities(['A']);
      final token = TestingAuthenticationToken('ada', null);
      final copy = UsernamePasswordAuthenticationToken.authenticated(
        'ada',
        null,
        given,
      );
      given.clear();
      expect(copy.authorities, hasLength(1));
      expect(
        () => copy.authorities.add(SimpleGrantedAuthority('B')),
        throwsUnsupportedError,
      );
      expect(token.authorities, isEmpty);
    });

    test('the name comes from the principal', () {
      String nameOf(Object? principal) =>
          UsernamePasswordAuthenticationToken.unauthenticated(
            principal,
            null,
          ).name;
      expect(nameOf('ada'), 'ada');
      expect(nameOf(User.withUsername('bob').password('x').build()), 'bob');
      expect(nameOf(null), '');
      expect(nameOf(42), '42');
      expect(nameOf(TestingAuthenticationToken('carol', null)), 'carol');
      expect(nameOf(_NamedPrincipal('dave')), 'dave');
    });

    test('an anonymous token needs a key and authorities, holds no '
        'credentials, and counts as authenticated', () {
      expect(
        () => AnonymousAuthenticationToken('key', 'anonymousUser', const []),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('needs authorities'),
          ),
        ),
      );
      expect(
        () => AnonymousAuthenticationToken(
          '',
          'anonymousUser',
          authorities(['A']),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('non-empty key'),
          ),
        ),
      );
      final anonymous = AnonymousAuthenticationToken(
        'key',
        'anonymousUser',
        authorities(['ROLE_ANONYMOUS']),
      );
      expect(anonymous.credentials, '');
      expect(anonymous.isAuthenticated, isTrue);
      expect(anonymous.name, 'anonymousUser');
      expect(anonymous.keyHash, 'key'.hashCode);
    });

    test('erasing credentials reaches the details too', () {
      final details = _SecretDetails();
      final token =
          UsernamePasswordAuthenticationToken.authenticated(
              'ada',
              'secret',
              const [],
            )
            ..details = details
            ..eraseCredentials();

      expect(details.erased, isTrue);
      expect(token.credentials, isNull);
    });

    test('toString never shows credentials or the password of the user', () {
      final user = User.withUsername('ada').password('{noop}hunter2').build();
      final token = UsernamePasswordAuthenticationToken.authenticated(
        user,
        'hunter2',
        authorities(['ROLE_A']),
      )..details = 'from 10.0.0.1';

      final text = '$token';

      expect(text, isNot(contains('hunter2')));
      expect(text, contains('Principal=ada'));
      expect(text, contains('Credentials=[PROTECTED]'));
      expect(text, contains('Authenticated=true'));
      expect(text, contains('Details=from 10.0.0.1'));
      expect(text, contains('ROLE_A'));
      expect(text, startsWith('UsernamePasswordAuthenticationToken'));
      final anonymous = AnonymousAuthenticationToken(
        'k',
        'anonymousUser',
        authorities(['A']),
      );
      expect('$anonymous', startsWith('AnonymousAuthenticationToken'));
    });
  });

  group('SecurityContextImpl', () {
    test('equal when it holds the same authentication', () {
      final ada = TestingAuthenticationToken('ada', null);
      expect(
        SecurityContextImpl(ada),
        SecurityContextImpl(TestingAuthenticationToken('ada', null)),
      );
      expect(
        SecurityContextImpl(ada).hashCode,
        SecurityContextImpl(ada).hashCode,
      );
      expect(SecurityContextImpl(ada), isNot(SecurityContextImpl()));
      expect(SecurityContextImpl(), SecurityContextImpl());
      expect(isEqual(SecurityContextImpl(), 'x'), isFalse);
    });

    test('toString says whether anyone is logged in, without secrets', () {
      expect('${SecurityContextImpl()}', contains('Null authentication'));
      final context = SecurityContextImpl(
        TestingAuthenticationToken('ada', 'hunter2'),
      );
      final text = '$context';
      expect(text, contains('Authentication='));
      expect(text, contains('ada'));
      expect(text, isNot(contains('hunter2')));
    });
  });

  group('User', () {
    test("equal by name only, as Spring's", () {
      final a = User.withUsername('ada').password('x').roles(['A']).build();
      final b = User.withUsername('ada').password('y').roles(['B']).build();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(User.withUsername('bob').password('x').build()));
      expect(isEqual(a, 'ada'), isFalse);
    });

    test('the plain constructor gives an enabled, unrestricted account', () {
      final user = User('ada', 'x', authorities(['A']));
      expect(user.username, 'ada');
      expect(user.password, 'x');
      expect(user.isEnabled, isTrue);
      expect(user.isAccountNonExpired, isTrue);
      expect(user.isAccountNonLocked, isTrue);
      expect(user.isCredentialsNonExpired, isTrue);
      expect(() => User('', 'x', const []), throwsArgumentError);
    });

    test('authorities are sorted and without duplicates', () {
      final user = User('ada', 'x', authorities(['B', 'A', 'B', 'C']));
      expect(AuthorityUtils.authorityListToSet(user.authorities).toList(), [
        'A',
        'B',
        'C',
      ]);
      expect(user.authorities.map((a) => a.authority), ['A', 'B', 'C']);
      expect(
        () => user.authorities.add(SimpleGrantedAuthority('D')),
        throwsUnsupportedError,
      );
    });

    test('toString hides the password and shows the flags', () {
      final user = User.withUsername('ada')
          .password('{noop}hunter2')
          .accountLocked(true)
          .build();
      final text = '$user';
      expect(text, isNot(contains('hunter2')));
      expect(text, contains('Username=ada'));
      expect(text, contains('Password=[PROTECTED]'));
      expect(text, contains('AccountNonLocked=false'));
      expect(text, contains('Enabled=true'));
    });

    test('erasing the credentials forgets the password only', () {
      final user = User.withUsername('ada').password('x').build()
        ..eraseCredentials();
      expect(user.password, isNull);
      expect(user.username, 'ada');
    });
  });

  group('UserBuilder', () {
    test('passwordEncoder encodes the password given, whatever the order', () {
      String encode(String raw) => 'enc($raw)';
      final before = User.withUsername('ada')
          .passwordEncoder(encode)
          .password('secret')
          .build();
      final after = User.withUsername('ada')
          .password('secret')
          .passwordEncoder(encode)
          .build();
      expect(before.password, 'enc(secret)');
      expect(after.password, 'enc(secret)');
    });

    test('without an encoder the password is stored as given; without a '
        'password the encoder is not asked', () {
      expect(
        User.withUsername('ada').password('{noop}x').build().password,
        '{noop}x',
      );
      final none = User.withUsername('ada')
          .passwordEncoder((_) => fail('must not be called'))
          .build();
      expect(none.password, isNull);
    });

    test('authorityNames and authorities replace the roles', () {
      final byName = User.withUsername('ada')
          .roles(['A'])
          .authorityNames(['x', 'y'])
          .build();
      expect(AuthorityUtils.authorityListToSet(byName.authorities), {'x', 'y'});
      final byObject = User.withUsername('ada')
          .authorityNames(['x'])
          .authorities([SimpleGrantedAuthority('z')])
          .build();
      expect(AuthorityUtils.authorityListToSet(byObject.authorities), {'z'});
    });

    test('every flag can be turned on', () {
      final user = User.withUsername('ada')
          .disabled(true)
          .accountExpired(true)
          .accountLocked(true)
          .credentialsExpired(true)
          .build();
      expect(user.isEnabled, isFalse);
      expect(user.isAccountNonExpired, isFalse);
      expect(user.isAccountNonLocked, isFalse);
      expect(user.isCredentialsNonExpired, isFalse);
    });

    test('withUserDetails copies everything', () {
      final original = User.withUsername('ada')
          .password('x')
          .roles(['A'])
          .disabled(true)
          .accountLocked(true)
          .build();
      final copy = User.withUserDetails(original).build();
      expect(copy.username, 'ada');
      expect(copy.password, 'x');
      expect(copy.authorities, original.authorities);
      expect(copy.isEnabled, isFalse);
      expect(copy.isAccountNonLocked, isFalse);
      expect(copy.isAccountNonExpired, isTrue);
      expect(copy.isCredentialsNonExpired, isTrue);
    });

    test('a role with the prefix is refused, naming it', () {
      expect(
        () => User.withUsername('ada').roles(['ROLE_A']),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('ROLE_A cannot start with ROLE_'),
          ),
        ),
      );
    });

    test('an empty username is refused when built', () {
      expect(() => User.withUsername('').build(), throwsArgumentError);
    });
  });

  group('InMemoryUserDetailsManager', () {
    late InMemoryUserDetailsManager manager;

    setUp(() {
      manager = InMemoryUserDetailsManager([
        User.withUsername('ada').password('{noop}old').roles(['USER']).build(),
      ]);
    });

    test('updating a user that does not exist is an error, not a create', () {
      expect(
        () =>
            manager.updateUser(User.withUsername('bob').password('x').build()),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('bob does not exist'),
          ),
        ),
      );
      expect(manager.userExists('bob'), isFalse);
    });

    test('updating replaces the user, found without regard to case', () {
      manager.updateUser(
        User.withUsername('ADA').password('{noop}new').roles(['ADMIN']).build(),
      );
      final loaded = manager.loadUserByUsername('ada');
      expect(loaded.password, '{noop}new');
      expect(AuthorityUtils.authorityListToSet(loaded.authorities), {
        'ROLE_ADMIN',
      });
    });

    test('creating twice is refused, also with another case', () {
      expect(
        () =>
            manager.createUser(User.withUsername('ADA').password('x').build()),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('already exists'),
          ),
        ),
      );
    });

    test('deleting an unknown user changes nothing', () {
      manager.deleteUser('nobody');
      expect(manager.userExists('ada'), isTrue);
    });

    test('updatePassword stores the hash and returns a copy', () {
      final updated = manager.updatePassword(
        manager.loadUserByUsername('ada'),
        '{noop}upgraded',
      );
      expect(updated.password, '{noop}upgraded');
      (updated as User).eraseCredentials();
      expect(manager.loadUserByUsername('ada').password, '{noop}upgraded');
    });

    test('a stored user is a copy: changing the original changes nothing', () {
      final original = User.withUsername('bob').password('x').build();
      manager.createUser(original);
      original.eraseCredentials();
      expect(manager.loadUserByUsername('bob').password, 'x');
    });
  });

  group('account checks', () {
    const status = AccountStatusUserDetailsChecker();

    User user({
      bool locked = false,
      bool disabled = false,
      bool expired = false,
      bool credentialsExpired = false,
    }) =>
        User.withUsername('ada')
            .password('x')
            .accountLocked(locked)
            .disabled(disabled)
            .accountExpired(expired)
            .credentialsExpired(credentialsExpired)
            .build();

    test('a normal account passes', () {
      expect(() => status.check(user()), returnsNormally);
      expect(
        () => const CredentialsExpiryChecker().check(user()),
        returnsNormally,
      );
    });

    test('locked, disabled and expired accounts are refused with their own '
        'exception', () {
      expect(
        () => status.check(user(locked: true)),
        throwsA(isA<LockedException>()),
      );
      expect(
        () => status.check(user(disabled: true)),
        throwsA(isA<DisabledException>()),
      );
      expect(
        () => status.check(user(expired: true)),
        throwsA(isA<AccountExpiredException>()),
      );
    });

    test('lock comes before disabled, which comes before expired', () {
      expect(
        () => status.check(user(locked: true, disabled: true, expired: true)),
        throwsA(isA<LockedException>()),
      );
      expect(
        () => status.check(user(disabled: true, expired: true)),
        throwsA(isA<DisabledException>()),
      );
    });

    test('the status check leaves expired credentials to the check after '
        'the password', () {
      final stale = user(credentialsExpired: true);
      expect(() => status.check(stale), returnsNormally);
      expect(
        () => const CredentialsExpiryChecker().check(stale),
        throwsA(isA<CredentialsExpiredException>()),
      );
    });
  });

  group('authorization results', () {
    test('decisions print their outcome', () {
      expect(
        '${AuthorizationDecision.granted}',
        'AuthorizationDecision [granted=true]',
      );
      expect(
        '${AuthorizationDecision.denied}',
        'AuthorizationDecision [granted=false]',
      );
      expect(
        '${const AuthorityAuthorizationDecision(false, ['A', 'B'])}',
        'AuthorityAuthorizationDecision [granted=false, authorities=[A, B]]',
      );
    });

    test('managers print what they decide on', () {
      expect(
        '${AuthorityAuthorizationManager<void>.hasAuthority('read')}',
        'AuthorityAuthorizationManager[authorities=[read]]',
      );
      expect(
        '${AuthorityAuthorizationManager<void>.hasRole('ADMIN')}',
        'AuthorityAuthorizationManager[authorities=[ROLE_ADMIN]]',
      );
      expect(
        '${const AuthenticatedAuthorizationManager<void>.authenticated()}',
        'AuthenticatedAuthorizationManager[authenticated]',
      );
      expect(
        '${const AuthenticatedAuthorizationManager<void>.fullyAuthenticated()}',
        'AuthenticatedAuthorizationManager[fully]',
      );
      expect(
        '${const AuthenticatedAuthorizationManager<void>.anonymous()}',
        'AuthenticatedAuthorizationManager[anonymous]',
      );
      expect(
        '${const SingleResultAuthorizationManager<void>.denyAll()}',
        'SingleResultAuthorizationManager[granted=false]',
      );
    });

    test('hasAuthority grants the one authority, not roles by that name', () {
      final manager = AuthorityAuthorizationManager<void>.hasAuthority('read');
      Authentication holding(String name) =>
          TestingAuthenticationToken('ada', null, [name]);
      expect(manager.authorize(() => holding('read'), null).isGranted, isTrue);
      expect(
        manager.authorize(() => holding('ROLE_read'), null).isGranted,
        isFalse,
      );
      final decision = manager.authorize(
        () => holding('x'),
        null,
      ) as AuthorityAuthorizationDecision;
      expect(decision.authorities, ['read']);
    });

    test('a custom result in SingleResultAuthorizationManager', () {
      const manager = SingleResultAuthorizationManager<void>(
        AuthorityAuthorizationDecision(true, ['x']),
      );
      expect(manager.authorize(() => null, null).isGranted, isTrue);
    });

    test('fullyAuthenticated: authenticated and not remembered', () {
      const manager =
          AuthenticatedAuthorizationManager<void>.fullyAuthenticated();
      expect(
        manager
            .authorize(() => TestingAuthenticationToken('ada', null), null)
            .isGranted,
        isTrue,
      );
      expect(manager.authorize(() => null, null).isGranted, isFalse);
      expect(
        manager
            .authorize(
              () =>
                  AnonymousAuthenticationToken('k', 'anon', authorities(['A'])),
              null,
            )
            .isGranted,
        isFalse,
      );
    });

    test('the default trust resolver never sees a remembered login', () {
      const resolver = AuthenticationTrustResolverImpl();
      final login = TestingAuthenticationToken('ada', null);
      expect(resolver.isRememberMe(login), isFalse);
      expect(resolver.isRememberMe(null), isFalse);
      expect(resolver.isFullyAuthenticated(login), isTrue);
      expect(resolver.isFullyAuthenticated(null), isFalse);
      expect(resolver.isAuthenticated(null), isFalse);
      expect(resolver.isAnonymous(null), isFalse);
    });

    test('the role hierarchy keeps unnamed authorities and adds implied '
        'ones once', () {
      final hierarchy = RoleHierarchyImpl.fromHierarchy('''
        ROLE_A > ROLE_B
        ROLE_C > ROLE_B
      ''');
      final reachable = hierarchy.getReachableGrantedAuthorities([
        SimpleGrantedAuthority('ROLE_A'),
        SimpleGrantedAuthority('ROLE_C'),
        const _NamelessAuthority(),
      ]);
      expect(reachable.where((a) => a.authority == 'ROLE_B'), hasLength(1));
      expect(reachable.where((a) => a.authority == null), hasLength(1));
      expect(AuthorityUtils.authorityListToSet(reachable), {
        'ROLE_A',
        'ROLE_B',
        'ROLE_C',
      });
      expect(
        AuthorityUtils.authorityListToSet(
          const NullRoleHierarchy().getReachableGrantedAuthorities(
            authorities(['ROLE_A']),
          ),
        ),
        {'ROLE_A'},
      );
    });
  });
}

final class _NamelessAuthority implements GrantedAuthority {
  const _NamelessAuthority();

  @override
  String? get authority => null;
}

final class _NamedPrincipal implements Principal {
  _NamedPrincipal(this.name);

  @override
  final String name;
}

final class _SecretDetails implements CredentialsContainer {
  bool erased = false;

  @override
  void eraseCredentials() => erased = true;
}
