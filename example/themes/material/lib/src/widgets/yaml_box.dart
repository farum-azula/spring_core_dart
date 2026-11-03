import 'package:flutter/material.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

/// A few lines of the YAML that make what is shown. A test checks that every
/// line is really in lib/resources/, so the boxes cannot drift from the files.
class YamlBox extends StatelessWidget {
  const YamlBox(this.text, {super.key, this.label});

  final String text;

  /// The file the lines come from, shown above them.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.theme.spacing.m),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(context.theme.spacing.s),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: EdgeInsets.only(bottom: context.theme.spacing.s),
              child: Text(
                label!,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: colors.outline),
              ),
            ),
          SelectableText(
            text,
            style: context.theme.typography.code.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
