import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/image_cache_memory.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_figure.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/platform_memory.dart';

/// The app's memory ([MemoryFigure]s of [sources]), read every
/// [interval] only while someone listens, with the last [kept] samples
/// ([history]) for a chart: the memory block of the debug panel's
/// Isolates tab and the console's `memory` segment listen while they
/// show, so nothing is read, and no source holds anything (the VM
/// service's connection), while neither does.
final class DebugMemoryWatch extends ChangeNotifier
    implements ValueListenable<MemorySample?> {
  /// The memory of [sources], by default the platform's and the image
  /// cache's, read every [interval] while listened to.
  DebugMemoryWatch({
    List<MemoryFigureSource>? sources,
    this.interval = const Duration(seconds: 1),
    this.kept = 180,
  }) : sources =
           sources ?? [platformMemorySource(), const ImageCacheMemorySource()],
       assert(interval > Duration.zero, 'the interval must be positive');

  /// Where the figures come from, in their order.
  final List<MemoryFigureSource> sources;

  /// How often they are read.
  final Duration interval;

  /// How many samples [history] keeps: three minutes at a second.
  final int kept;

  final _history = ListQueue<MemorySample>();
  Timer? _timer;
  var _reading = false;
  var _disposed = false;

  /// The samples, oldest first, the newest last.
  Iterable<MemorySample> get history => _history;

  @override
  MemorySample? get value => _history.isEmpty ? null : _history.last;

  /// Whether it reads now: someone listens.
  bool get isReading => _timer != null;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_timer == null) {
      for (final source in sources) {
        source.open();
      }
      _timer = Timer.periodic(interval, (_) => unawaited(_read()));
      unawaited(_read());
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
    _disposed = true;
    _stop();
    super.dispose();
  }

  Future<void> _read() async {
    if (_reading) {
      return;
    }
    _reading = true;
    try {
      final figures = [for (final source in sources) ...await source.read()];
      if (_timer == null || _disposed) {
        return;
      }
      _history.addLast(MemorySample(DateTime.now(), figures));
      while (_history.length > kept) {
        _history.removeFirst();
      }
      notifyListeners();
    } finally {
      _reading = false;
    }
  }

  void _stop() {
    if (_timer == null) {
      return;
    }
    _timer!.cancel();
    _timer = null;
    for (final source in sources) {
      source.close();
    }
  }
}
