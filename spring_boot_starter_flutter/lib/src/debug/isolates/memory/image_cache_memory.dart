import 'package:flutter/painting.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_figure.dart';

const _note =
    'Decoded images Flutter keeps to draw again, of its maximum; live: '
    'held by a widget, pending: still loading or decoding.';

/// Flutter's image cache (`PaintingBinding.instance.imageCache`) as a
/// figure, on every platform: its bytes of the maximum, its images of the
/// maximum, those live and those pending.
final class ImageCacheMemorySource implements MemoryFigureSource {
  /// The source of the binding's image cache.
  const ImageCacheMemorySource();

  @override
  void open() {}

  @override
  Future<List<MemoryFigure>> read() async {
    final cache = PaintingBinding.instance.imageCache;
    return [
      MemoryFigure(
        name: 'Image cache',
        note: _note,
        used: cache.currentSizeBytes,
        amounts: [MemoryAmount('max', cache.maximumSizeBytes)],
        counts:
            '${cache.currentSize} / ${cache.maximumSize} images · '
            '${cache.liveImageCount} live · ${cache.pendingImageCount} pending',
        short: 'img',
      ),
    ];
  }

  @override
  void close() {}
}
