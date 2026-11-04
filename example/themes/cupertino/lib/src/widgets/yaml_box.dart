import 'package:flutter/cupertino.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';

/// A few lines of the YAML that make what is shown. A test checks that every
/// line is really in lib/resources/, so the boxes cannot drift from the files.
class YamlBox extends StatelessWidget {
  const YamlBox(this.text, {super.key, this.label});

  final String text;

  /// The file the lines come from, shown above them.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final code = context.theme.typography.code;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.theme.spacing.m),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(context.theme.tokens.corner.tiny),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: EdgeInsets.only(bottom: context.theme.spacing.s),
              child: Text(
                label!,
                style: code.copyWith(
                  fontSize: 11,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          Text(text, style: code.copyWith(color: colors.onSurface)),
        ],
      ),
    );
  }
}
