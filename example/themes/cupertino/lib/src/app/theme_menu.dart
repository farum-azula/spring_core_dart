import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';

typedef ThemeMenuBeans = (
  ThemeSelection,
  SpringThemes,
);

/// Switches the theme: `ThemeSelection.select` with the names the
/// generator wrote in `AppThemes`. The whole app changes at once. The menu
/// is an action sheet, as on iOS.
class ThemeMenu extends SpringStatelessWidget<ThemeMenuBeans> {
  const ThemeMenu({super.key});

  Future<void> _open(BuildContext context) => showCupertinoModalPopup<void>(
    context: context,
    builder: (sheet) {
      final (
        selection,
        themes,
      ) = beans;
      return CupertinoActionSheet(
        title: Text(context.messages.themes.switch$),
        actions: [
          for (final name in [AppThemes.system, ...themes.names])
            CupertinoActionSheetAction(
              isDefaultAction: selection.active == name,
              onPressed: () {
                selection.select(name);
                Navigator.of(sheet).pop();
              },
              child: Text(selection.active == name ? '$name  ✓' : name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheet).pop(),
          child: Text(context.messages.themes.cancel),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final (
      selection,
      _,
    ) = beans;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: () => _open(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.paintbrush, size: 20),
          SizedBox(width: context.theme.spacing.xs),
          Text(
            context.messages.themes.active(selection.active),
            style: CupertinoTheme.of(context).textTheme.actionTextStyle
                .copyWith(fontSize: 15),
          ),
        ],
      ),
    );
  }
}
