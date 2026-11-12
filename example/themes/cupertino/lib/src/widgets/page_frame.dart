import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/app/theme_menu.dart';

/// The frame of a page: a CupertinoPageScaffold with a large title that
/// shrinks as the page scrolls, the theme menu on its right, and a column
/// no wider than the theme's `tokens.layout.content-width`.
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
    final space = context.theme.spacing;
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(title),
            // A page of "More" has a back button on a phone; next to the
            // sidebar of a wide window it is a page like the others.
            automaticallyImplyLeading: MediaQuery.sizeOf(context).width < 840,
            trailing: const ThemeMenu(),
          ),
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: EdgeInsets.all(space.gutter),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: context.theme.tokens.layout.contentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          intro,
                          style: CupertinoTheme.of(context).textTheme.textStyle
                              .copyWith(
                                color: context.theme.colors.onSurfaceVariant,
                              ),
                        ),
                        SizedBox(height: space.xl),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
