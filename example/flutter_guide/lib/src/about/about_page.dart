import 'package:flutter/material.dart';
import 'package:neon_books_app/src/about/app_assets.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The About screen: the logo and a text, both assets injected into the
/// `AppAssets` bean; the text in the app's language (`about_ja.txt`).
class AboutPage extends SpringStatelessWidget<(AppAssets,)> {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final (assets,) = beans;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.message('about.title'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Image(image: assets.logoImage, height: 120),
          const SizedBox(height: 24),
          // Assets are read asynchronously.
          FutureBuilder(
            future: assets.aboutText(Localizations.localeOf(context)),
            builder: (context, text) => text.hasData
                ? Text(text.requireData, style: theme.textTheme.bodyLarge)
                : const Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(height: 24),
          Text(
            context.message(
              'about.source',
              args: [assets.logo.description, assets.about.description],
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
