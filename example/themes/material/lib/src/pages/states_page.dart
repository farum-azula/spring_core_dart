import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';
import 'package:theme_showcase_material/src/widgets/section.dart';
import 'package:theme_showcase_material/src/widgets/styled_widgets.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

/// `styles.*` and ThemeStates: a look per state for the app's own widgets.
@ScreenRoute('/states', title: '#{nav.states}')
class StatesPage extends StatefulWidget {
  const StatesPage({super.key});

  @override
  State<StatesPage> createState() => _StatesPageState();
}

class _StatesPageState extends State<StatesPage> {
  final _tags = <String>{'Selected'};
  int _card = 0;
  int _presses = 0;

  static const _states = <(String, WidgetState?)>[
    ('default', null),
    ('hovered', WidgetState.hovered),
    ('focused', WidgetState.focused),
    ('pressed', WidgetState.pressed),
    ('selected', WidgetState.selected),
    ('error', WidgetState.error),
    ('disabled', WidgetState.disabled),
  ];

  @override
  Widget build(BuildContext context) {
    final space = context.theme.spacing;
    final styles = context.theme.styles;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return PageFrame(
      title: context.messages.nav.states,
      intro:
          'Flutter\'s widgets get their states from components.*. The '
          'widgets of your own app get theirs from styles.<name>: one value '
          'or a value per state, and ThemeStates tracks hover, focus, press '
          'and the keyboard for you. Everything below is live: hover, tab '
          'to, press and click it.',
      children: [
        Section(
          title: 'A style',
          note:
              'The first state that is true wins: disabled, \$colors.error, '
              'pressed, dragged, hovered, focused, selected, scrolled-under, '
              'default. `transition` blends the change.',
          child: const YamlBox(
            'pill:\n'
            '  padding: [12, 6]\n'
            '  radius: 999\n'
            r'  border: { default: $colors.outline, hovered: $colors.primary, selected: $colors.primary, disabled: $colors.outline-variant, error: $colors.error }'
            '\n'
            r'  fill: { default: transparent, hovered: { color: $colors.primary, alpha: 8% }, selected: { color: $colors.primary, alpha: 18% }, disabled: transparent }'
            '\n'
            r'  text: { default: $colors.on-surface-variant, hovered: $colors.primary, selected: $colors.primary, disabled: $colors.outline, error: $colors.error }'
            '\n'
            '  transition: 120ms ease-out',
            label: 'application.yml: styles',
          ),
        ),
        Section(
          title: 'Every state of the chip, resolved from the YAML',
          note: 'Not animated: styles.pill.style.resolve({state}).',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              for (final (name, state) in _states)
                Column(
                  children: [
                    _Frozen(
                      styles.pill.view(
                        styles.pill.style.resolve({?state}),
                      ),
                      name,
                    ),
                    SizedBox(height: space.xs),
                    Text(name, style: text.labelSmall),
                  ],
                ),
            ],
          ),
        ),
        Section(
          title: 'Live chips',
          note:
              'selected comes from our argument, hover and press from '
              'the pointer, disabled from onPressed: null.',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              for (final label in ['Selected', 'Hover me', 'Press me'])
                PillChip(
                  label,
                  selected: _tags.contains(label),
                  onPressed: () => setState(
                    () => _tags.contains(label)
                        ? _tags.remove(label)
                        : _tags.add(label),
                  ),
                ),
              const PillChip('Disabled'),
              PillChip('Error', error: true, onPressed: () {}),
            ],
          ),
        ),
        Section(
          title: 'A button with a glow',
          note:
              'A number can be a state value too: glow is a blur radius '
              '(0, 14 when hovered, 4 when pressed). Enter and Space work '
              'when it has focus.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'action:\n'
                '  padding: [24, 14]\n'
                '  radius: 12\n'
                '  fill:\n'
                r'    default: $colors.primary'
                '\n'
                r'    hovered: { color: $colors.primary, mix: { with: white, amount: 14% } }'
                '\n'
                r'    focused: { color: $colors.primary, mix: { with: white, amount: 14% } }'
                '\n'
                r'    pressed: $colors.tertiary'
                '\n'
                r'    disabled: { color: $colors.on-surface, alpha: 12% }'
                '\n'
                '  glow: { default: 0, hovered: 14, pressed: 4, disabled: 0 }\n'
                '  transition: 160ms ease-out',
                label: 'application.yml: styles',
              ),
              SizedBox(height: space.m),
              Wrap(
                spacing: space.m,
                runSpacing: space.m,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ActionButton(
                    'Pressed $_presses times',
                    onPressed: () => setState(() => _presses++),
                  ),
                  const ActionButton('Disabled'),
                ],
              ),
            ],
          ),
        ),
        Section(
          title: 'A field frame',
          note:
              'Click into it: the frame glows. The second one is in the '
              'error state, the third is disabled.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'field:\n'
                '  padding: [16, 12]\n'
                '  radius: 12\n'
                r'  border: { default: $colors.outline, hovered: $colors.on-surface-variant, focused: $colors.primary, error: $colors.error, disabled: $colors.outline-variant }'
                '\n'
                r'  fill: { default: $colors.surface-container-low, focused: $colors.surface-container, disabled: transparent }'
                '\n'
                '  glow: { default: 0, focused: 10, error: 10 }\n'
                '  transition: 140ms ease-out',
                label: 'application.yml: styles',
              ),
              SizedBox(height: space.m),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: const Column(
                  children: [
                    BoxField(label: 'Type something'),
                    SizedBox(height: 12),
                    BoxField(
                      label: 'Wrong value',
                      error: true,
                      initialText: 'oops',
                    ),
                    SizedBox(height: 12),
                    BoxField(label: 'Disabled', enabled: false),
                  ],
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Cards',
          note: 'Tap one to select it; hovering lifts the border and glow.',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              for (var i = 0; i < 3; i++)
                SizedBox(
                  width: 200,
                  child: TileCard(
                    selected: _card == i,
                    onPressed: () => setState(() => _card = i),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.bolt, color: scheme.primary),
                        SizedBox(height: space.s),
                        Text('Card ${i + 1}', style: text.titleMedium),
                        Text(_card == i ? 'Selected' : 'Tap to select'),
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

/// A chip painted from resolved values, no states tracked.
class _Frozen extends StatelessWidget {
  const _Frozen(this.values, this.label);

  final AppStylePillValues values;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: values.padding,
    decoration: BoxDecoration(
      color: values.fill,
      borderRadius: BorderRadius.circular(values.radius),
      border: Border.all(color: values.border),
    ),
    child: Text(
      'Chip',
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: values.text),
    ),
  );
}
