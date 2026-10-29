// The providers' logos as vector paths, transcribed from the artwork the
// providers publish for sign-in buttons; sources and terms in the
// package's NOTICE and README ("Login screens"). Drawn, not shipped as
// image files: no asset to declare, sharp at any size, no SVG package.
// The Apple logo is not here: Apple's artwork license forbids
// redistributing it, so an app passes its own copy to AppleLoginButton.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The Google "G" of the Sign in with Google buttons, at its standard
/// size of 20 × 20 logical pixels (Google allows no other colours and no
/// resizing of the logo within a button).
///
/// From the `signin-assets.zip` of Google's "Sign in with Google
/// branding guidelines" (developers.google.com/identity/branding-guidelines):
/// the "G" outline masks a conic gradient and six blurred ellipses, as in
/// the SVG files there.
class GoogleLogo extends StatelessWidget {
  /// The full-colour "G", [size] logical pixels square.
  const GoogleLogo({this.size = 20, super.key});

  /// The width and height; 20 in Google's buttons.
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _GooglePainter()),
  );
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  // The "G" outline in its 20 × 20 box (the mask of Google's SVG).
  static final Path _g = Path()
    ..moveTo(19.3987, 8.1814)
    ..lineTo(9.9849, 8.1814)
    ..lineTo(9.9849, 12.0445)
    ..lineTo(15.3598, 12.0445)
    ..cubicTo(15.1286, 13.294, 14.4294, 14.3596, 13.3676, 15.0712)
    ..cubicTo(12.4746, 15.6716, 11.3266, 16.0211, 9.9849, 16.0211)
    ..cubicTo(7.3864, 16.0211, 5.1823, 14.2666, 4.3947, 11.9004)
    ..cubicTo(4.1952, 11.2989, 4.0853, 10.6599, 4.0853, 9.9983)
    ..cubicTo(4.0853, 9.3367, 4.1952, 8.6966, 4.3947, 8.0962)
    ..cubicTo(5.1823, 5.7311, 7.3864, 3.9755, 9.9849, 3.9755)
    ..cubicTo(11.4524, 3.9755, 12.767, 4.4816, 13.8039, 5.4713)
    ..lineTo(16.6653, 2.6057)
    ..cubicTo(14.936, 0.9908, 12.6786, 0, 9.9849, 0)
    ..cubicTo(6.0832, 0, 2.705, 2.2414, 1.0618, 5.5076)
    ..cubicTo(0.383, 6.8592, 0, 8.3834, 0, 9.9994)
    ..cubicTo(0, 11.6155, 0.383, 13.1396, 1.0618, 14.4913)
    ..cubicTo(2.705, 17.7597, 6.0832, 20, 9.9849, 20)
    ..cubicTo(12.6797, 20, 14.9485, 19.1137, 16.6018, 17.5861)
    ..cubicTo(18.4887, 15.8452, 19.5732, 13.2702, 19.5732, 10.2275)
    ..cubicTo(19.5732, 9.5182, 19.5131, 8.835, 19.3987, 8.1825)
    ..close();

  // The conic gradient's stops (CSS `conic-gradient(from 90deg, ...)` in
  // degrees), rotated by -45° about its centre in the SVG.
  static const _stops = <(double, int)>[
    (0, 0xFFFF4641),
    (4.14555, 0xFFFF4641),
    (39.154, 0xFF3186FF),
    (72.0044, 0xFF3186FF),
    (96.7463, 0xFF00A5B7),
    (120.897, 0xFF0EBC5F),
    (154.722, 0xFF0EBC5F),
    (179.136, 0xFF6CC400),
    (203.588, 0xFFFFCC00),
    (226.915, 0xFFFFD314),
    (251.688, 0xFFFFCC00),
    (273.129, 0xFFFF6A2B),
    (289.305, 0xFFFD4641),
    (359.593, 0xFFFF4641),
    (360, 0xFFFF4641),
  ];

  // The blurred ellipses over it: centre, radii, rotation in degrees,
  // colour (Gaussian blur, standard deviation 1).
  static const _ellipses = <(double, double, double, double, double, int)>[
    (10.0496, 10.2413, 5.39634, 2.83537, 24.4473, 0xFF3186FF),
    (23.3538, 8.2155, 7.43918, 3.09357, 0, 0xFF3186FF),
    (15.2744, 6.2195, 7.40854, 2.37805, 0, 0xFFFF4641),
    (19.5427, 2.9268, 7.40854, 2.37805, 0, 0xFFFF5B8B),
    (14.4817, 9.878, 8.5061, 3.10976, 0, 0xFF3186FF),
    (15.1842, 4.0197, 4.53882, 2.37805, -28.6599, 0xFFFF4641),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 20;
    canvas
      ..save()
      ..scale(scale)
      ..clipPath(_g);
    canvas.drawCircle(
      const Offset(10.1283, 9.7927),
      12.87,
      Paint()
        ..shader = ui.Gradient.sweep(
          const Offset(9.6819, 9.7927),
          [for (final (_, color) in _stops) Color(color)],
          [for (final (degrees, _) in _stops) degrees / 360],
          // Repeated: the start angle is not 0, so angles past the end
          // wrap round to the first stops.
          TileMode.repeated,
          -math.pi / 4,
          2 * math.pi - math.pi / 4,
        ),
    );
    // In the box's units: the blur follows the canvas's scale.
    const blur = MaskFilter.blur(BlurStyle.normal, 1);
    for (final (x, y, rx, ry, degrees, color) in _ellipses) {
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(degrees * math.pi / 180)
        ..drawOval(
          Rect.fromCenter(center: Offset.zero, width: 2 * rx, height: 2 * ry),
          Paint()
            ..color = Color(color)
            ..maskFilter = blur,
        )
        ..restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}

/// The Microsoft logo of the Sign in with Microsoft buttons: four
/// squares in its four colours, in a 21 × 21 box.
///
/// From the `ms-symbollockup_mssymbol_19.svg` of Microsoft's "Sign in with
/// Microsoft branding guidelines"
/// (learn.microsoft.com/entra/identity-platform/howto-add-branding-in-apps),
/// which may not be altered.
class MicrosoftLogo extends StatelessWidget {
  /// The four-colour logo, [size] logical pixels square.
  const MicrosoftLogo({this.size = 21, super.key});

  /// The width and height; 21 in Microsoft's buttons.
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _MicrosoftPainter()),
  );
}

