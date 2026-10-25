import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// Every part of the theme on one page: the palette, the text styles,
/// the Material components and the app's own tokens. Nothing here sets a
/// color, font or shape; all of it comes from the properties.
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.message('gallery.title')),
        actions: const [ThemeMenu()],
      ),
      body: ListView(
        padding: EdgeInsets.all(theme.space('m')),
        children: const [
          ThemeBanner(),
          _Section('gallery.colors', Palette()),
          _Section('gallery.text', TextStyles()),
          _Section('gallery.components', Components()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.palette_outlined),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Picks the theme: `system`, the standard ones, the custom ones, and
/// one loaded from a "server" (an asset here) at run time. A
/// `SpringStatelessWidget`: rebuilt when the selection or the themes change.
class ThemeMenu extends SpringStatelessWidget<(ThemeSelection, SpringThemes)> {
  const ThemeMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final (selection, themes) = beans;
    return PopupMenuButton<String>(
      tooltip: context.message('gallery.theme'),
      icon: const Icon(Icons.brightness_6_outlined),
      onSelected: (name) => name == '_load'
          ? _loadFromServer(context, themes, selection)
          : selection.select(name),
      itemBuilder: (context) => [
        for (final name in ['system', ...themes.names])
          CheckedPopupMenuItem(
            value: name,
            checked: selection.active == name,
            child: Text(context.message('theme.$name', defaultMessage: name)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: '_load',
          child: Text(context.message('gallery.load')),
        ),
      ],
    );
  }

  // A server would send this YAML; the app adds the theme without a
  // restart. Invalid properties throw and change nothing.
  static Future<void> _loadFromServer(
    BuildContext context,
    SpringThemes themes,
    ThemeSelection selection,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = context.message('gallery.loaded', args: ['winter']);
    themes.loadYaml(
      await rootBundle.loadString('assets/remote/winter.yml', cache: false),
    );
    selection.select('winter');
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}

/// The theme's name on the brand's accent: the app's own tokens
/// (`spring.flutter.theme.tokens.brand.*`), per theme.
class ThemeBanner extends StatelessWidget {
  const ThemeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.of(context);
    final accent = theme.tokenColor('brand.accent')!;
    return Container(
      height: theme.tokenNumber('brand.banner-height'),
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

class _Section extends StatelessWidget {
  const _Section(this.title, this.child);

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: theme.space('l')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.message(title),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: theme.space('s')),
          child,
        ],
      ),
    );
  }
}

/// The main color roles with their "on" colors.
class Palette extends StatelessWidget {
  const Palette({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = [
      ('primary', scheme.primary, scheme.onPrimary),
      ('primaryContainer', scheme.primaryContainer, scheme.onPrimaryContainer),
      ('secondary', scheme.secondary, scheme.onSecondary),
      ('tertiary', scheme.tertiary, scheme.onTertiary),
      ('error', scheme.error, scheme.onError),
      ('surface', scheme.surface, scheme.onSurface),
      ('surfaceContainer', scheme.surfaceContainer, scheme.onSurface),
      ('inverseSurface', scheme.inverseSurface, scheme.onInverseSurface),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (name, color, on) in roles)
          Container(
            width: 104,
            height: 48,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(
                SpringTheme.of(context).shape('small'),
              ),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(name, style: TextStyle(color: on, fontSize: 11)),
          ),
      ],
    );
  }
}

/// A line in each text style group, and the theme's monospaced style.
class TextStyles extends StatelessWidget {
  const TextStyles({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Display small', style: text.displaySmall),
        Text('Headline medium', style: text.headlineMedium),
        Text('Title large', style: text.titleLarge),
        Text(
          'Body large: the quick brown fox jumps over the lazy dog.',
          style: text.bodyLarge,
        ),
        Text('Label large', style: text.labelLarge),
        Text(
          "typography.code: the theme's code style",
          style: SpringTheme.of(context).textStyle('code'),
        ),
      ],
    );
  }
}

/// The Material components the theme adjusts.
class Components extends StatefulWidget {
  const Components({super.key});

  @override
  State<Components> createState() => _ComponentsState();
}

class _ComponentsState extends State<Components> {
  bool _switch = true;
  bool _check = true;
  final _chips = {'Spring', 'Flutter'};

  @override
  Widget build(BuildContext context) {
    final space = SpringTheme.of(context).space('s');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: space,
          runSpacing: space,
          children: [
            FilledButton(onPressed: () {}, child: const Text('Filled')),
            ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
            OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
            TextButton(onPressed: () {}, child: const Text('Text')),
          ],
        ),
        SizedBox(height: space),
        Card(
          child: ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Spring in Action'),
            subtitle: const Text('A card in the theme\'s shape and color'),
            trailing: Switch(
              value: _switch,
              onChanged: (value) => setState(() => _switch = value),
            ),
          ),
        ),
        SizedBox(height: space),
        TextField(
          decoration: InputDecoration(
            labelText: context.message('gallery.name'),
          ),
        ),
        SizedBox(height: space),
        Wrap(
          spacing: space,
          children: [
            for (final label in ['Spring', 'Flutter', 'Dart'])
              FilterChip(
                label: Text(label),
                selected: _chips.contains(label),
                onSelected: (on) => setState(
                  () => on ? _chips.add(label) : _chips.remove(label),
                ),
              ),
          ],
        ),
        Row(
          children: [
            Checkbox(
              value: _check,
              onChanged: (value) => setState(() => _check = value!),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        Wrap(
          spacing: space,
          children: [
            OutlinedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(context.message('gallery.dialog')),
                  content: Text(context.message('gallery.dialog.text')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.message('gallery.ok')),
                    ),
                  ],
                ),
              ),
              child: Text(context.message('gallery.dialog')),
            ),
            OutlinedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.message('gallery.dialog.text'))),
              ),
              child: Text(context.message('gallery.snack')),
            ),
          ],
        ),
      ],
    );
  }
}
