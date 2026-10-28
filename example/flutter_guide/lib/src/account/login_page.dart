import 'package:flutter/material.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/app/messages.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_security_core/spring_security_core.dart'
    show BadCredentialsException, AuthenticationException;

/// The Login screen: name and password go to the server's form login
/// (through `Session.login` and the `AuthenticationManager`); on success
/// the screen closes. With single sign-on (the `sso` profile) it has one
/// button instead, "Sign in with Keycloak" (`Session.signInWithKeycloak`):
/// the password is typed into Keycloak's page, never into the app.
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
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final (session,) = beans;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    String? error;
    try {
      await session.login(_username.text.trim(), _password.text);
    } on BadCredentialsException {
      error = mounted ? context.message('login.failed') : null;
    } on AuthenticationException catch (failure) {
      error = mounted ? errorMessage(context, failure) : null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) {
      navigator.pop();
    }
  }

  Future<void> _signInWithKeycloak() async {
    final (session,) = beans;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    String? error;
    try {
      await session.signInWithKeycloak();
    } on AuthorizationCancelledException {
      // The user closed Keycloak's page: no error, the screen stays.
    } on Exception catch (failure) {
      error = mounted ? errorMessage(context, failure) : null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
    if (session.isLoggedIn) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final (session,) = beans;
    final space = SpringTheme.of(context).space('m');
    return Scaffold(
      appBar: AppBar(title: Text(context.message('login.title'))),
      body: ListView(
        padding: EdgeInsets.all(space),
        children: session.usesKeycloak
            ? _keycloak(context, space)
            : _form(context, space),
      ),
    );
  }

  List<Widget> _keycloak(BuildContext context, double space) => [
    Text(context.message('login.keycloakHint')),
    SizedBox(height: space),
    FilledButton.icon(
      key: const Key('login-keycloak'),
      onPressed: _busy ? null : _signInWithKeycloak,
      icon: const Icon(Icons.key),
      label: Text(context.message('login.keycloak')),
    ),
    if (_error case final error?) ...[
      SizedBox(height: space),
      Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ],
  ];

  List<Widget> _form(BuildContext context, double space) => [
    Text(context.message('login.hint')),
    SizedBox(height: space),
    TextField(
      key: const Key('login-username'),
      controller: _username,
      autofillHints: const [AutofillHints.username],
      decoration: InputDecoration(
        labelText: context.message('login.username'),
      ),
    ),
    SizedBox(height: space),
    TextField(
      key: const Key('login-password'),
      controller: _password,
      obscureText: true,
      autofillHints: const [AutofillHints.password],
      decoration: InputDecoration(
        labelText: context.message('login.password'),
        errorText: _error,
      ),
      onSubmitted: (_) => _login(),
    ),
    SizedBox(height: space),
    FilledButton(
      onPressed: _busy ? null : _login,
      child: Text(context.message('login.submit')),
    ),
  ];
}
