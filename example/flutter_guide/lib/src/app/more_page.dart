import 'package:flutter/material.dart';
import 'package:neon_books_app/spring_gen/main.spring.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The other screens. The Admin entry is there for admins only; that is
/// convenience, the server checks the role of every admin request.
@ScreenRoute('/more', title: '#{section.more}')
class MorePage extends SpringStatelessWidget<(Session,)> {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final (session,) = beans;
    // Each entry opens its screen's route over everything.
    ListTile entry(IconData icon, String key, String path) => ListTile(
      leading: Icon(icon),
      title: Text(context.message(key)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.route.push<void>(path),
    );
    return ListView(
      children: [
        entry(Icons.support_agent, 'support.title', SupportPageRoute.pattern),
        if (session.isAdmin)
          entry(
            Icons.admin_panel_settings,
            'admin.title',
            AdminPageRoute.pattern,
          ),
        entry(
          Icons.palette_outlined,
          'settings.title',
          SettingsPageRoute.pattern,
        ),
        entry(Icons.article_outlined, 'logs.title', LogsPageRoute.pattern),
        entry(Icons.info_outline, 'about.title', AboutPageRoute.pattern),
      ],
    );
  }
}
