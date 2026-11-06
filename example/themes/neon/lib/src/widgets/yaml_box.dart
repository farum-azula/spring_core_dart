import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';

/// A few lines of the YAML that make what is shown, in a NeonCode block
/// (Markdown, colored by the theme's `styles.code`). A
/// test checks that every line is really in this app's `lib/resources/` or in
/// neon_ui's `themes/neon.yml`, so the boxes cannot drift from the files.
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
          child: NeonLabel(label!),
        ),
      NeonCode(text, language: 'yaml'),
    ],
  );
}
