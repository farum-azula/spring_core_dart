import 'package:flutter/material.dart';
import 'package:neon_books_app/src/about/about_page.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/admin/admin_page.dart';
import 'package:neon_books_app/src/logs/logs_page.dart';
import 'package:neon_books_app/src/settings/settings_page.dart';
import 'package:neon_books_app/src/support/support_page.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The other screens. The Admin entry is there for admins only; that is
/// convenience, the server checks the role of every admin request.
class MorePage extends SpringStatelessWidget<(Session,)> {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final (session,) = beans;
    ListTile entry(IconData icon, String key, Widget Function() page) =>
        ListTile(
          leading: Icon(icon),
          title: Text(context.message(key)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: RouteSettings(name: key),
              builder: (_) => page(),
            ),
          ),
        );
    return ListView(
      children: [
        entry(Icons.support_agent, 'support.title', SupportPage.new),
        if (session.isAdmin)
          entry(Icons.admin_panel_settings, 'admin.title', AdminPage.new),
        entry(Icons.palette_outlined, 'settings.title', SettingsPage.new),
        entry(Icons.article_outlined, 'logs.title', LogsPage.new),
        entry(Icons.info_outline, 'about.title', AboutPage.new),
      ],
    );
  }
}
