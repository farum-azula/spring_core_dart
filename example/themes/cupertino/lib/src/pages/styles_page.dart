import 'package:flutter/cupertino.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/ios_widgets.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

/// `styles.*` and ThemeStates: a look per state for the app's own widgets,
/// built from Cupertino and basic widgets.
@ScreenRoute('/styles', title: '#{nav.styles}', branch: '/more')
class StylesPage extends StatefulWidget {
  const StylesPage({super.key});

  @override
  State<StylesPage> createState() => _StylesPageState();
}

class _StylesPageState extends State<StylesPage> {
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
    final theme = context.theme;
    final space = theme.spacing;
    final styles = theme.styles;
    final colors = theme.colors;
    final text = CupertinoTheme.of(context).textTheme;
    final small = text.textStyle.copyWith(
      fontSize: 13,
      color: colors.onSurfaceVariant,
    );
    return PageFrame(
      title: context.messages.nav.styles,
      intro:
          'The Cupertino widgets get their look from `cupertino.*`. The '
          'widgets of your own app get theirs from styles.<name>: one value '
          'or a value per state, and ThemeStates tracks hover, focus, press '
          'and the keyboard for you. iOS fades what is pressed, so these '
          'styles have an `opacity`. Everything below is live: hover, tab '
          'to, press and click it.',
      children: [
        Section(
          title: 'A style',
          note:
              'The first state that is true wins: disabled, error, '
              'pressed, dragged, hovered, focused, selected, scrolled-under, '
              'default. `transition` blends the change.',
          child: const YamlBox(
            'ios-chip:\n'
            '  padding: [14, 7]\n'
            '  radius: 999\n'
            r'  border: { default: $colors.outline, hovered: $colors.primary, selected: $colors.primary, disabled: $colors.outline-variant, error: $colors.error }'
            '\n'
            r'  fill: { default: $colors.surface-container-lowest, hovered: { color: $colors.primary, alpha: 8% }, selected: { color: $colors.primary, alpha: 16% }, disabled: transparent }'
            '\n'
            r'  text: { default: $colors.on-surface-variant, hovered: $colors.primary, selected: $colors.primary, disabled: $colors.outline, error: $colors.error }'
            '\n'
            '  opacity: { default: 1, pressed: 0.55 }\n'
            '  transition: 120ms ease-out',
            label: 'application.yml: styles',
          ),
        ),
        Section(
          title: 'Every state of the chip, resolved from the YAML',
          note: 'Not animated: styles.iosChip.style.resolve({state}).',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              for (final (name, state) in _states)
                Column(
                  children: [
                    _Frozen(
                      styles.iosChip.view(
                        styles.iosChip.style.resolve({?state}),
                      ),
                    ),
                    SizedBox(height: space.xs),
                    Text(name, style: small.copyWith(fontSize: 11)),
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
                IosChip(
                  label,
                  selected: _tags.contains(label),
                  onPressed: () => setState(
                    () => _tags.contains(label)
                        ? _tags.remove(label)
                        : _tags.add(label),
                  ),
                ),
              const IosChip('Disabled'),
              IosChip('Error', error: true, onPressed: () {}),
            ],
          ),
        ),
        Section(
          title: 'A button that fades',
          note:
              'A number can be a state value too: opacity is 1, 0.9 when '
              'hovered and 0.55 when pressed. Enter and Space work when it '
              'has focus. CupertinoButton does the same with no YAML '
              '(see the Controls page); this one is yours to restyle.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'ios-button:\n'
                '  padding: [20, 12]\n'
                r'  radius: $shape.large'
                '\n'
                '  fill:\n'
                r'    default: $colors.primary'
                '\n'
                r'    hovered: { color: $colors.primary, mix: { with: white, amount: 14% } }'
                '\n'
                r'    disabled: { color: $colors.on-surface, alpha: 12% }'
                '\n'
                '  opacity: { default: 1, hovered: 0.9, pressed: 0.55, disabled: 0.6 }\n'
                '  transition: 120ms ease-out',
                label: 'application.yml: styles',
              ),
              SizedBox(height: space.m),
              Wrap(
                spacing: space.m,
                runSpacing: space.m,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IosButton(
                    'Pressed $_presses times',
                    onPressed: () => setState(() => _presses++),
                  ),
                  const IosButton('Disabled'),
                ],
              ),
            ],
          ),
        ),
        Section(
          title: 'A field frame',
          note:
              'Click into it: the frame gets a border. The second one is '
              'in the error state, the third is disabled. The text field '
              'inside is a CupertinoTextField with no decoration.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'ios-field:\n'
                '  padding: [14, 12]\n'
                r'  radius: $shape.medium'
                '\n'
                r'  border: { default: transparent, hovered: $colors.outline, focused: $colors.primary, error: $colors.error, disabled: transparent }'
                '\n'
                r'  fill: { default: $colors.surface-container-high, focused: $colors.surface-container-lowest, disabled: { color: $colors.surface-container-high, alpha: 50% } }'
                '\n'
                '  width: { default: 0, hovered: 1, focused: 2, error: 2 }',
                label: 'application.yml: styles',
              ),
              SizedBox(height: space.m),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: const Column(
                  children: [
                    IosField(placeholder: 'Type something'),
                    SizedBox(height: 12),
                    IosField(
                      placeholder: 'Wrong value',
                      error: true,
                      initialText: 'oops',
                    ),
                    SizedBox(height: 12),
                    IosField(placeholder: 'Disabled', enabled: false),
                  ],
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Cards',
          note: 'Tap one to select it; hovering darkens the border.',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              for (var i = 0; i < 3; i++)
                SizedBox(
                  width: 180,
                  child: IosCard(
                    selected: _card == i,
                    onPressed: () => setState(() => _card = i),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          CupertinoIcons.bolt_fill,
                          color: colors.primary,
                        ),
                        SizedBox(height: space.s),
                        Text(
                          'Card ${i + 1}',
                          style: text.navTitleTextStyle,
                        ),
                        Text(
                          _card == i ? 'Selected' : 'Tap to select',
                          style: small,
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

/// A chip painted from resolved values, no states tracked.
class _Frozen extends StatelessWidget {
  const _Frozen(this.values);

  final AppStyleIosChipValues values;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: values.opacity,
    child: Container(
      padding: values.padding,
      decoration: BoxDecoration(
        color: values.fill,
        borderRadius: BorderRadius.circular(values.radius),
        border: Border.all(color: values.border),
      ),
      child: Text(
        'Chip',
        style: context.theme.typography.labelLarge.copyWith(
          fontSize: 15,
          color: values.text,
        ),
      ),
    ),
  );
}
