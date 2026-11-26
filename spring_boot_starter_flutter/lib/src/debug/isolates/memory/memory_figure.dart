import 'package:flutter/foundation.dart';

/// An amount of memory beside a [MemoryFigure]'s use: what it is
/// ([label], `capacity`, `limit`) and its [bytes].
@immutable
final class MemoryAmount {
  /// [bytes] named [label].
  const MemoryAmount(this.label, this.bytes);

  /// What the amount is (`capacity`, `total`, `limit`, `max`).
  final String label;

  /// Its size.
  final int bytes;

  @override
  bool operator ==(Object other) =>
      other is MemoryAmount && other.label == label && other.bytes == bytes;

  @override
  int get hashCode => Object.hash(label, bytes);
}

/// One number of the memory block of the debug panel's Isolates tab: the
/// process's memory, the Dart heap, the JavaScript heap, the image cache.
///
/// A figure the platform does not tell has no [used] and says why in
/// [unavailable].
@immutable
final class MemoryFigure {
  /// The figure [name], [used] of [amounts], explained by [note].
  const MemoryFigure({
    required this.name,
    required this.note,
    this.used,
    this.amounts = const [],
    this.counts,
    this.short,
    this.unavailable,
  });

  /// What it measures (`Process (RSS)`, `Dart heap`).
  final String name;

  /// One line of what the number is, shown muted under it.
  final String note;

  /// The bytes in use; `null` when the platform does not tell.
  final int? used;

  /// What [used] is measured against (`capacity`, `total`, `limit`).
  final List<MemoryAmount> amounts;

  /// What it counts besides bytes (`12 / 1000 images · 3 live`); `null`:
  /// nothing.
  final String? counts;

  /// Its label in the debug console's `memory` segment (`mem`, `img`);
  /// `null`: not in the segment.
  final String? short;

  /// Why there is no [used] (`not in a release build`); `null` with one.
  final String? unavailable;

  @override
  bool operator ==(Object other) =>
      other is MemoryFigure &&
      other.name == name &&
      other.used == used &&
      listEquals(other.amounts, amounts) &&
      other.counts == counts &&
      other.unavailable == unavailable;

  @override
  int get hashCode =>
      Object.hash(name, used, Object.hashAll(amounts), counts, unavailable);
}

/// The figures read at one moment, oldest first in a history.
@immutable
final class MemorySample {
  /// The [figures] read at [at].
  const MemorySample(this.at, this.figures);

  /// When they were read.
  final DateTime at;

  /// The figures, in the order of their sources.
  final List<MemoryFigure> figures;
}

/// Where figures come from: the platform's memory, the image cache, or a
/// source of the application's. [open] is called when something starts
/// to show them, [close] when nothing does, so a source holds nothing (a
/// connection to the VM service) in between.
abstract interface class MemoryFigureSource {
  /// Prepares the reads (connects, lazily).
  void open();

  /// The figures now.
  Future<List<MemoryFigure>> read();

  /// Lets go of what [open] took.
  void close();
}
