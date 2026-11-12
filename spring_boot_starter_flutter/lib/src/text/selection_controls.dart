import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

/// The selection handles of the starter's own selectable text in an app
/// without a design library: none where a mouse selects (the desktops),
/// two round handles in the theme's primary color where a finger does.
///
/// A design starter replaces them with its library's own through a
/// `DesignScope`. No menu: the platform's shortcuts copy.
final class SpringTextSelectionControls extends TextSelectionControls
    with TextSelectionHandleControls {
  /// The controls.
  SpringTextSelectionControls();

  /// The one instance.
  static final instance = SpringTextSelectionControls();

  static const _size = 22.0;

  static bool get _touch => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => true,
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };

  @override
  Size getHandleSize(double textLineHeight) =>
      _touch ? const Size(_size, _size) : Size.zero;

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    if (!_touch) {
      return Offset.zero;
    }
    return switch (type) {
      TextSelectionHandleType.left => const Offset(_size, 0),
      TextSelectionHandleType.right => Offset.zero,
      TextSelectionHandleType.collapsed => const Offset(_size / 2, -4),
    };
  }

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    if (!_touch) {
      return const SizedBox.shrink();
    }
    final color =
        SpringTheme.maybeOf(context)?.colorScheme.primary ??
        const Color(0xFF2196F3);
    final handle = SizedBox.square(
      dimension: _size,
      child: CustomPaint(painter: _HandlePainter(color)),
    );
    // The corner points at the text: up and to the left as drawn.
    final turned = switch (type) {
      TextSelectionHandleType.left => Transform.rotate(
        angle: math.pi / 2,
        child: handle,
      ),
      TextSelectionHandleType.right => handle,
      TextSelectionHandleType.collapsed => Transform.rotate(
        angle: math.pi / 4,
        child: handle,
      ),
    };
    return GestureDetector(onTap: onTap, child: turned);
  }
}

class _HandlePainter extends CustomPainter {
  const _HandlePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final radius = size.width / 2;
    canvas
      ..drawCircle(Offset(radius, radius), radius, paint)
      ..drawRect(Rect.fromLTWH(0, 0, radius, radius), paint);
  }

  @override
  bool shouldRepaint(_HandlePainter oldDelegate) => color != oldDelegate.color;
}
