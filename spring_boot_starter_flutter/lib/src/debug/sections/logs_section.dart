import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

/// The logs: the records of the logging system's buffer (`logBuffer`),
/// newest first, live, filtered by level and text.
final class DebugLogsSection implements DebugPanelSection, Ordered {
  /// The section of [buffer]; `null`: the app has no logging system.
  const DebugLogsSection(this.buffer);

  /// The records.
  final LogBuffer? buffer;

  @override
  String get title => 'Logs';

  @override
  int get order => 0;

  @override
  Widget build(BuildContext context) => switch (buffer) {
    final buffer? => _Logs(buffer),
    null => Text(
      'No logging system: add spring_boot_starter_logging.',
      style: DebugStyle.of(context).text,
    ),
  };
}

class _Logs extends StatefulWidget {
  const _Logs(this.buffer);

  final LogBuffer buffer;

  @override
  State<_Logs> createState() => _LogsState();
}

class _LogsState extends State<_Logs> {
  SpringLogLevel _least = SpringLogLevel.trace;
  String _filter = '';

  static const _levels = [
    ('All', SpringLogLevel.trace),
    ('Info', SpringLogLevel.info),
    ('Warning', SpringLogLevel.warning),
    ('Error', SpringLogLevel.error),
  ];

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          children: [
            for (final (label, level) in _levels)
              DebugChip(
                label,
                selected: _least == level,
                onTap: () => setState(() => _least = level),
              ),
            DebugChip('Clear', onTap: widget.buffer.clear),
          ],
        ),
        DebugFilter(onChanged: (text) => setState(() => _filter = text)),
        Expanded(
          child: StreamBuilder<void>(
            stream: widget.buffer.onChange,
            builder: (context, _) {
              final needle = _filter.toLowerCase();
              final records = [
                for (final record in widget.buffer.records.reversed)
                  if (record.level.index >= _least.index &&
                      (needle.isEmpty ||
                          record.message.toLowerCase().contains(needle) ||
                          record.loggerName.toLowerCase().contains(needle)))
                    record,
              ];
              if (records.isEmpty) {
                return Text('No records', style: style.text);
              }
              return ListView.builder(
                itemCount: records.length,
                itemBuilder: (context, i) {
                  final record = records[i];
                  final color = switch (record.level) {
                    SpringLogLevel.error => style.error,
                    SpringLogLevel.warning => style.warning,
                    SpringLogLevel.info => style.foreground,
                    _ => style.muted,
                  };
                  final time = record.time.toIso8601String().substring(11, 23);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '$time ${record.level.name.toUpperCase()} '
                      '${record.loggerName}: ${record.message}'
                      '${record.error == null ? '' : '\n${record.error}'}',
                      style: style.code.copyWith(color: color),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
