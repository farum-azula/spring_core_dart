import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_signals/src/widgets/signal_build_tracker.dart';

/// Builds again when followed state its [builder] read has changed, and
/// only then: a small part of a screen that shows one value.
///
/// ```dart
/// // Built again when the total changes, not when anything else of the
/// // basket does.
/// Watch((context) => Text('${context.basket.total}'))
/// ```
///
/// A `SpringStatelessWidget` and a `SpringState` follow their own `build`
/// the same way and need no `Watch`; it is for ordinary widgets, and for
/// keeping a rebuild small.
class Watch extends StatefulWidget {
  /// The widget built by [builder].
  const Watch(this.builder, {super.key});

  /// Builds the widget; what it reads is followed.
  final WidgetBuilder builder;

  @override
  State<Watch> createState() => _WatchState();
}

class _WatchState extends State<Watch> {
  late final SignalTracking _tracking = SignalTracking(_rebuild);

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tracking.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _tracking.track(() => widget.builder(context));
}
