import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';

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
    final text = CupertinoTheme.of(context).textTheme.textStyle;
    final space = context.theme.spacing;
    return Padding(
      padding: EdgeInsets.only(bottom: space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          if (note != null)
            Padding(
              padding: EdgeInsets.only(top: space.xs),
              child: Text(
                note!,
                style: text.copyWith(
                  fontSize: 15,
                  color: context.theme.colors.onSurfaceVariant,
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
