import 'package:flutter/widgets.dart';

/// Tells whether its child is on the screen: `false` once it is scrolled
/// wholly out of the view. Checked when a scrollable above it moves and
/// after each layout, not on every frame.
class OnScreen extends StatefulWidget {
  /// [builder] is built again when the child comes to the screen or leaves
  /// it; with [enabled] `false` it is always told `true`.
  const OnScreen({super.key, required this.builder, this.enabled = true});

  /// Whether the check is made.
  final bool enabled;

  /// The child, for whether it is on the screen.
  final Widget Function(BuildContext context, bool onScreen) builder;

  @override
  State<OnScreen> createState() => _OnScreenState();
}

class _OnScreenState extends State<OnScreen> {
  ScrollPosition? _position;
  bool _onScreen = true;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = widget.enabled
        ? Scrollable.maybeOf(context)?.position
        : null;
    if (!identical(position, _position)) {
      _position?.removeListener(_check);
      _position = position?..addListener(_check);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(OnScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  /// After the layout of this frame: the box's place is known then.
  void _schedule() {
    if (_scheduled || !widget.enabled) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) {
        _check();
      }
    });
  }

  void _check() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }
    final view = View.of(context);
    final screen = Offset.zero & view.physicalSize / view.devicePixelRatio;
    final onScreen = (box.localToGlobal(Offset.zero) & box.size).overlaps(
      screen,
    );
    if (onScreen != _onScreen) {
      setState(() => _onScreen = onScreen);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, !widget.enabled || _onScreen);
}
