import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The rows of the task manager ([IsolateLoads.all]), read again every
/// [interval] only while someone listens: a widget that shows them
/// listens while it is on screen, so nothing is read, and so nothing
/// measured, while none is.
///
/// The first listener reads at once, so a widget that listens before it
/// builds (a `ListenableBuilder`) has the rows in its first frame; without
/// a listener [value] is what was read last.
final class IsolateLoadsWatch extends ChangeNotifier
    implements ValueListenable<List<IsolateLoad>> {
  /// The rows of [loads], read every [interval] while listened to.
  IsolateLoadsWatch(this.loads, {this.interval = const Duration(seconds: 1)})
    : assert(interval > Duration.zero, 'the interval must be positive');

  /// What is read.
  final IsolateLoads loads;

  /// How often it is read.
  final Duration interval;

  List<IsolateLoad> _value = const [];
  Timer? _timer;

  @override
  List<IsolateLoad> get value => _value;

  /// Whether it reads now: someone listens.
  bool get isReading => _timer != null;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_timer == null) {
      _value = loads.all();
      _timer = Timer.periodic(interval, (_) {
        _value = loads.all();
        notifyListeners();
      });
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }
}
