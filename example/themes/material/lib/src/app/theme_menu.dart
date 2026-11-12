import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

typedef ThemeMenuBeans = (
  ThemeSelection,
  SpringThemes,
);

/// Switches the theme: `ThemeSelection.select` with the names the
/// generator wrote in `AppThemes`. The whole app changes at once.
class ThemeMenu extends SpringStatelessWidget<ThemeMenuBeans> {
  const ThemeMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final (
      selection,
      themes,
    ) = beans;
    return PopupMenuButton<String>(
      tooltip: context.messages.themes.switch$,
      onSelected: selection.select,
      itemBuilder: (_) => [
        for (final name in [AppThemes.system, ...themes.names])
          CheckedPopupMenuItem(
            value: name,
            checked: selection.active == name,
            child: Text(name),
          ),
      ],
      child: Padding(
        padding: EdgeInsets.all(context.theme.spacing.s),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.palette_outlined),
            SizedBox(width: context.theme.spacing.s),
            Text(context.messages.themes.active(selection.active)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
