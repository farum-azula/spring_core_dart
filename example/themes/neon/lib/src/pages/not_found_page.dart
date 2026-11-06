import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';

/// An address that is no page (`/nope`): a way back to the overview.
@ScreenRoute.notFound()
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) => PageFrame(
    kicker: 'NOT FOUND',
    title: 'No page here',
    intro: 'Nothing of this showcase is at ${context.route.uri.path}.',
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: NeonButton(
          label: 'TO THE OVERVIEW',
          onPressed: () => context.route.go('/overview'),
        ),
      ),
    ],
  );
}
