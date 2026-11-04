import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The `neon-gate` loader kind: the splash of NEON. Dark panels slide in
/// from different sides, one after the other, and close like a gate: two
/// halves meet at a slanted seam, platforms come in over them from the top,
/// the bottom and the sides. Their edges glow in cyan and red and flicker a
/// little. In the middle an angled box outlined in red fills by the
/// progress and counts the percentage (the text is the style
/// `label-small`). When the work is done the box goes and the panels part
/// the way they came, platforms first, the gate last; with the splash's
/// `exit.reveal` they part over the app, which is already there.
///
/// The colors, sizes and times come from the loader in the theme
/// (`themes/neon.yml`): `gate`, `edge`, `flicker`, `box`, `label`, and the
/// phases `enter` (the panels slide in), `fill` (follows the progress, with
/// a `min-duration`) and `exit` (they part). Each panel eases on its own
/// share of a phase, so the phases themselves are linear. The geometry is
/// here, the same numbers as the page loader
/// (`lib/resources/loaders/neon-gate.html`), which draws the same before
/// Flutter runs; the splash goes on from the time and progress it reached,
/// so nothing jumps at the hand-off. With "reduce motion" the gate stands
/// closed and nothing flickers or slides.
@ThemeLoaderKind('neon-gate')
class NeonGateLoader extends ThemeLoaderWidget<NeonGateLoaderProps> {
  /// Creates the loader; the generated code registers one.
  const NeonGateLoader();

  @override
  Widget build(BuildContext context, LoaderFrame<NeonGateLoaderProps> frame) {
    final reduce = frame.reduceMotion;
    // With less motion the gate stands closed, whatever the phases say
    // (they are all at their end).
    final enter = reduce ? 1.0 : frame.phase('enter');
    final exit = reduce ? 0.0 : frame.phase('exit');
    if (enter <= 0 || exit >= 1) {
      return const SizedBox.expand();
    }
    final fill = frame.phase('fill').clamp(0.0, 1.0);
    final props = frame.props;
    return Semantics(
      label: '${props.label.text} ${(fill * 100).round()} %',
      child: SizedBox.expand(
        child: CustomPaint(
          isComplex: true,
          painter: _GatePainter(
            props: props,
            enter: enter,
            exit: exit,
            fill: fill,
            elapsed: reduce ? Duration.zero : frame.elapsed,
            label: context.theme.typography.labelSmall,
          ),
        ),
      ),
    );
  }
}

/// One panel of the gate: its shape and glowing edge (in percent of the
/// screen), whether it is a platform (the lighter color) and its edge the
/// accent, where it comes from and goes (a share of the screen), when it
/// moves in each phase (start and length, shares of the phase) and the
/// phase of its flicker (a share of a cycle).
class _Panel {
  const _Panel(
    this.shape,
    this.edge, {
    required this.from,
    required this.enter,
    required this.exit,
    required this.flicker,
    this.platform = false,
    this.accent = false,
  });

  final List<Offset> shape;
  final List<Offset> edge;
  final Offset from;
  final (double, double) enter;
  final (double, double) exit;
  final double flicker;
  final bool platform;
  final bool accent;
}

