import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';
import 'package:theme_showcase_material/src/widgets/section.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

/// Flutter's own widgets, looking as `components.*` says. No widget below has
/// a style of its own: delete the YAML and they are plain Material.
class ComponentsPage extends StatefulWidget {
  const ComponentsPage({super.key});

  @override
  State<ComponentsPage> createState() => _ComponentsPageState();
}

class _ComponentsPageState extends State<ComponentsPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    'Buttons',
    'Selection',
    'Inputs',
    'Feedback',
    'Navigation',
    'Lists and cards',
    'Cupertino',
  ];

  late final _controller = TabController(length: _tabs.length, vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final space = context.theme.spacing;
    return PageFrame(
      title: context.messages.nav.components,
      intro:
          'Every Flutter component has a theme, and each is a key under '
          'components. Colors are written as `\$colors.role`, a color or a color object; the ones '
          'marked below take a value per state (hovered, pressed, focused, '
          'selected, disabled, error). Hover and press the widgets.',
      children: [
        TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final tab in _tabs) Tab(text: tab)],
        ),
        SizedBox(height: space.l),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => switch (_controller.index) {
            0 => const _Buttons(),
            1 => const _Selection(),
            2 => const _Inputs(),
            3 => const _Feedback(),
            4 => const _Navigation(),
            5 => const _Lists(),
            _ => const _CupertinoSection(),
          },
        ),
      ],
    );
  }
}

Widget _row(BuildContext context, List<Widget> children) => Wrap(
  spacing: context.theme.spacing.m,
  runSpacing: context.theme.spacing.m,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: children,
);

class _Buttons extends StatefulWidget {
  const _Buttons();

  @override
  State<_Buttons> createState() => _ButtonsState();
}

class _ButtonsState extends State<_Buttons> {
  bool _favorite = false;
  Set<String> _view = {'list'};

