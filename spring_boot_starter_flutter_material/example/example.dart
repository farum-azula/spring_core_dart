// A MaterialApp whose whole look is configuration: the palette from one
// seed color, the shapes, the app bar and the cards, a light and a dark
// theme (lib/resources/application.yml next to this file). A customizer
// changes, in code, what no property covers. The generator writes
// example.spring.dart (`dart run build_runner build`).
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

import 'spring_gen/example.spring.dart';

/// A value of the app's own widgets on Material's theme, where widgets of
/// other packages look for theirs too (`Theme.of(context).extension`).
class Brand extends ThemeExtension<Brand> {
  /// The brand's accent.
  const Brand(this.accent);

  /// The color of what the brand marks.
  final Color accent;

  @override
  Brand copyWith({Color? accent}) => Brand(accent ?? this.accent);

  @override
  Brand lerp(Brand? other, double t) =>
      other == null ? this : Brand(Color.lerp(accent, other.accent, t)!);
}

/// Adds [Brand] to every theme, made from the theme's palette: no theme
/// property adds a `ThemeExtension` of one's own.
@Component()
class BrandTheme implements ThemeCustomizer {
  @override
  ThemeData customize(ThemeData theme, SpringThemeData spring) =>
      theme.copyWith(
        extensions: [
          ...theme.extensions.values,
          Brand(spring.colorScheme.tertiary),
        ],
      );
}

/// The only page: the theme's colors and components, and a switch between
/// the light and the dark theme.
class ThemePage extends SpringStatelessWidget<(ThemeSelection,)> {
  /// The page.
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    final (selection,) = beans;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Themes from properties'),
        actions: [
          IconButton(
            tooltip: dark ? 'Light theme' : 'Dark theme',
            icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => selection.select(dark ? 'light' : 'dark'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                Icons.palette,
                color: Theme.of(context).extension<Brand>()!.accent,
              ),
              title: const Text('One seed color'),
              subtitle: const Text(
                'Every role of the palette is made from it, '
                'in the light and in the dark theme.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (name, color) in [
                ('primary', colors.primary),
                ('secondary', colors.secondary),
                ('tertiary', colors.tertiary),
                ('surface container', colors.surfaceContainer),
              ])
                Chip(
                  avatar: CircleAvatar(backgroundColor: color),
                  label: Text(name),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () {}, child: const Text('Filled')),
        ],
      ),
    );
  }
}

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    // No MaterialApp in the code: the starter builds it from
    // spring.flutter.app.* and spring.flutter.theme.*.
    home: const ThemePage(),
  ),
);
