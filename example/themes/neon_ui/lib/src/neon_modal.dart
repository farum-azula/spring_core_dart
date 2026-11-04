import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:neon_ui/src/neon_glow_border.dart';

/// Shows [builder] in a dialog with the glowing, turning border. Width and
/// barrier are `tokens.neon.modal.*`.
Future<T?> showNeonModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: context.theme.tokens.neon.modal.barrier,
  pageBuilder: (context, _, _) => Center(
    child: SizedBox(
      width: context.theme.tokens.neon.modal.width,
      child: IntrinsicHeight(
        child: NeonGlowBorder(child: Builder(builder: builder)),
      ),
    ),
  ),
);
