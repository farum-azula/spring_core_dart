import 'package:flutter/material.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/app/messages.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_security_core/spring_security_core.dart'
    show BadCredentialsException, AuthenticationException;

/// The Login screen: name and password go to the server's form login
/// (through `Session.login` and the `AuthenticationManager`); on success
/// the screen closes.
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

  @override
  Widget build(BuildContext context) {
    final space = SpringTheme.of(context).space('m');
    return Scaffold(
      appBar: AppBar(title: Text(context.message('login.title'))),
      body: ListView(
        padding: EdgeInsets.all(space),
        children: [
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
        ],
      ),
    );
  }
}