// Back to front. The page loader has the same numbers.
const _panels = [
  // The gate: two halves that meet at a slanted seam; the left one is
  // over the right one, so its edge is the seam.
  _Panel(
    [Offset(55.6, -2), Offset(102, -2), Offset(102, 102), Offset(43.6, 102)],
    [Offset(58, -2), Offset(46, 102)],
    from: Offset(1.1, 0),
    enter: (0.08, 0.5),
    exit: (0.44, 0.56),
    flicker: 0.66,
    accent: true,
  ),
  _Panel(
    [Offset(-2, -2), Offset(56.4, -2), Offset(44.4, 102), Offset(-2, 102)],
    [Offset(56.4, -2), Offset(44.4, 102)],
    from: Offset(-1.1, 0),
    enter: (0, 0.5),
    exit: (0.4, 0.6),
    flicker: 0.41,
  ),
  // The platforms over it: the top, the bottom, one at each side.
  _Panel(
    [
      Offset(-2, -2),
      Offset(102, -2),
      Offset(102, 8),
      Offset(62, 8),
      Offset(58.5, 12.5),
      Offset(-2, 12.5),
    ],
    [Offset(-2, 12.5), Offset(58.5, 12.5), Offset(62, 8), Offset(102, 8)],
    from: Offset(0, -1.1),
    enter: (0.3, 0.42),
    exit: (0.2, 0.4),
    flicker: 0.17,
    platform: true,
    accent: true,
  ),
  _Panel(
    [
      Offset(-2, 102),
      Offset(102, 102),
      Offset(102, 87.5),
      Offset(42, 87.5),
      Offset(38.5, 92),
      Offset(-2, 92),
    ],
    [Offset(-2, 92), Offset(38.5, 92), Offset(42, 87.5), Offset(102, 87.5)],
    from: Offset(0, 1.1),
    enter: (0.38, 0.42),
    exit: (0.24, 0.4),
    flicker: 0.53,
    platform: true,
  ),
  _Panel(
    [Offset(-2, 30), Offset(33, 30), Offset(30.5, 36), Offset(-2, 36)],
    [Offset(-2, 30), Offset(33, 30), Offset(30.5, 36)],
    from: Offset(-1.1, 0),
    enter: (0.5, 0.4),
    exit: (0.04, 0.36),
    flicker: 0.79,
    platform: true,
  ),
  _Panel(
    [Offset(69.5, 64), Offset(102, 64), Offset(102, 70), Offset(67, 70)],
    [Offset(69.5, 64), Offset(67, 70), Offset(102, 70)],
    from: Offset(1.1, 0),
    enter: (0.58, 0.42),
    exit: (0, 0.36),
    flicker: 0.29,
    platform: true,
    accent: true,
  ),
];

// When the box comes (a share of enter) and goes (a share of exit).
const _boxIn = (0.8, 0.2);
const _boxOut = (0.0, 0.2);

// The easing of a panel coming in and going out: Material's emphasized
// decelerate and accelerate (cubic-bezier(.05,.7,.1,1) and
// cubic-bezier(.3,0,.8,.15) on the page).
const _in = Cubic(0.05, 0.7, 0.1, 1);
const _out = Cubic(0.3, 0, 0.8, 0.15);

// How much the edges dim over a flicker cycle: (share, depth), linear
// between; the page's @keyframes ng-flick.
const _flicker = [
  (0.0, 0.0),
  (0.05, 0.0),
  (0.06, 0.9),
  (0.08, 0.1),
  (0.1, 0.6),
  (0.12, 0.0),
  (0.55, 0.0),
  (0.56, 0.7),
  (0.58, 0.0),
  (0.6, 0.4),
  (0.62, 0.0),
  (1.0, 0.0),
];

double _depth(double t) {
  for (var i = 1; i < _flicker.length; i++) {
    final (t1, v1) = _flicker[i];
    if (t <= t1) {
      final (t0, v0) = _flicker[i - 1];
      return t1 == t0 ? v1 : v0 + (v1 - v0) * (t - t0) / (t1 - t0);
    }
  }
  return 0;
}

// Where a part is in a phase at [t]: 0 before its start, 1 after its end.
double _local(double t, (double, double) timing) =>
    ((t - timing.$1) / timing.$2).clamp(0.0, 1.0);

const _rad = math.pi / 180;

class _GatePainter extends CustomPainter {
  _GatePainter({
    required this.props,
    required this.enter,
    required this.exit,
    required this.fill,
    required this.elapsed,
    required this.label,
  });

