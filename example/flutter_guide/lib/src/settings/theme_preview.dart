import 'package:flutter/material.dart';
import 'package:neon_books_app/spring_gen/main.spring.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The theme's name on the brand's accent: the app's own tokens
/// (`spring.flutter.theme.tokens.brand.*`), per theme, read through
/// `context.theme` (generated, typed).
class ThemeBanner extends StatelessWidget {
  const ThemeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.of(context);
    final brand = context.theme.tokens.brand;
    final accent = brand.accent;
    return Container(
      height: brand.bannerHeight,
      margin: EdgeInsets.all(context.theme.spacing.m),
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

/// A tag in the theme's `styles.tag`: padding, radius and fill per widget
/// state (hovered, selected), animated over the style's `transition`.
class ThemeTag extends StatelessWidget {
  const ThemeTag(
    this.label, {
    super.key,
    this.selected = false,
    this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ThemeStates(
      style: context.theme.styles.tag,
      selected: selected,
      onPressed: onPressed,
      builder: (context, tag) {
        final fill = tag.fill;
        return Container(
          padding: tag.padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(tag.radius),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              // The soft fill is see-through: text on the surface's color
              // unless the tag is selected (solid accent).
              color: !selected
                  ? Theme.of(context).colorScheme.onSurface
                  : ThemeData.estimateBrightnessForColor(fill) ==
                        Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ),
        );
      },
    );
  }
}

/// The tags of `tokens.brand.tag.labels`, rising into place with the
/// theme's `animations.rise`; tap one to select it.
class ThemeTags extends StatefulWidget {
  const ThemeTags({super.key});

  @override
  State<ThemeTags> createState() => _ThemeTagsState();
}

class _ThemeTagsState extends State<ThemeTags> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing.s;
    return ThemeAnimation(
      theme.animations.rise,
      builder: (context, t) => AnimatedBuilder(
        animation: t,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - t.value) * space),
          child: child,
        ),
        child: Wrap(
          spacing: space,
          runSpacing: space,
          children: [
            for (final label in theme.tokens.brand.tag.labels)
              ThemeTag(
                label,
                selected: label == _selected,
                onPressed: () => setState(() => _selected = label),
              ),
          ],
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
          const ThemeTags(),
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
