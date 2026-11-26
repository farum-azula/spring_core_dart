import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_flutter_signals/src/debug/signal_widget_names.dart';
import 'package:spring_boot_starter_flutter_signals/src/follow_keeper.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_probe.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show WidgetAwareBuildTracker, WidgetBuildTracking;

/// Builds a Spring widget again when followed state its `build` read has
/// changed: a `@Signal` field, a `@Computed` value, the state of an
/// asynchronous one. Only what the last `build` read counts, so a widget
/// that shows the total is not built again for the coupon.
///
/// With [names] (the `signalWidgetNames` bean, there only when a view of
/// the signals' debug tools is in the running app) each tracking keeps its
/// widget's element, and names it only while a tool collects; without it
/// a tracking keeps nothing of the widget.
final class SignalBuildTracker implements WidgetAwareBuildTracker {
  /// The tracker, naming the widgets by [names] when given.
  const SignalBuildTracker([this.names]);

  /// Names the widgets for the debug tools; `null` outside their build.
  final SignalWidgetNames? names;

  @override
  WidgetBuildTracking attach(VoidCallback rebuild) => SignalTracking(rebuild);

  @override
  WidgetBuildTracking attachTo(VoidCallback rebuild, BuildContext context) =>
      names?.track(rebuild, context) ?? SignalTracking(rebuild);
}

/// The followed reads of one widget's `build`.
base class SignalTracking implements WidgetBuildTracking {
  /// The tracking that asks for a build with [rebuild].
  SignalTracking(this.rebuild);

  /// Asks the widget to build again.
  final VoidCallback rebuild;

  // A build that fails goes on following what the last one followed.
  final FollowKeeper _keeper = FollowKeeper();

  void Function()? _stop;
  bool _disposed = false;

  /// What the debug tools call the widget: `a widget` unless the tracking
  /// was made by [SignalWidgetNames].
  String get label => 'a widget';

  /// Whether the widget left the screen.
  bool get disposed => _disposed;

  /// Asks the widget to build again, after the frame when called during
  /// one: a debug tool that starts collecting hears what it reads.
  void refresh() => _changed();

  @override
  T track<T>(T Function() build) {
    _stop?.call();
    T? result;
    Object? failure;
    StackTrace? failureStack;
    var built = false;
    // The effect runs the build once, noting what it read; when any of it
    // changes the effect runs again and only asks for a new build, which
    // comes back here.
    _stop = signals.effect(() {
      if (built) {
        // Still watching what it read until the new build reads it again:
        // a rebuild is no moment of nobody watching.
        _keeper.followKept();
        signals.untracked(_changed);
        return;
      }
      built = true;
      final probe = SignalProbes.current;
      probe?.beginReader(this);
      try {
        result = _keeper.run(build);
      } on Object catch (error, stackTrace) {
        failure = error;
        failureStack = stackTrace;
      } finally {
        probe?.endReader();
      }
    });
    if (failure case final error?) {
      Error.throwWithStackTrace(error, failureStack!);
    }
    return result as T;
  }

  void _changed() {
    if (_disposed) {
      return;
    }
    // A change made while widgets are being built, laid out or painted
    // (a `build` that assigns state, an effect run by one) cannot mark
    // another widget at once.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) {
          rebuild();
        }
      });
      SchedulerBinding.instance.ensureVisualUpdate();
      return;
    }
    rebuild();
  }

  @override
  void dispose() {
    _disposed = true;
    _stop?.call();
    _stop = null;
  }
}
