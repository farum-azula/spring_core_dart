import 'package:flutter/widgets.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';

/// A titled part of a page: a heading, a line of explanation, the content,
/// all on a translucent card (the theme's `tokens.neon.panel`) so the
/// background picture does not fight the text.
class Section extends StatelessWidget {
  const Section({
    required this.title,
    required this.child,
    super.key,
    this.note,
  });

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    final neon = theme.tokens.neon;
    return Padding(
      padding: EdgeInsets.only(bottom: space.l),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(space.m),
        decoration: BoxDecoration(
          color: neon.panel,
          border: Border.all(color: neon.panelBorder, width: neon.borderWidth),
          borderRadius: BorderRadius.circular(neon.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.typography.titleLarge),
            if (note != null)
              Padding(
                padding: EdgeInsets.only(top: space.xs),
                child: Text(
                  note!,
                  style: theme.typography.bodyMedium.copyWith(
                    color: theme.colors.onSurfaceVariant,
                  ),
                ),
              ),
            SizedBox(height: space.m),
            child,
          ],
        ),
      ),
    );
  }
}
