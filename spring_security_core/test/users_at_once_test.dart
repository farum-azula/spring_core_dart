// An authentication outside every scope is told to the strategy's
// listener, and `withMockUsersAtOnce` shows whether one user's calls see
// another's: with code that keeps the user in the scope, and with code
// that remembers it in a field.
import 'dart:async';

import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_security_core/testing.dart';
import 'package:test/test.dart';

Authentication _token(String name) => TestingAuthenticationToken(name, null);

// Reads the user, waits, reads again: both from the current scope.
final class _Scoped {
  Future<(String, String)> whoAmI() async {
    final before = SecurityContextHolder.getContext().authentication!.name;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return (before, SecurityContextHolder.getContext().authentication!.name);
  }
}

// The mistake: the user of the call kept in a field of a singleton.
final class _Remembering {
  late String _user;

  Future<String> whoAmI() async {
    _user = SecurityContextHolder.getContext().authentication!.name;
    await Future<void>.delayed(Duration.zero);
    return _user;
  }
}

void main() {
  late SecurityContextHolderStrategy original;

  setUp(() => original = SecurityContextHolder.getContextHolderStrategy());

  tearDown(() {
    SecurityContextHolder.clearContext();
    SecurityContextHolder.setContextHolderStrategy(original);
  });

  group('an authentication outside every scope', () {
    late ZoneSecurityContextHolderStrategy strategy;
    late List<(String, StackTrace)> told;

    setUp(() {
      told = [];
      strategy = ZoneSecurityContextHolderStrategy()
        ..onProgramWideAuthentication = (authentication, where) =>
            told.add((authentication.name, where));
      SecurityContextHolder.setContextHolderStrategy(strategy);
    });

    test('set on the context is told, with where', () {
      expect(strategy.programWideAuthentication, isNull);
      SecurityContextHolder.getContext().authentication = _token('ada');
      expect(told.map((t) => t.$1), ['ada']);
      expect('${told.single.$2}', contains('users_at_once_test.dart'));
      expect(strategy.programWideAuthentication!.name, 'ada');
      expect(programWideAuthentication()!.name, 'ada');
    });

    test('set with a context is told; an empty context and a clear are '
        'not', () {
      SecurityContextHolder.setContext(SecurityContextImpl(_token('bob')));
      SecurityContextHolder.setContext(SecurityContextImpl());
      SecurityContextHolder.getContext().authentication = null;
      SecurityContextHolder.clearContext();
      expect(told.map((t) => t.$1), ['bob']);
      expect(strategy.programWideAuthentication, isNull);
    });

    test('inside a scope nothing is told, and nothing is left', () async {
      await withMockUser(() async {
        SecurityContextHolder.getContext().authentication = _token('eve');
        SecurityContextHolder.setContext(SecurityContextImpl(_token('eve')));
      });
      SecurityContextHolder.runWithContext(
        () => SecurityContextHolder.getContext().authentication = _token('x'),
      );
      expect(told, isEmpty);
      expect(programWideAuthentication(), isNull);
    });

    test('code started in a scope and run later is still in it; code run '
        'from outside is not', () async {
      late void Function() later;
      await withMockUser(() async {
        // A callback made here keeps the scope it was made in only when
        // it is bound to the zone.
        later = Zone.current.bindCallback(
          () => SecurityContextHolder.getContext().authentication = _token(
            'in',
          ),
        );
      });
      later();
      expect(told, isEmpty);
      // The same from no scope: the program's.
      SecurityContextHolder.getContext().authentication = _token('out');
      expect(told.map((t) => t.$1), ['out']);
    });

    test('the context of the program is equal to an empty one, as before', () {
      expect(SecurityContextHolder.getContext(), SecurityContextImpl());
      expect(
        SecurityContextHolder.getContext(),
        isNot(same(SecurityContextHolder.createEmptyContext())),
      );
    });

    test('nobody listening: nothing happens', () {
      strategy.onProgramWideAuthentication = null;
      SecurityContextHolder.getContext().authentication = _token('ada');
      expect(strategy.programWideAuthentication!.name, 'ada');
    });
  });

  group('withMockUsersAtOnce', () {
    const users = ['ada', 'bob', 'eve'];

    test('every call of every user, in rounds', () async {
      final found = await withMockUsersAtOnce(users, (user) => user, rounds: 4);
      expect(found.keys, users);
      for (final user in users) {
        expect(found[user], List.filled(4, user));
      }
    });

    test(
      'code that reads the user from the scope gives each their own',
      () async {
        final scoped = _Scoped();
        final found = await withMockUsersAtOnce(users, (_) => scoped.whoAmI());
        for (final MapEntry(key: user, value: results) in found.entries) {
          expect(results, everyElement((user, user)), reason: user);
        }
        expect(programWideAuthentication(), isNull);
      },
    );

    test('code that remembers the user in a field is found out', () async {
      final remembering = _Remembering();
      final found = await withMockUsersAtOnce(
        users,
        (_) => remembering.whoAmI(),
      );
      final mixed = [
        for (final MapEntry(key: user, value: results) in found.entries)
          ...results.where((result) => result != user),
      ];
      expect(mixed, isNotEmpty);
    });

    test(
      'the roles, and a failing call fails the whole once all ended',
      () async {
        final ended = <String>[];
        await expectLater(
          withMockUsersAtOnce(
            users,
            (user) async {
              expect(
                SecurityContextHolder.getContext().authentication!.authorities
                    .map((a) => a.authority),
                ['ROLE_ADMIN'],
              );
              await Future<void>.delayed(const Duration(milliseconds: 5));
              ended.add(user);
              if (user == 'bob') {
                throw StateError('bob fails');
              }
              return user;
            },
            rounds: 2,
            roles: ['ADMIN'],
          ),
          throwsStateError,
        );
        expect(ended, hasLength(6));
      },
    );

    test('a name twice is refused', () {
      expect(
        withMockUsersAtOnce(['ada', 'ada'], (user) => user),
        throwsArgumentError,
      );
    });
  });
}
