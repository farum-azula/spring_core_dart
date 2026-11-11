import 'package:spring_boot_actuator/spring_boot_actuator.dart'
    show Health, HealthIndicator;
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.context.ProgramWideAuthentication');

/// Watches the security context outside every request of a server: an
/// authentication set there is the program's, and stays.
///
/// A request runs in a scope of its own (`FilterChainProxy`), so its user
/// ends with it. Code outside a request (a `@Scheduled` method, a timer, a
/// listener of a stream opened at startup, a callback run later) has no
/// scope unless it opens one: an authentication it sets goes to the one
/// context of the whole program, and everything else outside a request
/// then acts as that user. That is how one user's identity outlives the
/// work it was for.
///
/// The monitor logs a WARN on `spring.security.context` each time it
/// happens from a new place in the code (the place is in the message, the
/// user is not), and [SecurityContextHealthIndicator], when it is
/// switched on, shows whether there is such an authentication now.
/// Nothing is refused: code that means it (a system user for all the
/// background work) keeps working; switch the logger off for it.
///
/// ```dart
/// // Outside a request: as a user for this work only.
/// await SecurityContextHolder.runWithContext(
///   () => reports.sendFor(user),
///   SecurityContextImpl(authentication),
/// );
/// ```
///
/// Differs from Spring: Spring has neither; it keeps the context in a
/// `ThreadLocal`, where the same mistake leaves a user on a pooled thread.
final class ProgramWideAuthenticationMonitor implements DisposableBean {
  /// Starts watching the strategy of `SecurityContextHolder`, when it is
  /// the default one ([ZoneSecurityContextHolderStrategy]).
  ProgramWideAuthenticationMonitor() {
    final strategy = SecurityContextHolder.getContextHolderStrategy();
    if (strategy is ZoneSecurityContextHolderStrategy) {
      _strategy = strategy;
      _before = strategy.onProgramWideAuthentication;
      strategy.onProgramWideAuthentication = _report;
    }
  }

  /// The most places remembered: one more is logged every time.
  static const maxPlaces = 256;

  ZoneSecurityContextHolderStrategy? _strategy;
  void Function(Authentication authentication, StackTrace where)? _before;
  final _places = <String>{};
  var _count = 0;

  /// How many times an authentication was set outside every request since
  /// the start.
  int get count => _count;

  /// The authentication all the code outside a request acts as now, or
  /// `null`: nobody, as it should be on a server.
  Authentication? get current => _strategy?.programWideAuthentication;

  void _report(Authentication authentication, StackTrace where) {
    _count++;
    _before?.call(authentication, where);
    final place = _place(where);
    if (_places.length >= maxPlaces || _places.add(place)) {
      _log.warning(
        'An authentication (${authentication.runtimeType}) was set outside '
        'a request, at $place. It is the one of the whole program now: all '
        'the code that runs outside a request (scheduled work, listeners, '
        'timers) acts as that user until it is cleared. To act as a user '
        'for one piece of work, run it in '
        'SecurityContextHolder.runWithContext. Logged once per place.',
      );
    }
  }

  // The first frame that is not the security context's own.
  static String _place(StackTrace where) {
    for (final line in where.toString().split('\n')) {
      if (line.trim().isEmpty ||
          line.contains('package:spring_security_core/') ||
          line.contains('program_wide_authentication.dart')) {
        continue;
      }
      return line.replaceFirst(RegExp(r'^#\d+\s+'), '').trim();
    }
    return 'an unknown place';
  }

  @override
  void destroy() {
    final strategy = _strategy;
    if (strategy != null && strategy.onProgramWideAuthentication == _report) {
      strategy.onProgramWideAuthentication = _before;
    }
    _strategy = null;
  }
}

/// The health of the security context outside requests, `securityContext`
/// in `/actuator/health`: whether an authentication is set for the whole
/// program now, and how many times one was set since the start.
///
/// The status is always `UP`: an application may mean it (see
/// [ProgramWideAuthenticationMonitor]), so the details inform and an alert
/// on `programWideAuthentication` is the application's to set up.
/// It is there only with `management.health.securityContext.enabled=true`,
/// so that the health of an application is what Spring Boot's is unless
/// it asks for more.
///
/// Differs from Spring: Spring Boot has no such indicator.
class SecurityContextHealthIndicator extends HealthIndicator {
  /// The indicator of what [monitor] sees.
  SecurityContextHealthIndicator(this.monitor);

  /// What watches the context.
  final ProgramWideAuthenticationMonitor monitor;

  @override
  Health health() => Health.up()
      .withDetail('programWideAuthentication', monitor.current != null)
      .withDetail('setOutsideRequests', monitor.count)
      .build();
}
