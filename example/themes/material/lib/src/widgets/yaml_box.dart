import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

/// A few lines of the YAML that make what is shown, as a block of Markdown
/// colored by the theme's `styles.code`. A test checks that every line is
/// really in lib/resources/, so the boxes cannot drift from the files.
class YamlBox extends StatelessWidget {
  const YamlBox(this.text, {super.key, this.label});

  final String text;

  /// The file the lines come from, shown above them.
  final String? label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null)
        Padding(
          padding: EdgeInsets.only(bottom: context.theme.spacing.xs),
          child: Text(
            label!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      MarkdownView.code(text, language: 'yaml'),
    ],
  );
}