  @override
  Widget build(BuildContext context) {
    void noop() {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Section(
          title: 'Four buttons, one shared style',
          note:
              '`button` holds what they share; each adds its own. The '
              'filled button\'s fill changes with the state.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'button: { shape: full, min-height: 44 }\n'
                'filled-button:\n'
                '  background-color:\n'
                '    default: \$colors.primary\n'
                '    hovered: { color: \$colors.primary, alpha: 85% }\n'
                '    pressed: \$colors.tertiary\n'
                '    disabled: { color: \$colors.on-surface, alpha: 12% }\n'
                '  side:\n'
                '    default: none\n'
                '    focused: { color: \$colors.secondary, width: 2 }\n'
                '  text-style: { style: label-large, weight: bold }',
                label: 'application.yml: components',
              ),
              SizedBox(height: context.theme.spacing.m),
              _row(context, [
                FilledButton(onPressed: noop, child: const Text('Filled')),
                const FilledButton(onPressed: null, child: Text('Disabled')),
                FilledButton.icon(
                  onPressed: noop,
                  icon: const Icon(Icons.add),
                  label: const Text('With icon'),
                ),
                ElevatedButton(onPressed: noop, child: const Text('Elevated')),
                OutlinedButton(onPressed: noop, child: const Text('Outlined')),
                TextButton(onPressed: noop, child: const Text('Text')),
              ]),
            ],
          ),
        ),
        Section(
          title: 'Elevation, borders and overlays per state',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'elevated-button:\n'
                '  elevation: { default: level1, hovered: level3, pressed: level0 }\n'
                'outlined-button:\n'
                '  side:\n'
                '    default: { color: \$colors.outline, width: 1 }\n'
                '    hovered: { color: \$colors.primary, width: 2 }\n'
                '    disabled: { color: { color: \$colors.on-surface, alpha: 12% }, width: 1 }\n'
                'text-button:\n'
                '  foreground-color: { default: \$colors.primary, hovered: \$colors.tertiary, disabled: { color: \$colors.on-surface, alpha: 38% } }\n'
                '  overlay-color: { hovered: { color: \$colors.primary, alpha: 8% }, pressed: { color: \$colors.primary, alpha: 16% } }',
                label: 'application.yml: components',
              ),
              SizedBox(height: context.theme.spacing.m),
              _row(context, [
                const OutlinedButton(onPressed: null, child: Text('Disabled')),
                TextButton.icon(
                  onPressed: noop,
                  icon: const Icon(Icons.favorite_border),
                  label: const Text('Hover me'),
                ),
              ]),
            ],
          ),
        ),
        Section(
          title: 'Icon, segmented, floating',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'icon-button:\n'
                '  foreground-color: { default: \$colors.on-surface-variant, hovered: \$colors.primary, selected: \$colors.primary }\n'
                'segmented-button:\n'
                '  background-color: { selected: \$colors.secondary-container }\n'
                '  foreground-color: { selected: \$colors.on-secondary-container }\n'
                'floating-action-button: { shape: large, elevation: level2 }',
                label: 'application.yml: components',
              ),
              SizedBox(height: context.theme.spacing.m),
              _row(context, [
                IconButton(
                  isSelected: _favorite,
                  icon: const Icon(Icons.favorite_border),
                  selectedIcon: const Icon(Icons.favorite),
                  tooltip: 'Favorite (selected state)',
                  onPressed: () => setState(() => _favorite = !_favorite),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'list', label: Text('List')),
                    ButtonSegment(value: 'grid', label: Text('Grid')),
                    ButtonSegment(value: 'map', label: Text('Map')),
                  ],
                  selected: _view,
                  onSelectionChanged: (value) => setState(() => _view = value),
                ),
                FloatingActionButton(
                  onPressed: noop,
                  heroTag: 'components-fab',
                  child: const Icon(Icons.add),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Selection extends StatefulWidget {
  const _Selection();

  @override
  State<_Selection> createState() => _SelectionState();
}

class _SelectionState extends State<_Selection> {
  bool _check = true;
  String _radio = 'b';
  bool _switch = true;
  double _slider = 40;
  final _chosen = <String>{'Neon'};
  String _choice = 'Light';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Section(
          title: 'Checkbox, radio, switch',
          note:
              'The checkbox is wrong (error state) when it is off and '
              'required.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'checkbox:\n'
                '  fill-color: { default: \$colors.outline, selected: \$colors.primary, error: \$colors.error, disabled: { color: \$colors.on-surface, alpha: 12% } }\n'
                '  shape: { type: rounded, radius: extra-small }\n'
                'radio:\n'
                '  fill-color: { default: \$colors.outline, selected: \$colors.primary, disabled: { color: \$colors.on-surface, alpha: 38% } }\n'
                'switch:\n'
                '  thumb-color: { default: \$colors.outline, selected: \$colors.on-primary }\n'
                '  track-color: { default: \$colors.surface-container-highest, selected: \$colors.primary }',
                label: 'application.yml: components',
              ),
              SizedBox(height: context.theme.spacing.m),
              _row(context, [
                Checkbox(
                  value: _check,
                  onChanged: (v) => setState(() => _check = v ?? false),
                ),
                Checkbox(
                  value: false,
                  isError: true,
                  onChanged: (_) {},
                ),
                const Checkbox(value: true, onChanged: null),
                RadioGroup<String>(
                  groupValue: _radio,
                  onChanged: (v) => setState(() => _radio = v ?? 'a'),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Radio<String>(value: 'a'),
                      Radio<String>(value: 'b'),
                    ],
                  ),
                ),
                Switch(
                  value: _switch,
                  onChanged: (v) => setState(() => _switch = v),
                ),
                const Switch(value: false, onChanged: null),
              ]),
            ],
          ),
        ),
        Section(
          title: 'Slider',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'track-height: 6\n'
                'active-track-color: \$colors.primary\n'
                'inactive-track-color: { color: \$colors.primary, alpha: 24% }\n'
                'thumb-color: \$colors.tertiary\n'
                'value-indicator-color: \$colors.tertiary\n'
                'show-value-indicator: on-drag',
                label: 'application.yml: components.slider',
              ),
              SizedBox(height: context.theme.spacing.s),
              Slider(
                value: _slider,
                max: 100,
                divisions: 10,
                label: _slider.round().toString(),
                onChanged: (v) => setState(() => _slider = v),
              ),
            ],
          ),
        ),
        Section(
          title: 'Chips',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'shape: stadium\n'
                'side: \$colors.outline-variant\n'
                'selected-color: \$colors.secondary-container\n'
                'label-style: label-large',
                label: 'application.yml: components.chip',
              ),
              SizedBox(height: context.theme.spacing.m),
              _row(context, [
                for (final label in ['Neon', 'Ocean', 'Paper'])
                  FilterChip(
                    label: Text(label),
                    selected: _chosen.contains(label),
                    onSelected: (on) => setState(
                      () => on ? _chosen.add(label) : _chosen.remove(label),
                    ),
                  ),
                for (final label in ['Light', 'Dark'])
                  ChoiceChip(
                    label: Text(label),
                    selected: _choice == label,
                    onSelected: (_) => setState(() => _choice = label),
                  ),
                InputChip(label: const Text('Input'), onDeleted: () {}),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Inputs extends StatelessWidget {
  const _Inputs();

  @override
  Widget build(BuildContext context) => Section(
    title: 'Text fields',
    note:
        'An outline, a fill, and a thicker border while focused or wrong. '
        'Click into a field.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const YamlBox(
          'input:\n'
          '  style: outline\n'
          '  shape: small\n'
          '  filled: true\n'
          '  fill-color: \$colors.surface-container-low\n'
          '  focused-border: { type: outline, radius: small, side: { color: \$colors.primary, width: 2 } }\n'
          '  error-border: { type: outline, radius: small, side: { color: \$colors.error, width: 2 } }',
          label: 'application.yml: components',
        ),
        SizedBox(height: context.theme.spacing.m),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'Your name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              SizedBox(height: context.theme.spacing.m),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'E-mail',
                  errorText: 'This is not an address',
                ),
              ),
              SizedBox(height: context.theme.spacing.m),
              const TextField(
                enabled: false,
                decoration: InputDecoration(labelText: 'Disabled'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Feedback extends StatelessWidget {
  const _Feedback();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Section(
          title: 'Dialog, snack bar, bottom sheet',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'dialog: { shape: extra-large, elevation: level3, title-text-style: headline-small }\n'
                'snack-bar:\n'
                '  behavior: floating\n'
                '  shape: medium\n'
                '  show-close-icon: true\n'
                '  background-color: \$colors.inverse-surface\n'
                '  content-text-style: { style: body-medium, color: \$colors.on-inverse-surface }\n'
                'bottom-sheet: { shape: extra-large, constraints: { max-width: 640 } }',
                label: 'application.yml: components',
              ),
              SizedBox(height: context.theme.spacing.m),
              _row(context, [
                FilledButton.tonal(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('A dialog'),
                      content: const Text(
                        'Shape, elevation and title come from YAML.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open a dialog'),
                ),
                FilledButton.tonal(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('A floating snack bar')),
                  ),
                  child: const Text('Show a snack bar'),
                ),
                FilledButton.tonal(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (context) => const SizedBox(
                      height: 200,
                      child: Center(child: Text('A bottom sheet')),
                    ),
                  ),
                  child: const Text('Open a bottom sheet'),
                ),
              ]),
            ],
          ),
        ),
        Section(
          title: 'Tooltip, badge, progress, banner',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'tooltip:\n'
                '  decoration: { color: \$colors.inverse-surface, radius: small }\n'
                '  text-style: { style: label-medium, color: \$colors.on-inverse-surface }\n'
                '  padding: 12, 8\n'
                '  wait-duration: 300ms\n'
                'badge: { background-color: \$colors.tertiary, text-color: \$colors.on-tertiary }\n'
                'progress-indicator: { color: \$colors.primary, linear-track-color: { color: \$colors.primary, alpha: 16% }, stroke-cap: round, linear-min-height: 6 }\n'
                'banner: { background-color: \$colors.secondary-container, content-text-style: { style: body-medium, color: \$colors.on-secondary-container } }',
                label: 'application.yml: components',
              ),
              SizedBox(height: context.theme.spacing.m),
              _row(context, [
                const Tooltip(
                  message: 'A tooltip from YAML',
                  child: Icon(Icons.info_outline),
                ),
                const Badge(label: Text('3'), child: Icon(Icons.mail_outline)),
                const SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(value: 0.6),
                ),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(value: 0.6),
                ),
              ]),
              SizedBox(height: context.theme.spacing.m),
              MaterialBanner(
                content: const Text('A banner, from components.banner'),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Dismiss')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Navigation extends StatefulWidget {
  const _Navigation();

  @override
  State<_Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<_Navigation> {
  int _bar = 0;
  int _rail = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Section(
          title: 'Navigation bar and rail',
          note:
              'The window you are using has a rail (wide) or a drawer '
              '(narrow). These are small copies.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'navigation-bar: { height: 72, label-behavior: only-show-selected, indicator-color: \$colors.secondary-container }\n'
                'navigation-rail: { label-type: all, use-indicator: true, indicator-color: \$colors.secondary-container }',
                label: 'application.yml: components',
              ),
              SizedBox(height: context.theme.spacing.m),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: NavigationBar(
                  selectedIndex: _bar,
                  onDestinationSelected: (i) => setState(() => _bar = i),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.search),
                      label: 'Search',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      label: 'Me',
                    ),
                  ],
                ),
              ),
              SizedBox(height: context.theme.spacing.m),
              SizedBox(
                height: 230,
                child: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _rail,
                      onDestinationSelected: (i) => setState(() => _rail = i),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          label: Text('Home'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.search),
                          label: Text('Search'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.person_outline),
                          label: Text('Me'),
                        ),
                      ],
                    ),
                    VerticalDivider(width: 1, color: scheme.outlineVariant),
                  ],
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Tab bar and popup menu',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'tab-bar:\n'
                '  indicator-size: tab\n'
                r'  indicator-color: $colors.tertiary'
                '\n'
                '  label-color: \$colors.primary\n'
                '  unselected-label-color: \$colors.on-surface-variant\n'
                '  divider-height: 0\n'
                'popup-menu: { shape: medium, elevation: level3 }',
                label: 'application.yml: components',
              ),
              SizedBox(height: context.theme.spacing.m),
              _row(context, [
                const SizedBox(
                  width: 360,
                  child: DefaultTabController(
                    length: 3,
                    child: TabBar(
                      tabs: [
                        Tab(text: 'One'),
                        Tab(text: 'Two'),
                        Tab(text: 'Three'),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<int>(
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 1, child: Text('First')),
                    PopupMenuItem(value: 2, child: Text('Second')),
                  ],
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Lists extends StatefulWidget {
  const _Lists();

  @override
  State<_Lists> createState() => _ListsState();
}

class _ListsState extends State<_Lists> {
  int _selected = 1;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Section(
          title: 'Cards, list tiles, dividers, expansion',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'card: { shape: large, color: \$colors.surface-container-low, elevation: level0 }\n'
                'list-tile: { shape: medium, selected-tile-color: { color: \$colors.primary, alpha: 12% }, selected-color: \$colors.primary }\n'
                'divider: { color: \$colors.outline-variant, thickness: 1 }\n'
                'expansion-tile: { shape: medium, collapsed-shape: medium }',
                label: 'application.yml: components',
              ),
              SizedBox(height: context.theme.spacing.m),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        ListTile(
                          leading: Icon(
                            [Icons.mail, Icons.star, Icons.flag][i],
                          ),
                          title: Text('Item ${i + 1}'),
                          subtitle: Text(
                            i == _selected ? 'Selected' : 'Tap to select',
                          ),
                          selected: i == _selected,
                          onTap: () => setState(() => _selected = i),
                        ),
                        if (i < 2) const Divider(height: 1),
                      ],
                      const ExpansionTile(
                        title: Text('Expand me'),
                        children: [ListTile(title: Text('Inside'))],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CupertinoSection extends StatefulWidget {
  const _CupertinoSection();

  @override
  State<_CupertinoSection> createState() => _CupertinoSectionState();
}

class _CupertinoSectionState extends State<_CupertinoSection> {
  bool _on = true;
  double _value = 0.4;

  @override
  Widget build(BuildContext context) {
    // The iOS look has a root of its own, `cupertino`; SpringThemes makes a
    // CupertinoThemeData for every theme.
    final themes = context.bean<SpringThemes>();
    final name = SpringTheme.of(context).name;
    final cupertino = themes.cupertino(name);
    return Section(
      title: 'Cupertino',
      note:
          'CupertinoThemeData from `cupertino.*`. An app of type cupertino '
          '(spring.flutter.app.type) uses it everywhere; here it wraps this '
          'box only.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const YamlBox(
            'primary-color: \$colors.primary\n'
            'scaffold-background-color: \$colors.surface\n'
            'bar-background-color: \$colors.surface-container\n'
            'text-theme:\n'
            '  nav-title-text-style: { style: title-large, weight: 600 }',
            label: 'application.yml: cupertino',
          ),
          SizedBox(height: context.theme.spacing.m),
          ClipRRect(
            borderRadius: BorderRadius.circular(context.theme.spacing.m),
            child: CupertinoTheme(
              data: cupertino,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cupertino.scaffoldBackgroundColor,
                ),
                child: Column(
                  children: [
                    CupertinoNavigationBar(
                      automaticallyImplyLeading: false,
                      middle: const Text('Cupertino'),
                      trailing: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {},
                        child: const Text('Done'),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(context.theme.spacing.m),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _row(context, [
                            CupertinoButton.filled(
                              onPressed: () {},
                              child: const Text('Filled'),
                            ),
                            CupertinoButton(
                              onPressed: () {},
                              child: const Text('Plain'),
                            ),
                            CupertinoSwitch(
                              value: _on,
                              onChanged: (v) => setState(() => _on = v),
                            ),
                            const CupertinoActivityIndicator(),
                          ]),
                          SizedBox(height: context.theme.spacing.m),
                          const CupertinoTextField(
                            placeholder: 'A Cupertino field',
                          ),
                          SizedBox(height: context.theme.spacing.m),
                          CupertinoSlider(
                            value: _value,
                            onChanged: (v) => setState(() => _value = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
