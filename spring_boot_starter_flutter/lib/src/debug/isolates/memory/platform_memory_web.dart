import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_figure.dart';

/// The memory of a web app: the page's JavaScript heap, used, total and
/// its limit, where the browser tells it (`performance.memory`,
/// Chromium).
MemoryFigureSource platformMemorySource() => const _BrowserMemory();

const _note =
    'The page\'s JavaScript heap, used of total and the most it may grow '
    'to; a WebAssembly build keeps its Dart objects here too. Chromium '
    'rounds it.';

final class _BrowserMemory implements MemoryFigureSource {
  const _BrowserMemory();

  @override
  void open() {}

  @override
  Future<List<MemoryFigure>> read() async {
    final memory = _memory();
    final used = memory?.usedJSHeapSize;
    return [
      MemoryFigure(
        name: 'JS heap',
        note: _note,
        used: used?.toInt(),
        amounts: [
          if (memory?.totalJSHeapSize case final total?)
            MemoryAmount('total', total.toInt()),
          if (memory?.jsHeapSizeLimit case final limit?)
            MemoryAmount('limit', limit.toInt()),
        ],
        short: 'mem',
        unavailable: used == null
            ? 'this browser does not tell (performance.memory: Chromium)'
            : null,
      ),
    ];
  }

  @override
  void close() {}

  static _Memory? _memory() {
    try {
      final performance = globalContext['performance'];
      if (performance.isUndefinedOrNull) {
        return null;
      }
      final memory = (performance! as JSObject)['memory'];
      return memory.isUndefinedOrNull ? null : memory! as _Memory;
    } on Object {
      return null;
    }
  }
}

extension type _Memory._(JSObject _) implements JSObject {
  external double? get usedJSHeapSize;
  external double? get totalJSHeapSize;
  external double? get jsHeapSizeLimit;
}
