// An authentication set outside every request of a server: the monitor
// logs it once per place and the health shows it; requests of several
// users at the same time each see their own user.
import 'dart:async';

import 'package:spring_boot_actuator/spring_boot_actuator.dart' show Status;
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

Authentication _token(String name) => TestingAuthenticationToken(name, null);

void _setFromHere(String name) =>
    SecurityContextHolder.getContext().authentication = _token(name);

void _setFromThere(String name) =>
    SecurityContextHolder.getContext().authentication = _token(name);

void main() {
  final logs = captureLogs();

  tearDown(SecurityContextHolder.clearContext);

  List<String> warnings() => [
    for (final record in logs.atLevel(SpringLogLevel.warning))
      if (record.message.contains('outside a request')) record.message,
  ];

  test('requests of several users at the same time each see their own '
      'user, and none is left afterwards', () async {
    await withApp(null, (mvc, context) async {
      const users = ['ada', 'bob', 'eve', 'kay'];
      final found = await withMockUsersAtOnce(users, (name) async {
        final result = await mvc.perform(
          request(HttpMethod.get, '/api/me', processors: [user(name)]),
        );
        return (result.response.json! as Map<String, Object?>)['name'];
      });
      for (final MapEntry(key: name, value: answers) in found.entries) {
        expect(answers, everyElement(name), reason: name);
      }
      expect(programWideAuthentication(), isNull);
      expect(warnings(), isEmpty);
      final health = context.getBean<SecurityContextHealthIndicator>().health();
      expect(health.status, Status.up);
      expect(health.details, {
        'programWideAuthentication': false,
        'setOutsideRequests': 0,
      });
    }, properties: ['management.health.securityContext.enabled=true']);
  });

  test('an authentication set outside a request is logged once per place, '
      'without the user, and the health shows it', () async {
    await withApp(null, (mvc, context) async {
      final monitor = context.getBean<ProgramWideAuthenticationMonitor>();
      // What a scheduled method or a timer of the application would do.
      _setFromHere('ada');
      _setFromHere('bob');
      _setFromThere('eve');
      expect(monitor.count, 3);
      expect(monitor.current!.name, 'eve');
      expect(warnings(), hasLength(2));
      expect(warnings().first, contains('TestingAuthenticationToken'));
      expect(warnings().first, contains('_setFromHere'));
      expect(warnings().last, contains('_setFromThere'));
      expect(warnings().join(), isNot(contains('ada')));
      expect(warnings().first, contains('runWithContext'));

      final health = context.getBean<SecurityContextHealthIndicator>().health();
      expect(health.status, Status.up);
      expect(health.details, {
        'programWideAuthentication': true,
        'setOutsideRequests': 3,
      });

      // A request is not touched by it: it has a scope of its own.
      final result = await mvc.perform(
        request(HttpMethod.get, '/api/me', processors: [user('kay')]),
      );
      expect((result.response.json! as Map<String, Object?>)['name'], 'kay');

      SecurityContextHolder.clearContext();
      expect(monitor.current, isNull);
    }, properties: ['management.health.securityContext.enabled=true']);
  });

  test('inside a scope of its own nothing is logged', () async {
    await withApp(null, (mvc, context) async {
      await SecurityContextHolder.runWithContext(() async {
        _setFromHere('ada');
        await Future<void>.delayed(Duration.zero);
      });
      expect(context.getBean<ProgramWideAuthenticationMonitor>().count, 0);
      expect(warnings(), isEmpty);
    });
  });

  test('the application closed: nobody listens any more', () async {
    await withApp(null, (mvc, context) async {});
    final strategy =
        SecurityContextHolder.getContextHolderStrategy()
            as ZoneSecurityContextHolderStrategy;
    expect(strategy.onProgramWideAuthentication, isNull);
    _setFromHere('ada');
    expect(warnings(), isEmpty);
  });

  test('without management.health.securityContext.enabled=true: no '
      'indicator, the log stays', () async {
    await withApp(
      null,
      (mvc, context) async {
        expect(
          context.containsBean('securityContextHealthIndicator'),
          isFalse,
        );
        _setFromHere('ada');
        expect(warnings(), hasLength(1));
      },
    );
  });
}
