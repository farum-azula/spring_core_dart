import 'package:flutter/material.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/account/sso_properties.dart';
import 'package:neon_books_app/src/app/messages.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The Login screen: the starter's `LoginForm`, whose name and password
/// go to the server's form login (through `Session.login` and the
/// `AuthenticationManager`); on success the screen closes. With single
/// sign-on (the `sso` profile) it has one button instead, the starter's
/// `OAuth2LoginButton` "Sign in with Keycloak"
/// (`Session.signInWithKeycloak`): the password is typed into Keycloak's
/// page, never into the app.
class LoginPage extends SpringStatefulWidget<(Session,)> {
  const LoginPage({super.key});

  /// Opens the screen.
  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'login'),
      builder: (_) => const LoginPage(),
    ),
  );

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends SpringState<LoginPage, (Session,)> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final (session,) = beans;
    final space = SpringTheme.of(context).space('m');
    return Scaffold(
      appBar: AppBar(title: Text(context.message('login.title'))),
      body: ListView(
        padding: EdgeInsets.all(space),
        children: session.usesKeycloak
            ? _keycloak(context, session, space)
            : _form(context, session, space),
      ),
    );
  }

  List<Widget> _keycloak(BuildContext context, Session session, double space) {
    final navigator = Navigator.of(context);
    return [
      Text(context.message('login.keycloakHint')),
      SizedBox(height: space),
      OAuth2LoginButton(
        context.bean<SsoProperties>().registrationId,
        key: const Key('login-keycloak'),
        label: context.message('login.keycloak'),
        icon: const Icon(Icons.key),
        // Through the Session: it waits for the restore of the start and
        // tells the app's beans (basket, chat) who logged in.
        login: (_) async {
          await session.signInWithKeycloak();
          return null;
        },
        onSuccess: (_) {
          setState(() => _error = null);
          if (session.isLoggedIn) {
            navigator.pop();
          }
        },
        // A closed Keycloak page is no error: the button handles it.
        onError: (failure) =>
            setState(() => _error = errorMessage(context, failure)),
      ),
      if (_error case final error?) ...[
        SizedBox(height: space),
        Text(
          error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ];
  }

  List<Widget> _form(BuildContext context, Session session, double space) {
    final navigator = Navigator.of(context);
    return [
      Text(context.message('login.hint')),
      SizedBox(height: space),
      LoginForm(
        usernameLabel: context.message('login.username'),
        passwordLabel: context.message('login.password'),
        submitLabel: context.message('login.submit'),
        // Through the Session: it sets the user and tells the app's
        // beans; the form shows the progress and the errors.
        authenticate: (username, password) async {
          await session.login(username, password);
          return null;
        },
        errorMessage: (context, failure) => failure is BadCredentialsException
            ? context.message('login.failed')
            : errorMessage(context, failure),
        onSuccess: (_) => navigator.pop(),
      ),
    ];
  }
}
