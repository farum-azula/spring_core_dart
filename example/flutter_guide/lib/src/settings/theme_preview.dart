import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The theme's name on the brand's accent: the app's own tokens
/// (`spring.flutter.theme.tokens.brand.*`), per theme, read through
/// `SpringTheme.of(context)`.
class ThemeBanner extends StatelessWidget {
  const ThemeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.of(context);
    final accent = theme.tokenColor('brand.accent')!;
    return Container(
      height: theme.tokenNumber('brand.banner-height'),
      margin: EdgeInsets.all(theme.space('m')),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(theme.shape('large')),
      ),
      child: Text(
        context.message('theme.${theme.name}', defaultMessage: theme.name),
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
          color: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
      ),
    );
  }
}

/// Every part of the theme in a few lines: the palette, the text styles
/// and the components the theme adjusts. Nothing here sets a color, font
/// or shape; all of it comes from the properties.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final space = theme.space('s');
    final roles = [
      ('primary', scheme.primary, scheme.onPrimary),
      ('secondary', scheme.secondary, scheme.onSecondary),
      ('tertiary', scheme.tertiary, scheme.onTertiary),
      ('surface', scheme.surface, scheme.onSurface),
      ('container', scheme.surfaceContainer, scheme.onSurface),
      ('error', scheme.error, scheme.onError),
    ];
    return Padding(
      padding: EdgeInsets.all(theme.space('m')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: space,
            runSpacing: space,
            children: [
              for (final (name, color, on) in roles)
                Container(
                  width: 104,
                  height: 40,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(theme.shape('small')),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(name, style: TextStyle(color: on, fontSize: 11)),
                ),
            ],
          ),
          SizedBox(height: space),
          Text('Display small', style: text.displaySmall),
          Text('Headline small', style: text.headlineSmall),
          Text(
            'Body large: NEON Books, open all night.',
            style: text.bodyLarge,
          ),
          Text(
            "typography.code: the theme's code style",
            style: theme.textStyle('code'),
          ),
          SizedBox(height: space),
          Wrap(
            spacing: space,
            runSpacing: space,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Filled')),
              OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
              TextButton(onPressed: () {}, child: const Text('Text')),
            ],
          ),
          SizedBox(height: space),
          const Card(
            child: ListTile(
              leading: Icon(Icons.menu_book_outlined),
              title: Text('Spring in Action'),
              subtitle: Text("A card in the theme's shape and color"),
            ),
          ),
        ],
      ),
    );
  }
}
