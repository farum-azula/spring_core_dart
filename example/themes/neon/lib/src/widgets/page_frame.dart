import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';

/// The frame of a page: its kicker, title and intro, then a scrolling column
/// no wider than the app's `tokens.showcase.content-width`.
class PageFrame extends StatelessWidget {
  const PageFrame({
    required this.kicker,
    required this.title,
    required this.intro,
    required this.children,
    super.key,
  });

  final String kicker;
  final String title;
  final String intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    return SingleChildScrollView(
      padding: EdgeInsets.all(space.l),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: theme.tokens.showcase.contentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NeonLabel(kicker, color: theme.colors.primary),
              SizedBox(height: space.xs),
              Text(title, style: theme.typography.headlineSmall),
              SizedBox(height: space.s),
              Text(
                intro,
                style: theme.typography.bodyLarge.copyWith(
                  color: theme.colors.onSurfaceVariant,
                ),
              ),
              SizedBox(height: space.xl),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
