import 'package:material_ui/material_ui.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

/// The frame of a page: its title and a scrolling column no wider than the
/// theme's `tokens.layout.content-width`.
class PageFrame extends StatelessWidget {
  const PageFrame({
    required this.title,
    required this.intro,
    required this.children,
    super.key,
  });

  final String title;
  final String intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final space = context.theme.spacing;
    // No Scrollbar of our own: on a desktop the scroll view adds one.
    return SingleChildScrollView(
      padding: EdgeInsets.all(space.l),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: context.theme.tokens.layout.contentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.displaySmall),
              SizedBox(height: space.s),
              Text(
                intro,
                style: text.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
