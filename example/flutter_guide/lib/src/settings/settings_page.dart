import 'package:flutter/material.dart';
import 'package:neon_books_app/src/about/app_assets.dart';
import 'package:neon_books_app/src/app/language.dart';
import 'package:neon_books_app/src/settings/theme_preview.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The beans of [SettingsPage].
typedef SettingsPageBeans = (
  ThemeSelection,
  SpringThemes,
  LanguageSelection,
  AppAssets,
);

/// The Settings screen: the theme (every theme of the properties, and one
/// loaded at run time) and the language. Both are beans
/// (`ThemeSelection` of the starter, `LanguageSelection` of the app);
/// picking one changes the whole app at once.
class SettingsPage extends SpringStatelessWidget<SettingsPageBeans> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final (
      selection,
      themes,
      language,
      assets,
    ) = beans;
    final space = SpringTheme.of(context).space('m');
    Widget heading(String key) => Padding(
      padding: EdgeInsets.fromLTRB(space, space, space, 0),
      child: Text(
        context.message(key),
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
    ListTile choice(
      String label, {
      required bool on,
      required VoidCallback tap,
    }) => ListTile(
      title: Text(label),
      trailing: on ? const Icon(Icons.check) : null,
      selected: on,
      onTap: tap,
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.message('settings.title'))),
      body: ListView(
        children: [
          const ThemeBanner(),
          heading('settings.theme'),
          for (final name in ['system', ...themes.names])
            choice(
              context.message('theme.$name', defaultMessage: name),
              on: selection.active == name,
              tap: () => selection.select(name),
            ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: Text(context.message('settings.loadTheme')),
            onTap: () => _loadTheme(context, themes, selection, assets),
          ),
          heading('settings.language'),
          for (final (code, key) in [
            (null, 'language.system'),
            ('en', 'language.en'),
            ('ja', 'language.ja'),
          ])
            choice(
              context.message(key),
              on: language.languageCode == code,
              tap: () => language.select(code),
            ),
          heading('settings.preview'),
          const ThemePreview(),
        ],
      ),
    );
  }

  // A theme as the server could send it: YAML read at run time, checked
  // (an invalid one throws and changes nothing), then shown.
  static Future<void> _loadTheme(
    BuildContext context,
    SpringThemes themes,
    ThemeSelection selection,
    AppAssets assets,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = context.message('settings.themeLoaded', args: ['winter']);
    themes.loadYaml(await assets.winterTheme.readAsString());
    selection.select('winter');
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}
