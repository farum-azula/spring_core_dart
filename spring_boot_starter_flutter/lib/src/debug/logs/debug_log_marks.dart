import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show SpringLogRecord;

/// The records marked whole in the debug panel's Logs tab (its pick
/// mode): by their sequence, so a mark stays on its record while new ones
/// arrive. Marked records are what its Copy and its actions (the export)
/// take; with none marked, the tab is in its text-selection mode.
class DebugLogMarks extends ChangeNotifier {
  final _sequences = <int>{};

  /// How many records are marked.
  int get count => _sequences.length;

  /// Whether no record is marked: the tab selects text.
  bool get isEmpty => _sequences.isEmpty;

  /// Whether [record] is marked.
  bool contains(SpringLogRecord record) => _sequences.contains(record.sequence);

  /// Marks [record], or unmarks it when it is marked.
  void toggle(SpringLogRecord record) {
    if (!_sequences.remove(record.sequence)) {
      _sequences.add(record.sequence);
    }
    notifyListeners();
  }

  /// Unmarks every record: back to selecting text.
  void clear() {
    if (_sequences.isNotEmpty) {
      _sequences.clear();
      notifyListeners();
    }
  }

  /// Unmarks the records that left [records], the buffer's records
  /// oldest first: those older than its oldest (evicted), every one when
  /// it is empty (cleared). Tells its listeners only when one went.
  void prune(List<SpringLogRecord> records) {
    if (_sequences.isEmpty) {
      return;
    }
    final before = _sequences.length;
    if (records.isEmpty) {
      _sequences.clear();
    } else {
      final oldest = records.first.sequence;
      _sequences.removeWhere((sequence) => sequence < oldest);
    }
    if (_sequences.length != before) {
      notifyListeners();
    }
  }

  /// The marked ones of [records], in their order.
  List<SpringLogRecord> of(Iterable<SpringLogRecord> records) => [
    for (final record in records)
      if (_sequences.contains(record.sequence)) record,
  ];
}
