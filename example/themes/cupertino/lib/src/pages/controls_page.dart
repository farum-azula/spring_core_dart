import 'package:flutter/cupertino.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

/// A gallery of Cupertino's own controls, each with the line of YAML that
/// reaches it: `cupertino.*` by itself, or a `colors.*` the app passes.
class ControlsPage extends StatefulWidget {
  const ControlsPage({super.key});

  @override
  State<ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<ControlsPage> {
  bool _switch = true;
  bool _checkbox = true;
  int _radio = 1;
  double _slider = 0.4;
  String _segment = 'Day';
  String _sliding = 'Week';
  int _pick = 2;
  DateTime _date = DateTime(2026, 11, 2);
  String _chose = 'nothing yet';

  Future<void> _sheet() async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Share the theme'),
        message: const Text(
          'The sheet reads primary-color and the text styles.',
        ),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, 'Copy the YAML'),
            child: const Text('Copy the YAML'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'Send a link'),
            child: const Text('Send a link'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'Reset'),
            child: const Text('Reset'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(context.messages.themes.cancel),
        ),
      ),
    );
    if (choice != null && mounted) {
      setState(() => _chose = 'action sheet: $choice');
    }
  }

  Future<void> _alert() async {
    final choice = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Switch to dark?'),
        content: const Text(
          'The dialog\'s buttons use primary-color; the destructive one '
          'uses iOS\'s red.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, 'Not now'),
            child: const Text('Not now'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, 'Switch'),
            child: const Text('Switch'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'Delete'),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (choice != null && mounted) {
      setState(() => _chose = 'alert dialog: $choice');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    final colors = theme.colors;
    final days = theme.tokens.chart.days;
    final text = CupertinoTheme.of(context).textTheme;
    Widget wrap(List<Widget> children) => Wrap(
      spacing: space.m,
      runSpacing: space.s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
    return PageFrame(
      title: context.messages.nav.controls,
      intro:
          'The controls of Cupertino, as they come. None has a line of its '
          'own in the YAML: they read the CupertinoThemeData (the primary '
          'color, the text styles), and the few that take a color from '
          'somewhere else get one from `colors.*`. Under each: where its '
          'look comes from.',
      children: [
        Section(
          title: 'What reaches them',
          child: const YamlBox(
            r'primary-color: $colors.primary'
            '\n'
            r'primary-contrasting-color: $colors.on-primary'
            '\n'
            r'scaffold-background-color: $colors.surface'
            '\n'
            'nav-title-text-style: { size: 17, weight: 600 }\n'
            'picker-text-style: { size: 21 }\n'
            'date-time-picker-text-style: { size: 21 }\n'
            "secondary: '#34C759'\n"
            "surface-container-high: '#E9E9EB'",
            label: 'application.yml: cupertino and colors',
          ),
        ),
        Section(
          title: 'Buttons',
          note:
              'CupertinoButton: the label is primary-color in the '
              'action-text-style; filled has primary-color as its fill and '
              'primary-contrasting-color as its label; tinted has a faded '
              'primary-color.',
          child: wrap([
            CupertinoButton(onPressed: () {}, child: const Text('Plain')),
            CupertinoButton.tinted(
              onPressed: () {},
              child: const Text('Tinted'),
            ),
            CupertinoButton.filled(
              onPressed: () {},
              child: const Text('Filled'),
            ),
            const CupertinoButton.filled(
              onPressed: null,
              child: Text('Disabled'),
            ),
            CupertinoButton.filled(
              onPressed: () {},
              sizeStyle: CupertinoButtonSize.small,
              child: const Text('Small'),
            ),
          ]),
        ),
        Section(
          title: 'Switch, checkbox, radio',
          note:
              'The checkbox and the radios take primary-color. The switch '
              'is iOS green by default; here it takes colors.secondary, '
              'which the app declares green too.',
          child: wrap([
            CupertinoSwitch(
              value: _switch,
              activeTrackColor: colors.secondary,
              onChanged: (value) => setState(() => _switch = value),
            ),
            CupertinoCheckbox(
              value: _checkbox,
              onChanged: (value) => setState(() => _checkbox = value ?? false),
            ),
            RadioGroup<int>(
              groupValue: _radio,
              onChanged: (value) => setState(() => _radio = value ?? 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) CupertinoRadio<int>(value: i),
                ],
              ),
            ),
          ]),
        ),
        Section(
          title: 'Slider',
          note: 'CupertinoSlider: the active part is primary-color.',
          child: Row(
            children: [
              Expanded(
                child: CupertinoSlider(
                  value: _slider,
                  onChanged: (value) => setState(() => _slider = value),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(_slider * 100).round()}%',
                  style: text.textStyle,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Segmented controls',
          note:
              'CupertinoSegmentedControl: primary-color for the selected '
              'segment and the border. CupertinoSlidingSegmentedControl: '
              'a thumb that slides on a track; the track takes '
              'colors.surface-container-high.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CupertinoSegmentedControl<String>(
                groupValue: _segment,
                onValueChanged: (value) => setState(() => _segment = value),
                children: const {
                  'Day': Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Day'),
                  ),
                  'Week': Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Week'),
                  ),
                  'Month': Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Month'),
                  ),
                },
              ),
              SizedBox(height: space.m),
              CupertinoSlidingSegmentedControl<String>(
                groupValue: _sliding,
                backgroundColor: colors.surfaceContainerHigh,
                thumbColor: colors.surfaceContainerLowest,
                onValueChanged: (value) =>
                    setState(() => _sliding = value ?? 'Week'),
                children: const {
                  'Day': Text('Day'),
                  'Week': Text('Week'),
                  'Month': Text('Month'),
                },
              ),
            ],
          ),
        ),
        Section(
          title: 'Picker',
          note:
              'CupertinoPicker: the items use picker-text-style (21 pt). '
              'The items here are tokens.chart.days.',
          child: SizedBox(
            height: 130,
            child: CupertinoPicker(
              itemExtent: 36,
              scrollController: FixedExtentScrollController(initialItem: _pick),
              onSelectedItemChanged: (index) => setState(() => _pick = index),
              children: [for (final day in days) Center(child: Text(day))],
            ),
          ),
        ),
        Section(
          title: 'Date picker',
          note:
              'CupertinoDatePicker: the wheels use '
              'date-time-picker-text-style (21 pt).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 180,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _date,
                  onDateTimeChanged: (value) => setState(() => _date = value),
                ),
              ),
              Text(
                'Picked: ${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                style: text.textStyle.copyWith(
                  fontSize: 13,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Action sheet, alert dialog, context menu',
          note:
              'The sheet and the dialog are routes above the app, in the '
              'same CupertinoTheme: primary-color for their actions. Press '
              'and hold the card for the context menu.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              wrap([
                CupertinoButton.tinted(
                  onPressed: _sheet,
                  child: const Text('Action sheet'),
                ),
                CupertinoButton.tinted(
                  onPressed: _alert,
                  child: const Text('Alert dialog'),
                ),
              ]),
              SizedBox(height: space.s),
              Text(
                'You chose: $_chose',
                style: text.textStyle.copyWith(
                  fontSize: 13,
                  color: colors.onSurfaceVariant,
                ),
              ),
              SizedBox(height: space.m),
              SizedBox(
                width: 200,
                height: 80,
                child: CupertinoContextMenu(
                  actions: [
                    CupertinoContextMenuAction(
                      trailingIcon: CupertinoIcons.share,
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Share'),
                    ),
                    CupertinoContextMenuAction(
                      isDefaultAction: true,
                      trailingIcon: CupertinoIcons.heart,
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Favorite'),
                    ),
                    CupertinoContextMenuAction(
                      isDestructiveAction: true,
                      trailingIcon: CupertinoIcons.delete,
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Delete'),
                    ),
                  ],
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(
                        theme.tokens.layout.card.radius,
                      ),
                    ),
                    child: Text(
                      'Press and hold',
                      style: text.textStyle.copyWith(color: colors.onPrimary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'List section and tiles',
          note:
              'CupertinoListSection and CupertinoListTile use iOS\'s grouped '
              'greys by default. Here the section takes the card color and '
              'the separator color from colors.* so every theme owns them.',
          child: CupertinoListSection.insetGrouped(
            margin: EdgeInsets.zero,
            backgroundColor: CupertinoColors.transparent,
            separatorColor: colors.outline,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(
                theme.tokens.layout.card.radius,
              ),
            ),
            children: [
              CupertinoListTile.notched(
                backgroundColor: CupertinoColors.transparent,
                leading: _Badge(CupertinoIcons.wifi, colors.primary),
                title: const Text('Wi-Fi'),
                additionalInfo: const Text('Home'),
                trailing: const CupertinoListTileChevron(),
                onTap: () {},
              ),
              CupertinoListTile.notched(
                backgroundColor: CupertinoColors.transparent,
                leading: _Badge(CupertinoIcons.airplane, colors.tertiary),
                title: const Text('Airplane mode'),
                trailing: CupertinoSwitch(
                  value: _switch,
                  activeTrackColor: colors.secondary,
                  onChanged: (value) => setState(() => _switch = value),
                ),
              ),
              CupertinoListTile.notched(
                backgroundColor: CupertinoColors.transparent,
                leading: _Badge(CupertinoIcons.bell_fill, colors.error),
                title: const Text('Notifications'),
                subtitle: const Text('Banners, sounds'),
                trailing: const CupertinoListTileChevron(),
                onTap: () {},
              ),
            ],
          ),
        ),
        Section(
          title: 'Search field and text field',
          note:
              'Both take their text from the theme\'s text style and the '
              'cursor and selection from primary-color (the handles from '
              'selection-handle-color). The fill is ours: '
              'colors.surface-container-high.',
          child: Column(
            children: [
              CupertinoSearchTextField(
                placeholder: 'Search',
                backgroundColor: colors.surfaceContainerHigh,
              ),
              SizedBox(height: space.m),
              CupertinoTextField(
                placeholder: 'Name',
                padding: EdgeInsets.all(space.m),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(
                    theme.tokens.corner.tiny,
                  ),
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Activity indicator',
          note:
              'CupertinoActivityIndicator is grey unless told; colors.primary '
              'tints the second. The last is a partly pulled indicator '
              '(a refresh): 60%.',
          child: wrap([
            const CupertinoActivityIndicator(radius: 14),
            CupertinoActivityIndicator(radius: 14, color: colors.primary),
            CupertinoActivityIndicator.partiallyRevealed(
              radius: 14,
              progress: 0.6,
              color: colors.tertiary,
            ),
          ]),
        ),
      ],
    );
  }
}

/// The colored square with an icon that iOS settings rows have.
class _Badge extends StatelessWidget {
  const _Badge(this.icon, this.color);

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Icon(icon, size: 18, color: context.theme.colors.onPrimary),
  );
}
