import 'package:material_ui/material_ui.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

/// A titled part of a page: a heading, one line of explanation, then the
/// content.
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
    final text = Theme.of(context).textTheme;
    final space = context.theme.spacing;
    return Padding(
      padding: EdgeInsets.only(bottom: space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleLarge),
          if (note != null)
            Padding(
              padding: EdgeInsets.only(top: space.xs),
              child: Text(
                note!,
                style: text.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          SizedBox(height: space.m),
          child,
        ],
      ),
    );
  }
}
