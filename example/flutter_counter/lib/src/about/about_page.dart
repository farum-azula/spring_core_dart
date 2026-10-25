import 'package:flutter/material.dart';
import 'package:flutter_counter/main.spring.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The About page: the logo and a text, both assets injected into the
/// `AppAssets` bean.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    // `context.appAssets`: generated for the @BuildContextAccess bean.
    final assets = context.appAssets;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: Text(context.message('about.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Image(image: assets.logoImage, height: 160),
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