  final NeonGateLoaderProps props;
  final double enter;
  final double exit;
  final double fill;
  final Duration elapsed;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final period = props.flicker.duration.inMicroseconds;
    final cycle = period <= 0 ? 0.0 : (elapsed.inMicroseconds / period) % 1;
    for (final panel in _panels) {
      // In: eased from its side; out: eased back the same way.
      final shown =
          _in.transform(_local(enter, panel.enter)) -
          _out.transform(_local(exit, panel.exit));
      if (shown <= 0) {
        continue;
      }
      final away = 1 - shown;
      canvas
        ..save()
        ..translate(
          away * panel.from.dx * size.width,
          away * panel.from.dy * size.height,
        );
      _panel(canvas, size, panel, cycle);
      canvas.restore();
    }
    _box(canvas, size);
  }

  Path _path(Size size, List<Offset> points, {bool close = true}) {
    Offset p(Offset o) =>
        Offset(o.dx * size.width / 100, o.dy * size.height / 100);
    final path = Path()..moveTo(p(points.first).dx, p(points.first).dy);
    for (final point in points.skip(1)) {
      path.lineTo(p(point).dx, p(point).dy);
    }
    return close ? (path..close()) : path;
  }

  void _panel(Canvas canvas, Size size, _Panel panel, double cycle) {
    final gate = props.gate;
    final edge = props.edge;
    canvas.drawPath(
      _path(size, panel.shape),
      Paint()..color = panel.platform ? gate.panel : gate.color,
    );
    final color = panel.accent ? edge.accent : edge.color;
    final alpha = 1 - props.flicker.dim * _depth((cycle + panel.flicker) % 1);
    final line = _path(size, panel.edge, close: false);
    final lit = color.withValues(alpha: color.a * alpha);
    canvas
      ..drawPath(
        line,
        Paint()
          ..color = lit
          ..style = PaintingStyle.stroke
          ..strokeWidth = edge.width * 2
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, edge.glow),
      )
      ..drawPath(
        line,
        Paint()
          ..color = lit
          ..style = PaintingStyle.stroke
          ..strokeWidth = edge.width,
      );
  }

  TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  // The box: angled, outlined in red, filled by the progress, the label at
  // the left and the number at the right.
  void _box(Canvas canvas, Size size) {
    final b = props.box;
    final come = _in.transform(_local(enter, _boxIn));
    final alpha = come * (1 - _local(exit, _boxOut));
    if (alpha <= 0) {
      return;
    }
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: math.min(b.width, size.width * 0.6),
      height: b.height,
    );
    final inner = rect.deflate(2);
    canvas
      ..saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
      )
      ..translate(size.width / 2, size.height / 2 + (1 - come) * 16)
      ..transform(Matrix4.skewX(math.tan(b.skew * _rad)).storage)
      ..drawRect(
        rect.inflate(1),
        Paint()
          ..color = b.color.withValues(alpha: b.color.a * 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, b.glow),
      )
      ..drawRect(
        inner,
        Paint()..color = Color.lerp(props.gate.color, b.color, 0.12)!,
      );
    final lit = Rect.fromLTWH(
      inner.left,
      inner.top,
      inner.width * fill,
      inner.height,
    );
    if (lit.width > 0) {
      canvas
        ..drawRect(lit, Paint()..color = b.fill)
        ..drawRect(
          Rect.fromLTRB(
            math.max(lit.left, lit.right - 2),
            lit.top,
            lit.right,
            lit.bottom,
          ),
          Paint()..color = const Color(0xD9FFFFFF),
        );
    }
    canvas.drawRect(
      rect.deflate(1),
      Paint()
        ..color = b.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final lab = props.label;
    final name = _text(
      lab.text.toUpperCase(),
      label.copyWith(
        fontSize: lab.size,
        letterSpacing: lab.letterSpacing,
        color: b.text,
        decoration: TextDecoration.none,
      ),
    );
    name.paint(
      canvas,
      Offset(inner.left + 12, inner.center.dy - name.height / 2),
    );
    final number = _text(
      '${(fill * 100).round()}%',
      label.copyWith(
        fontSize: b.height * 0.42,
        letterSpacing: 1,
        color: b.text,
        decoration: TextDecoration.none,
      ),
    );
    number
      ..paint(
        canvas,
        Offset(
          inner.right - 12 - number.width,
          inner.center.dy - number.height / 2,
        ),
      )
      ..dispose();
    name.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GatePainter old) => true;
}
