// Authentication events (chapter 4): the security packages publish them,
// the application decides what to do (here: log, and count failures).
import 'package:neon_books_server/src/app.spring.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

@Component()
@Log(topic: 'neon.security')
class LoginAudit {
  /// Failed logins per user name since the start.
  final failures = <String, int>{};

  /// A login: the form, or Keycloak's (`sso`). A native app's bearer
  /// token is checked on every request it sends, with an event each time:
  /// not a login, so only at debug level.
  @EventListener()
  void onSuccess(AuthenticationSuccessEvent event) {
    final authentication = event.authentication;
    if (authentication is JwtAuthenticationToken) {
      log.debug('bearer token of ${authentication.name}');
    } else {
      log.info('${authentication.name} logged in');
    }
  }

  @EventListener()
  void onBadCredentials(AuthenticationFailureBadCredentialsEvent event) {
    final name = event.authentication.name;
    final count = failures[name] = (failures[name] ?? 0) + 1;
    log.warning('failed login for "$name" ($count so far)');
  }

  @EventListener()
  void onLogout(LogoutSuccessEvent event) =>
      log.info('${event.authentication.name} logged out');
}
