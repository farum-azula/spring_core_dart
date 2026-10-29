// A Flutter app that logs its user in with Keycloak in the system's login
// window (the app login: OAuth2LoginService), keeps a PIN's settings as a
// secret, and shows what the user may
// do (for display only: the server checks access). The generator writes
// example.spring.dart (`dart run build_runner build`).
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

import 'example.spring.dart';

/// A secret of the app, kept as JSON in the Keychain / Keystore.
@Introspected()
class PinSettings {
  /// Settings with the PIN's [hash] and the failed [attempts].
  const PinSettings({required this.hash, required this.attempts});

  /// The PIN's hash, never the PIN.
  final String hash;

  /// Failed attempts since the last success.
  final int attempts;
}

/// The account: the app login and the app's own secret. The login service
/// exists when a registration is configured.
@Service()
class Account {
  /// The account on the login service and the secrets.
  Account(this._login, this._secrets);

  final OAuth2LoginService? _login;
  final SecretTemplate _secrets;

  /// Brings the user of the last run back from the stored tokens.
  Future<void> start() async => _login?.restore();

  /// Opens Keycloak's login page in the system's login window (a Safari
  /// sheet, a Chrome tab; the default browser on Windows and Linux).
  Future<void> signIn() async => _login?.login('keycloak');

  /// Revokes the tokens and forgets them.
  Future<void> signOut() async => _login?.logout();

  /// Stores the PIN's settings under `app.pin`.
  Future<void> savePin(String hash) =>
      _secrets.write('pin', PinSettings(hash: hash, attempts: 0));

  /// The PIN's settings, or `null` before the first [savePin].
  Future<PinSettings?> pin() => _secrets.read<PinSettings>('pin');
}

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    child: const MaterialApp(home: HomePage()),
  ),
);

/// The page: who is logged in, a menu for admins, sign in and out.
class HomePage extends SpringStatelessWidget<(Account,)> {
  /// Creates the page.
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final (account,) = beans;
    return Scaffold(
      appBar: AppBar(
        // Builds again on every login and logout.
        title: PrincipalBuilder(
          builder: (context, authentication) =>
              Text(authentication == null ? 'Guest' : authentication.name),
        ),
      ),
      body: const Center(
        // For display only: the server refuses non-admins anyway.
        child: PrincipalView(
          hasRole: 'ADMIN',
          otherwise: Text('Welcome'),
          child: Text('Admin tools'),
        ),
      ),
      floatingActionButton: PrincipalView(
        authenticated: false,
        otherwise: FloatingActionButton(
          onPressed: account.signOut,
          child: const Icon(Icons.logout),
        ),
        child: FloatingActionButton(
          onPressed: account.signIn,
          child: const Icon(Icons.login),
        ),
      ),
    );
  }
}
