import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';
import 'package:theme_showcase_neon/src/widgets/yaml_box.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// Every widget of neon_ui, with its looks per state.
@ScreenRoute('/components', title: '#{nav.components}')
class ComponentsPage extends StatefulWidget {
  const ComponentsPage({super.key});

  @override
  State<ComponentsPage> createState() => _ComponentsPageState();
}

class _ComponentsPageState extends State<ComponentsPage> {
  final _name = TextEditingController(text: 'Ada');
  final _email = TextEditingController(text: 'not an address');
  final _locked = TextEditingController(text: 'read only');
  final _chips = <String>{'Books'};
  double _logsHeight = 120;
  int _taps = 0;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _locked.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    return PageFrame(
      kicker: 'NEON_UI',
      title: 'Components',
      intro:
          'Thirteen widgets, one file each. Hover, press and focus them '
          '(Tab, then Enter): there is no state in their Dart code, every '
          'look is a line of styles.* in the theme.',
      children: [
        Section(
          title: 'Buttons',
          note: _taps == 0 ? 'Press one.' : 'Pressed $_taps times.',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: NeonButton(
                  label: 'Save',
                  onPressed: () => setState(() => _taps++),
                ),
              ),
              SizedBox(
                width: 150,
                child: NeonButton(
                  label: 'Outline',
                  filled: false,
                  onPressed: () => setState(() => _taps++),
                ),
              ),
              const SizedBox(
                width: 150,
                child: NeonButton(label: 'Disabled', onPressed: null),
              ),
              const SizedBox(
                width: 150,
                child: NeonButton(
                  label: 'Disabled',
                  filled: false,
                  onPressed: null,
                ),
              ),
            ],
          ),
        ),
        const Section(
          title: 'The style behind a button',
          child: YamlBox(
            label: 'neon_ui/lib/resources/themes/neon.yml',
            '''
neon-button:
  height: 42
  fill:
    default: \$colors.primary
    hovered: { color: \$colors.primary, mix: { with: white, amount: 14% } }
    disabled: { color: \$colors.primary, alpha: 40% }
  transition: 120ms ease-out''',
          ),
        ),
        Section(
          title: 'Chips and badges',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: space.s,
                runSpacing: space.s,
                children: [
                  for (final name in const ['Books', 'Authors', 'Orders'])
                    NeonChip(
                      label: name,
                      selected: _chips.contains(name),
                      onPressed: () => setState(
                        () => _chips.contains(name)
                            ? _chips.remove(name)
                            : _chips.add(name),
                      ),
                    ),
                  const NeonChip(
                    label: 'Disabled',
                    selected: false,
                    onPressed: null,
                  ),
                ],
              ),
              SizedBox(height: space.m),
              Wrap(
                spacing: space.s,
                runSpacing: space.s,
                children: [
                  for (final tone in NeonTone.values)
                    NeonBadge(tone.name, tone: tone),
                ],
              ),
            ],
          ),
        ),
        Section(
          title: 'Text fields',
          note:
              'The frame lights up on focus and turns red in error; type in '
              'the first one.',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              SizedBox(
                width: 280,
                child: NeonField(
                  label: 'Name',
                  child: NeonTextField(controller: _name),
                ),
              ),
              SizedBox(
                width: 280,
                child: NeonField(
                  label: 'E-mail (error)',
                  child: NeonTextField(controller: _email, error: true),
                ),
              ),
              SizedBox(
                width: 280,
                child: NeonField(
                  label: 'Locked',
                  child: NeonTextField(controller: _locked, enabled: false),
                ),
              ),
            ],
          ),
        ),
        const Section(
          title: 'Code',
          child: NeonCode(
            'final theme = context.theme;\ntheme.colors.primary',
            language: 'dart',
          ),
        ),
        Section(
          title: 'Panel and resize handle',
          note: 'Drag the grip under the panel.',
          child: Column(
            children: [
              SizedBox(
                height: _logsHeight,
                child: NeonPanel(
                  title: 'Panel',
                  titleTrailing: const NeonBadge('live', tone: NeonTone.green),
                  trailing: NeonChip(
                    label: 'Clear',
                    selected: false,
                    onPressed: () {},
                  ),
                  child: Center(
                    child: NeonLabel('${_logsHeight.round()} px high'),
                  ),
                ),
              ),
              NeonResizeHandle(
                onDrag: (dy) => setState(
                  () => _logsHeight = (_logsHeight + dy).clamp(100, 320),
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Logo',
          child: Wrap(
            spacing: space.l,
            runSpacing: space.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: const [
              NeonLogo(text: 'NEON'),
              NeonLabel('the accent glows, a pink and a cyan copy shift'),
            ],
          ),
        ),
      ],
    );
  }
}
