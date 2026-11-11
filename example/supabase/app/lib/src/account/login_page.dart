import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart'
    show
        SupabaseAuth,
        SupabaseUnavailableException,
        SupabaseWeakPasswordException;

/// Sign-in and sign-up with an email and a password: the starter's
/// `LoginForm` (the fields, the progress, the errors) on `SupabaseAuth`.
///
/// Nothing is done with the answer here: `SupabaseAuth` makes the user
/// Spring Security's current one, keeps the session (in the Keychain or
/// Keystore, in memory on the web) and refreshes its token; the home
/// screen follows the current user and replaces this page.
class LoginPage extends SpringStatefulWidget<(SupabaseAuth,)> {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends SpringState<LoginPage, (SupabaseAuth,)> {
  bool _signUp = false;
  String? _notice;

  Future<Authentication?> _authenticate(String email, String password) async {
    final (auth,) = beans;
    setState(() => _notice = null);
    if (!_signUp) {
      return auth.signInWithPassword(email: email, password: password);
    }
    final user = await auth.signUp(email: email, password: password);
    // A project that confirms addresses signs nobody in yet.
    if (user == null && mounted) {
      setState(() {
        _notice = 'Open the link we sent to $email, then sign in.';
        _signUp = false;
      });
    }
    return user;
  }

  static String _message(BuildContext context, Object failure) =>
      switch (failure) {
        SupabaseWeakPasswordException() =>
          'Choose a longer password (at least 6 characters).',
        SupabaseUnavailableException() =>
          'The project does not answer. Is it running?',
        BadCredentialsException() => 'Wrong email or password.',
        AuthenticationException(:final message) => message,
        _ => 'That did not work. Try again.',
      };

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        _signUp ? 'Create an account' : 'Sign in',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      LoginForm(
        // The form of the other mode starts empty.
        key: ValueKey(_signUp),
        usernameLabel: 'Email',
        usernameKeyboardType: TextInputType.emailAddress,
        submitLabel: _signUp ? 'Create account' : 'Sign in',
        authenticate: _authenticate,
        errorMessage: _message,
      ),
      if (_notice case final notice?) ...[
        const SizedBox(height: 16),
        Text(notice, key: const Key('login-notice')),
      ],
      const SizedBox(height: 8),
      TextButton(
        key: const Key('login-mode'),
        onPressed: () => setState(() {
          _signUp = !_signUp;
          _notice = null;
        }),
        child: Text(
          _signUp ? 'I have an account' : 'Create an account instead',
        ),
      ),
    ],
  );
}
