import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

final class _Source implements MemoryFigureSource {
  int opened = 0;
  int closed = 0;
  int reads = 0;
  int used = 48 * 1024 * 1024;

  @override
  void open() => opened++;

  @override
  Future<List<MemoryFigure>> read() async {
    reads++;
    return [
      MemoryFigure(name: 'Heap', note: 'the heap', used: used, short: 'mem'),
      const MemoryFigure(
        name: 'Image cache',
        note: 'decoded images',
        used: 9 * 1024,
        short: 'img',
      ),
      const MemoryFigure(name: 'Resident', note: 'unavailable here'),
    ];
  }

  @override
  void close() => closed++;
}

void main() {
  testWidgets('the memory is read only while someone listens, and keeps its '
      'last samples', (tester) async {
    final source = _Source();
    final watch = DebugMemoryWatch(
      sources: [source],
      interval: const Duration(seconds: 1),
      kept: 3,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(source.reads, 0, reason: 'nobody listens');
    expect(watch.isReading, isFalse);

    void listener() {}
    watch.addListener(listener);
    await tester.pump(const Duration(seconds: 4, milliseconds: 100));
    expect(source.opened, 1);
    expect(source.reads, 5, reason: 'at once, then every second');
    expect(watch.history, hasLength(3), reason: 'only the last kept');
    expect(watch.value!.figures.first.used, source.used);

    watch.removeListener(listener);
    final reads = source.reads;
    await tester.pump(const Duration(seconds: 5));
    expect(source.reads, reads, reason: 'stopped with its last listener');
    expect(source.closed, 1);
    watch.dispose();
  });

  testWidgets('the console segment shows each figure with a short label, '
      'only while it is started', (tester) async {
    final source = _Source();
    final isolates = DebugIsolates(
      loads: IsolateLoads(const []),
      memory: DebugMemoryWatch(sources: [source]),
    );
    final segment = MemoryConsoleSegment(isolates);
    expect(segment.read(), isNull, reason: 'nothing read yet');
    await tester.pump(const Duration(seconds: 3));
    expect(source.reads, 0);

    var changes = 0;
    final stop = segment.start(() => changes++);
    await tester.pump();
    expect(segment.read().toString(), 'mem 48.0 MB · img 9.0 KB');
    expect(changes, 1);

    stop();
    final reads = source.reads;
    await tester.pump(const Duration(seconds: 3));
    expect(source.reads, reads);
    isolates.memory.dispose();
  });
}
