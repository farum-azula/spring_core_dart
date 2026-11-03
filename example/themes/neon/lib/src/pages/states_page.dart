import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';
import 'package:theme_showcase_neon/src/widgets/state_tile.dart';
import 'package:theme_showcase_neon/src/widgets/yaml_box.dart';

/// The states of ThemeStates: switch some on, and try the others by hand.
class StatesPage extends StatefulWidget {
  const StatesPage({super.key});

  @override
  State<StatesPage> createState() => _StatesPageState();
}

class _StatesPageState extends State<StatesPage> {
  final _field = TextEditingController(text: 'Try focus');
  bool _disabled = false;
  bool _error = false;
  bool _selected = true;
  int _pressed = 0;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    return PageFrame(
      kicker: 'THEMESTATES',
      title: 'States',
      intro:
          'Disabled, error and selected come from the widget\'s arguments; '
          'hover, focus (Tab) and press from the pointer and the keyboard. '
          'ThemeStates picks the values for the state by a fixed precedence '
          'and animates to them over the style\'s transition.',
      children: [
        Section(
          title: 'Switch a state on',
          child: Wrap(
            spacing: space.s,
            runSpacing: space.s,
            children: [
              NeonChip(
                label: 'disabled',
                selected: _disabled,
                onPressed: () => setState(() => _disabled = !_disabled),
              ),
              NeonChip(
                label: 'error',
                selected: _error,
                onPressed: () => setState(() => _error = !_error),
              ),
              NeonChip(
                label: 'selected',
                selected: _selected,
                onPressed: () => setState(() => _selected = !_selected),
              ),
            ],
          ),
        ),
        Section(
          title: 'Widgets in that state',
          note: _pressed == 0
              ? 'Press the button, or focus it and press Enter or Space.'
              : 'Pressed $_pressed times.',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child: NeonButton(
                  label: 'Press me',
                  onPressed: _disabled
                      ? null
                      : () => setState(() => _pressed++),
                ),
              ),
              NeonChip(
                label: 'A chip',
                selected: _selected,
                onPressed: _disabled ? null : () {},
              ),
              SizedBox(
                width: 240,
                child: NeonTextField(
                  controller: _field,
                  error: _error,
                  enabled: !_disabled,
                ),
              ),
              SizedBox(
                width: 220,
                child: StateTile(
                  selected: _selected,
                  onPressed: _disabled ? null : () {},
                  child: Text(
                    'A tile of this app\'s own style',
                    style: theme.typography.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Section(
          title: 'A value per state',
          note:
              'A property is one value, or a map of states with a default. '
              'The precedence is disabled, error, pressed, hovered, focused, '
              'selected, default.',
          child: YamlBox(
            label: 'neon_ui/lib/resources/themes/neon.yml',
            '''
neon-chip:
  padding: [12, 6]
  border:
    default: \$colors.outline
    hovered: \$colors.primary
    selected: \$colors.primary
    disabled: { color: \$colors.outline, alpha: 40% }
  fill: { default: transparent, selected: { color: \$colors.primary, alpha: 12% } }''',
          ),
        ),
        const Section(
          title: 'A style of the app\'s own',
          note:
              'The tile above is not from the library: this app declares '
              'styles.showcase-tile and reads it as '
              'context.theme.styles.showcaseTile.',
          child: YamlBox(
            label: 'lib/resources/application.yml',
            '''
showcase-tile:
  padding: [16, 14]
  border:
    default: \$colors.outline
    hovered: \$colors.secondary
    selected: \$colors.primary
  glow: { default: 0, hovered: 8, selected: 14 }
  transition: 160ms ease-out''',
          ),
        ),
      ],
    );
  }
}
