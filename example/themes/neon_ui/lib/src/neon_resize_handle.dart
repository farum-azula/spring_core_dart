import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// A horizontal grip that reports vertical drags, for resizable panels:
/// `styles.neon-resize-handle` (lit on hover and while dragged).
class NeonResizeHandle extends StatelessWidget {
  const NeonResizeHandle({super.key, required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
    child: ThemeStates(
      style: context.theme.styles.neonResizeHandle,
      // A grip has no action, but only an enabled one shows hover.
      onPressed: () {},
      mouseCursor: SystemMouseCursors.resizeRow,
      builder: (context, s) => SizedBox(
        height: s.height,
        child: Center(
          child: Container(
            width: context.theme.tokens.neon.gripWidth,
            height: s.thickness,
            decoration: BoxDecoration(
              color: s.color,
              borderRadius: BorderRadius.circular(s.radius),
            ),
          ),
        ),
      ),
    ),
  );
}