class _MicrosoftPainter extends CustomPainter {
  const _MicrosoftPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 21;
    void square(double x, double y, int color) => canvas.drawRect(
      Rect.fromLTWH(x * unit, y * unit, 9 * unit, 9 * unit),
      Paint()..color = Color(color),
    );
    square(1, 1, 0xFFF25022);
    square(11, 1, 0xFF7FBA00);
    square(1, 11, 0xFF00A4EF);
    square(11, 11, 0xFFFFB900);
  }

  @override
  bool shouldRepaint(_MicrosoftPainter oldDelegate) => false;
}

/// GitHub's Invertocat mark, in black or white only (GitHub's logo rules
/// allow no other colours), in a 24 × 24 box.
///
/// From the `mark-github-24` icon of GitHub's Octicons
/// (github.com/primer/octicons, MIT license, © GitHub, Inc.); the mark is
/// GitHub's trademark, used under its logo guidelines
/// (brand.github.com), which allow it to show that an app works with
/// GitHub.
class GitHubLogo extends StatelessWidget {
  /// The mark in [color], [size] logical pixels square.
  const GitHubLogo({required this.color, this.size = 24, super.key});

  /// Black (for light backgrounds) or white (for dark ones): the only
  /// colours GitHub allows.
  final GitHubMarkColor color;

  /// The width and height.
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _GitHubPainter(
        color == GitHubMarkColor.white
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000),
      ),
    ),
  );
}

/// The two colours of GitHub's mark.
enum GitHubMarkColor {
  /// `#000000`, on light backgrounds.
  black,

  /// `#FFFFFF`, on dark backgrounds.
  white,
}

class _GitHubPainter extends CustomPainter {
  const _GitHubPainter(this.color);

  final Color color;

  static final Path _mark = Path()
    ..moveTo(10.226, 17.284)
    ..cubicTo(7.261, 16.924, 5.172, 14.791, 5.172, 12.028)
    ..cubicTo(5.172, 10.905, 5.576, 9.692, 6.25, 8.884)
    ..cubicTo(5.958, 8.143, 6.003, 6.57, 6.34, 5.919)
    ..cubicTo(7.238, 5.807, 8.451, 6.279, 9.17, 6.929)
    ..cubicTo(10.023, 6.66, 10.922, 6.525, 12.023, 6.525)
    ..cubicTo(13.123, 6.525, 14.022, 6.66, 14.83, 6.907)
    ..cubicTo(15.526, 6.278, 16.762, 5.807, 17.66, 5.919)
    ..cubicTo(17.975, 6.525, 18.02, 8.098, 17.727, 8.861)
    ..cubicTo(18.447, 9.715, 18.828, 10.861, 18.828, 12.028)
    ..cubicTo(18.828, 14.791, 16.739, 16.88, 13.73, 17.262)
    ..cubicTo(14.493, 17.756, 15.01, 18.834, 15.01, 20.069)
    ..lineTo(15.01, 22.405)
    ..cubicTo(15.01, 23.079, 15.571, 23.461, 16.245, 23.191)
    ..cubicTo(20.311, 21.641, 23.5, 17.576, 23.5, 12.545)
    ..cubicTo(23.5, 6.188, 18.334, 1, 11.978, 1)
    ..cubicTo(5.62, 1, 0.5, 6.188, 0.5, 12.545)
    ..cubicTo(0.5, 17.531, 3.667, 21.665, 7.935, 23.214)
    ..cubicTo(8.541, 23.439, 9.125, 23.034, 9.125, 22.428)
    ..lineTo(9.125, 20.63)
    ..arcToPoint(
      const Offset(8.047, 20.854),
      radius: const Radius.circular(2.9),
    )
    ..cubicTo(6.564, 20.854, 5.688, 20.046, 5.06, 18.541)
    ..cubicTo(4.813, 17.934, 4.543, 17.575, 4.026, 17.508)
    ..cubicTo(3.756, 17.485, 3.667, 17.373, 3.667, 17.238)
    ..cubicTo(3.667, 16.968, 4.117, 16.767, 4.565, 16.767)
    ..cubicTo(5.217, 16.767, 5.778, 17.171, 6.362, 18.002)
    ..cubicTo(6.812, 18.653, 7.283, 18.945, 7.845, 18.945)
    ..cubicTo(8.406, 18.945, 8.765, 18.743, 9.282, 18.226)
    ..cubicTo(9.664, 17.845, 9.956, 17.508, 10.226, 17.283)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.shortestSide / 24)
      ..drawPath(_mark, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_GitHubPainter oldDelegate) => oldDelegate.color != color;
}
