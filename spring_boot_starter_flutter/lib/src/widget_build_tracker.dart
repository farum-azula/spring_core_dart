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

/// A [WidgetBuildTracker] that is also told which widget it tracks: the
/// Spring widgets call [attachTo] with the widget's element in place of
/// [attach], so a debug tool can name the widget (`ReviewTile #3`). A
/// tracker that only implements [WidgetBuildTracker] keeps working: it
/// is called through [attach] as before.
///
/// ```dart
/// final class StoreTracker implements WidgetAwareBuildTracker {
///   @override
///   WidgetBuildTracking attach(VoidCallback rebuild) => _Tracking(rebuild);
///
///   @override
///   WidgetBuildTracking attachTo(VoidCallback rebuild, BuildContext context) =>
///       _Tracking(rebuild, context.widget.runtimeType);
/// }
/// ```
///
/// Spring has no counterpart.
abstract interface class WidgetAwareBuildTracker implements WidgetBuildTracker {
  /// The tracking of the widget of the element [context]; [rebuild] asks
  /// that widget to build again. Keep only what is needed of [context]:
  /// the tracking lives as long as the element.
  WidgetBuildTracking attachTo(VoidCallback rebuild, BuildContext context);
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
  /// The trackings that ask for a build with [rebuild], of the widget of
  /// the element [context] when given (told to a
  /// [WidgetAwareBuildTracker]).
  WidgetBuildTrackings(this.rebuild, [this.context]);

  /// Asks the widget to build again.
  final VoidCallback rebuild;

  /// The element of the widget tracked.
  final BuildContext? context;

  ApplicationContext? _applicationContext;
  List<WidgetBuildTracking> _trackings = const [];

  /// Runs [build] through the trackers of [applicationContext].
  T track<T>(ApplicationContext applicationContext, T Function() build) {
    if (!identical(applicationContext, _applicationContext)) {
      dispose();
      _applicationContext = applicationContext;
      final context = this.context;
      _trackings = [
        for (final tracker
            in applicationContext
                .getBeanProvider<WidgetBuildTracker>()
                .orderedList())
          if (context != null && tracker is WidgetAwareBuildTracker)
            tracker.attachTo(rebuild, context)
          else
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
    _applicationContext = null;
  }
}
