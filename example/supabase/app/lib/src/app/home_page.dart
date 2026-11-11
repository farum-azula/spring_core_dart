import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart'
    show SupabaseAuth;
import 'package:supabase_example_app/src/account/login_page.dart';
import 'package:supabase_example_app/src/profile/profile_card.dart';
import 'package:supabase_example_app/src/todos/todo_list.dart';

/// The app's one screen: the login while nobody is signed in, then the
/// user's profile and todos.
///
/// `PrincipalView` follows Spring Security's current user, which
/// `SupabaseAuth` sets at each sign-in, sign-out and at startup (the
/// session of the last run): the widgets below it are built for one user
/// and thrown away when that user leaves.
@ScreenRoute('/', title: 'Todos')
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Supabase todos'),
      actions: const [
        PrincipalView(authenticated: true, child: SignOutButton()),
        SizedBox(width: 8),
      ],
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: const PrincipalView(
          authenticated: true,
          otherwise: LoginPage(),
          child: Column(
            children: [
              ProfileCard(),
              Expanded(child: TodoList()),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Signs the user out: here at once (the screen goes back to the login),
/// then at the project, which revokes the session.
class SignOutButton extends SpringStatelessWidget<(SupabaseAuth,)> {
  const SignOutButton({super.key});

  @override
  Widget build(BuildContext context) {
    final (auth,) = beans;
    return IconButton(
      onPressed: auth.logout,
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout),
    );
  }
}
