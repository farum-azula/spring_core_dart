import 'package:flutter/material.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/account/login_page.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The app bar's account button: "Log in", or the user's name with a menu
/// to log out. A plain `StatelessWidget` reaching the bean through the
/// generated getter `context.session` (`@BuildContextAccess`); the
/// `ListenableBuilder` rebuilds it when the session changes.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    return ListenableBuilder(
      listenable: listenableOf(session),
      builder: (context, _) {
        final user = session.user;
        if (user == null) {
          return TextButton.icon(
            onPressed: () => LoginPage.open(context),
            icon: const Icon(Icons.login),
            label: Text(context.message('login.open')),
          );
        }
        return PopupMenuButton<void>(
          tooltip: context.message('account.menu'),
          itemBuilder: (context) => [
            PopupMenuItem(
              onTap: session.logout,
              child: Text(context.message('account.logout')),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  session.isAdmin ? Icons.admin_panel_settings : Icons.person,
                ),
                const SizedBox(width: 4),
                Text(user),
              ],
            ),
          ),
        );
      },
    );
  }
}
