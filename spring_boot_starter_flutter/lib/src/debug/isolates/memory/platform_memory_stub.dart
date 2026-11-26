import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_figure.dart';

/// The memory of a platform that tells none.
MemoryFigureSource platformMemorySource() => const _NoMemory();

final class _NoMemory implements MemoryFigureSource {
  const _NoMemory();

  @override
  void open() {}

  @override
  Future<List<MemoryFigure>> read() async => const [
    MemoryFigure(
      name: 'Memory',
      note: 'The platform tells no memory of the app.',
      unavailable: 'not available on this platform',
    ),
  ];

  @override
  void close() {}
}
