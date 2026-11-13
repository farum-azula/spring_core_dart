import 'package:flutter/scheduler.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_flutter_signals/src/follow_keeper.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show WidgetBuildTracker, WidgetBuildTracking;

/// Builds a Spring widget again when followed state its `build` read has
/// changed: a `@Signal` field, a `@Computed` value, the state of an
/// asynchronous one. Only what the last `build` read counts, so a widget
/// that shows the total is not built again for the coupon.
final class SignalBuildTracker implements WidgetBuildTracker {
  /// The tracker.
  const SignalBuildTracker();

  @override
  WidgetBuildTracking attach(VoidCallback rebuild) => SignalTracking(rebuild);
}

/// The followed reads of one widget's `build`.
final class SignalTracking implements WidgetBuildTracking {
  /// The tracking that asks for a build with [rebuild].
  SignalTracking(this.rebuild);

  /// Asks the widget to build again.
  final VoidCallback rebuild;

  // A build that fails goes on following what the last one followed.
  final FollowKeeper _keeper = FollowKeeper();

  void Function()? _stop;
  bool _disposed = false;

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
        signals.untracked(_changed);
        return;
      }
      built = true;
      try {
        result = _keeper.run(build);
      } on Object catch (error, stackTrace) {
        failure = error;
        failureStack = stackTrace;
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
