import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show IsolateLoad;
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_chart.dart'
    show formatTimelineDuration;

const _none = '–';

/// A share as a percentage (`42%`); a dash for none.
String formatIsolateBusy(double? busy) =>
    busy == null ? _none : '${(busy * 100).round()}%';

/// A lag as `0.3ms`, `12ms` or `1.2s`; a dash for none.
String formatIsolateLag(Duration? lag) =>
    lag == null ? _none : formatTimelineDuration(lag);

const _memoryUnits = ['B', 'KB', 'MB', 'GB'];

/// Bytes as `812 KB`, `48.3 MB` or `1.2 GB`; a dash for none.
String formatIsolateMemory(int? bytes) {
  if (bytes == null) {
    return _none;
  }
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _memoryUnits.length - 1) {
    value /= 1024;
    unit++;
  }
  final number = unit == 0 || value >= 100
      ? '${value.round()}'
      : value.toStringAsFixed(1);
  return '$number ${_memoryUnits[unit]}';
}

// How the details whose names end so are written.
final _detailUnits = <(String, String Function(num))>[
  (
    'Micros',
    (value) => formatIsolateLag(Duration(microseconds: value.round())),
  ),
  ('Bytes', (value) => formatIsolateMemory(value.round())),
];

/// One of [IsolateLoad.details] as text: a name ending in `Micros` as a
/// duration (`build 1.2ms`), one ending in `Bytes` as a size, any other as
/// it is (`frames 120`).
String formatIsolateDetail(String name, Object? value) {
  for (final (suffix, format) in _detailUnits) {
    if (value is num && name.endsWith(suffix)) {
      final short = name.substring(0, name.length - suffix.length);
      return '$short ${format(value)}';
    }
  }
  return '$name $value';
}

/// How busy a row is, as a bar: the accent's color, the warning's from a
/// half, the error's from four fifths. Empty for none.
class IsolateBusyBar extends StatelessWidget {
  /// The bar of [busy], `0` to `1`.
  const IsolateBusyBar(this.busy, {super.key});

  /// The share of the time the row was working.
  final double? busy;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final busy = (this.busy ?? 0).clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.line,
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: busy,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: busy >= 0.8
                ? style.error
                : busy >= 0.5
                ? style.warning
                : style.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

// A column of the table after the name: its title, its width, its text.
typedef _Column = ({
  String title,
  double width,
  String Function(IsolateLoad load) text,
});

final _columns = <_Column>[
  (title: 'kind', width: 56, text: (load) => load.kind),
  (title: 'busy', width: 44, text: (load) => formatIsolateBusy(load.busy)),
  (title: 'lag', width: 56, text: (load) => formatIsolateLag(load.lag)),
  (title: 'max lag', width: 60, text: (load) => formatIsolateLag(load.maxLag)),
  (title: 'active', width: 48, text: (load) => '${load.active ?? _none}'),
  (
    title: 'memory',
    width: 64,
    text: (load) => formatIsolateMemory(load.memory),
  ),
];

const _nameWidth = 88.0;

/// The task manager in full: every row of [rows] with its name, kind,
/// how busy it is, its lag and its longest, what it works on and its
/// memory (the process's, in the `main` row), and its details below.
/// "Copy JSON" copies the rows ([IsolateLoad.toJson]).
///
/// It listens to [rows] while it is on screen: with an
/// `IsolateLoadsWatch` they are read only then. A screen narrower than
/// the table scrolls it sideways.
class IsolatesView extends StatefulWidget {
  /// The view of [rows].
  const IsolatesView({required this.rows, super.key});

  /// The rows.
  final ValueListenable<List<IsolateLoad>> rows;

  @override
  State<IsolatesView> createState() => _IsolatesViewState();
}

class _IsolatesViewState extends State<IsolatesView> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert([
          for (final load in widget.rows.value) load.toJson(),
        ]),
      ),
    );
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: DebugChip(_copied ? 'Copied' : 'Copy JSON', onTap: _copy),
        ),
        Container(height: 1, color: style.line),
        const SizedBox(height: 8),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.rows,
            builder: (context, _) => LayoutBuilder(
              builder: (context, room) => SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(
                      room.maxWidth,
                      _columns.fold(_nameWidth, (sum, c) => sum + c.width),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Cells(
                          name: 'name',
                          cells: [for (final column in _columns) column.title],
                          style: style.code.copyWith(color: style.muted),
                        ),
                        for (final load in widget.rows.value) _Load(load),
                        if (widget.rows.value.isEmpty)
                          Text(
                            'No isolates',
                            style: style.text.copyWith(color: style.muted),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// A line of the table: the name, then a cell per column.
class _Cells extends StatelessWidget {
  const _Cells({required this.name, required this.cells, required this.style});

  final String name;
  final List<String> cells;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          name,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      for (final (i, cell) in cells.indexed)
        SizedBox(
          width: _columns[i].width,
          child: Text(
            cell,
            style: style,
            maxLines: 1,
            textAlign: TextAlign.end,
          ),
        ),
    ],
  );
}

// A row: its values, its bar and its details.
class _Load extends StatelessWidget {
  const _Load(this.load);

  final IsolateLoad load;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cells(
            name: load.name,
            cells: [for (final column in _columns) column.text(load)],
            style: style.code,
          ),
          const SizedBox(height: 3),
          SizedBox(height: 3, child: IsolateBusyBar(load.busy)),
          if (load.details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                [
                  for (final MapEntry(:key, :value) in load.details.entries)
                    formatIsolateDetail(key, value),
                ].join(' · '),
                style: style.code.copyWith(color: style.muted, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}
