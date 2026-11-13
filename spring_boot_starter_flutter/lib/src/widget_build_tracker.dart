import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Follows what the `build` of a Spring widget reads, to build it again
/// when that changes: the way a state library of another package (signals)
/// joins the Spring widgets, beside the `Listenable` beans they follow by
/// themselves.
///
/// Declare a bean of this type. Every `SpringStatelessWidget` and
/// `SpringState` then runs its `build` through each of them:
///
/// ```dart
/// final class StoreTracker implements WidgetBuildTracker {
///   @override
///   WidgetBuildTracking attach(VoidCallback rebuild) => _Tracking(rebuild);
/// }
/// ```
///
/// Spring has no counterpart.
abstract interface class WidgetBuildTracker {
  /// The tracking of one widget on the screen; [rebuild] asks that widget
  /// to build again.
  WidgetBuildTracking attach(VoidCallback rebuild);
}

/// What a [WidgetBuildTracker] keeps for one widget.
abstract interface class WidgetBuildTracking {
  /// Runs [build] and notes what it read; from then on a change of any of
  /// it calls the widget's `rebuild`, once, until the next [track].
  T track<T>(T Function() build);

  /// The widget left the screen: nothing is followed any more.
  void dispose();
}

/// The trackings of one widget: one per [WidgetBuildTracker] bean of the
/// application, made when the widget first builds.
final class WidgetBuildTrackings {
  /// The trackings that ask for a build with [rebuild].
  WidgetBuildTrackings(this.rebuild);

  /// Asks the widget to build again.
  final VoidCallback rebuild;

  ApplicationContext? _context;
  List<WidgetBuildTracking> _trackings = const [];

  /// Runs [build] through the trackers of [context].
  T track<T>(ApplicationContext context, T Function() build) {
    if (!identical(context, _context)) {
      dispose();
      _context = context;
      _trackings = [
        for (final tracker
            in context.getBeanProvider<WidgetBuildTracker>().orderedList())
          tracker.attach(rebuild),
      ];
    }
    var tracked = build;
    for (final tracking in _trackings) {
      final inner = tracked;
      tracked = () => tracking.track(inner);
    }
    return tracked();
  }

  /// Ends every tracking.
  void dispose() {
    for (final tracking in _trackings) {
      tracking.dispose();
    }
    _trackings = const [];
    _context = null;
  }
}
