import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:neon_ui/src/neon_chip.dart';
import 'package:neon_ui/src/neon_label.dart';
import 'package:neon_ui/src/neon_panel.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

const _loggerWidth = 40;
const _levelWidth = 5;
const _thread = 'main';
const _scrollbarThickness = 8.0;
const _followSlack = 24.0;

class NeonLogsPanel extends StatefulWidget {
  const NeonLogsPanel({
    super.key,
    required this.buffer,
    this.sourceSelector,
    this.status,
    this.processId,
    this.onClear,
    this.emptyMessage,
  });

  final LogBuffer buffer;
  final Widget? sourceSelector;
  final Widget? status;

  /// The process id to show after the level, or null (the web has none).
  final int? processId;
  final VoidCallback? onClear;
  final String? emptyMessage;

  @override
  State<NeonLogsPanel> createState() => _NeonLogsPanelState();
}

class _NeonLogsPanelState extends State<NeonLogsPanel> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  final _selection = FocusNode();
  final _widths = <SpringLogRecord, double>{};
  var _follow = true;

  @override
  void initState() {
    super.initState();
    _vertical.addListener(() {
      final position = _vertical.position;
      _follow = position.pixels >= position.maxScrollExtent - _followSlack;
    });
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buffer = widget.buffer;
    return StreamBuilder<List<SpringLogRecord>>(
      stream: buffer.watch(),
      initialData: buffer.records,
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <SpringLogRecord>[];
        if (_follow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_vertical.hasClients) {
              _vertical.jumpTo(_vertical.position.maxScrollExtent);
            }
          });
        }
        return NeonPanel(
          title: 'Logs',
          titleTrailing: widget.sourceSelector,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.status case final status?) ...[
                status,
                SizedBox(width: context.theme.spacing.s),
              ],
              NeonLabel('${records.length} records'),
              SizedBox(width: context.theme.spacing.s),
              NeonChip(
                label: 'Clear',
                selected: false,
                onPressed: widget.onClear ?? buffer.clear,
              ),
            ],
          ),
          child: records.isEmpty && widget.emptyMessage != null
              ? Center(child: NeonLabel(widget.emptyMessage!))
              : _lines(context, records),
        );
      },
    );
  }

  Widget _lines(BuildContext context, List<SpringLogRecord> records) {
    final theme = context.theme;
    final retained = records.toSet();
    _widths.removeWhere((record, _) => !retained.contains(record));
    final spans = [for (final record in records) _span(context, record)];
    final width = spans.indexed.fold<double>(0, (widest, entry) {
      final measured = _widths.putIfAbsent(
        records[entry.$1],
        () => _measure(entry.$2),
      );
      return measured > widest ? measured : widest;
    });
    final padding = theme.spacing.m;
    return LayoutBuilder(
      builder: (context, constraints) => RawScrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        thickness: _scrollbarThickness,
        thumbColor: theme.colors.outline,
        notificationPredicate: (notification) => notification.depth == 0,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width + padding * 2 > constraints.maxWidth
                ? width + padding * 2
                : constraints.maxWidth,
            height: constraints.maxHeight,
            child: RawScrollbar(
              controller: _vertical,
              thumbVisibility: true,
              thickness: _scrollbarThickness,
              thumbColor: theme.colors.outline,
              child: SelectableRegion(
                focusNode: _selection,
                selectionControls: emptyTextSelectionControls,
                child: ListView.builder(
                  controller: _vertical,
                  padding: EdgeInsets.all(padding),
                  itemCount: spans.length,
                  itemBuilder: (context, index) =>
                      Text.rich(spans[index], softWrap: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _measure(InlineSpan span) {
    final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  InlineSpan _span(BuildContext context, SpringLogRecord record) {
    final logs = context.theme.tokens.logs;
    final faint = logs.faint;
    final logger = record.loggerName.length > _loggerWidth
        ? record.loggerName.substring(record.loggerName.length - _loggerWidth)
        : record.loggerName.padRight(_loggerWidth);
    final error = record.error;
    final stack = record.stackTrace;
    return TextSpan(
      style: context.theme.typography.code.copyWith(color: logs.text),
      children: [
        TextSpan(
          text: _time(record.time),
          style: TextStyle(color: faint),
        ),
        TextSpan(
          text: ' ${_level(record.level).padLeft(_levelWidth)} ',
          style: TextStyle(color: _tone(logs, record.level)),
        ),
        if (widget.processId case final id?)
          TextSpan(
            text: '$id',
            style: TextStyle(color: logs.pid),
          ),
        TextSpan(
          text: ' --- [${_thread.padLeft(15)}] ',
          style: TextStyle(color: faint),
        ),
        TextSpan(
          text: logger,
          style: TextStyle(color: logs.logger),
        ),
        TextSpan(
          text: ' : ',
          style: TextStyle(color: faint),
        ),
        TextSpan(text: record.message),
        if (record.fields.isNotEmpty)
          TextSpan(
            text: ' ${record.fields}',
            style: TextStyle(color: faint),
          ),
        if (error != null)
          TextSpan(
            text: '\n$error',
            style: TextStyle(color: logs.error),
          ),
        if (stack != null)
          TextSpan(
            text: '\n$stack',
            style: TextStyle(color: faint),
          ),
      ],
    );
  }

  static String _level(SpringLogLevel level) => switch (level) {
    SpringLogLevel.warning => 'WARN',
    _ => level.name.toUpperCase(),
  };

  static Color _tone(AppThemeTokensLogs logs, SpringLogLevel level) =>
      switch (level) {
        SpringLogLevel.error => logs.error,
        SpringLogLevel.warning => logs.warn,
        _ => logs.info,
      };

  static String _time(DateTime time) {
    final local = time.toLocal();
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    String two(int value) => value.abs().toString().padLeft(2, '0');
    final iso = local.toIso8601String();
    final millis = iso.length >= 23 ? iso.substring(0, 23) : iso;
    return '$millis$sign${two(offset.inHours)}:${two(offset.inMinutes % 60)}';
  }
}
