import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolates_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/big_number.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_chart.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_figure.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_watch.dart';

/// The memory block at the top of the debug panel's Isolates tab: a card
/// per figure of [memory] with its number large in the debug theme's
/// number colour, what it is measured against, a chart of the last three
/// minutes and a muted line of what it is; a figure the platform does not
/// tell says why. It listens to [memory] while on screen, so the memory
/// is read only then.
class DebugMemoryBlock extends StatelessWidget {
  /// The block of [memory].
  const DebugMemoryBlock({required this.memory, super.key});

  /// The memory, read while the block shows.
  final DebugMemoryWatch memory;

  static const double _cardWidth = 260;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return ListenableBuilder(
      listenable: memory,
      builder: (context, _) {
        final figures = memory.value?.figures ?? const <MemoryFigure>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Memory', style: style.title),
            const SizedBox(height: 8),
            if (figures.isEmpty)
              Text('Reading…', style: style.text.copyWith(color: style.muted)),
            LayoutBuilder(
              builder: (context, room) {
                final columns = math.max(
                  1,
                  math.min(figures.length, room.maxWidth ~/ _cardWidth),
                );
                final width =
                    (room.maxWidth - _gap * (columns - 1)) / columns - 0.5;
                return Wrap(
                  spacing: _gap,
                  runSpacing: _gap,
                  children: [
                    for (final figure in figures)
                      SizedBox(
                        width: width,
                        child: _FigureCard(
                          figure,
                          points: _pointsOf(figure.name),
                          window: memory.interval * memory.kept,
                          gap: memory.interval * 2.5,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  List<MemoryChartPoint> _pointsOf(String name) => [
    for (final sample in memory.history)
      for (final figure in sample.figures)
        if (figure.name == name && figure.used != null)
          (
            at: sample.at,
            used: figure.used!,
            of: figure.amounts.firstOrNull?.bytes,
          ),
  ];
}

class _FigureCard extends StatelessWidget {
  const _FigureCard(
    this.figure, {
    required this.points,
    required this.window,
    required this.gap,
  });

  final MemoryFigure figure;
  final List<MemoryChartPoint> points;
  final Duration window;
  final Duration gap;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final muted = style.text.copyWith(color: style.muted, fontSize: 11);
    final used = figure.used;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: style.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(figure.name, style: style.text.copyWith(color: style.muted)),
          const SizedBox(height: 2),
          if (used == null)
            Text(
              figure.unavailable ?? 'not available',
              style: style.code.copyWith(color: style.warning),
            )
          else ...[
            DebugBigNumber.bytes(used),
            if (figure.amounts.isNotEmpty)
              Text(
                [
                  for (final amount in figure.amounts)
                    '${amount.label} ${formatIsolateMemory(amount.bytes)}',
                ].join(' · '),
                style: style.code,
              ),
            if (figure.counts case final counts?)
              Text(counts, style: style.code),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: MemoryChart(
                points: points,
                window: window,
                gap: gap,
                color: style.number,
                line: style.line,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(figure.note, style: muted),
        ],
      ),
    );
  }
}
