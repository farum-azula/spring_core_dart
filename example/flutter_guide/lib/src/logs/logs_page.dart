import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The Logs screen: the app's log lines from the `LogBuffer` bean (the
/// logging starter keeps the last `logging.buffer.capacity` records in
/// memory), filtered by level, the newest first. The calls to the server
/// are there too (`logging.level.feign=debug`).
class LogsPage extends SpringStatefulWidget<(LogBuffer,)> {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends SpringState<LogsPage, (LogBuffer,)> {
  var _level = SpringLogLevel.info;
  late Stream<List<SpringLogRecord>> _records;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  // The current list, then a new one after each burst of records.
  void _watch() => _records = beans.$1.watch(LogQuery(minLevel: _level));

  @override
  Widget build(BuildContext context) {
    final (buffer,) = beans;
    final theme = SpringTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.message('logs.title')),
        actions: [
          IconButton(
            onPressed: buffer.clear,
            tooltip: context.message('logs.clear'),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(theme.space('s')),
            child: SegmentedButton<SpringLogLevel>(
              segments: [
                for (final level in const [
                  SpringLogLevel.debug,
                  SpringLogLevel.info,
                  SpringLogLevel.warning,
                  SpringLogLevel.error,
                ])
                  ButtonSegment(
                    value: level,
                    label: Text(context.message('logs.${level.name}')),
                  ),
              ],
              selected: {_level},
              showSelectedIcon: false,
              onSelectionChanged: (levels) => setState(() {
                _level = levels.single;
                _watch();
              }),
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: _records,
              builder: (context, snapshot) {
                final records = (snapshot.data ?? const []).reversed.toList();
                if (records.isEmpty) {
                  return Center(child: Text(context.message('logs.empty')));
                }
                return ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return ListTile(
                      key: ValueKey(record.sequence),
                      dense: true,
                      leading: _LevelIcon(record.level),
                      title: Text(record.message),
                      subtitle: Text(
                        '${_time(record.time)} ${record.loggerName}'
                        '${record.fields.isEmpty ? '' : ' ${record.fields}'}',
                        style: theme.textStyle('code'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _time(DateTime time) => [
    time.hour,
    time.minute,
    time.second,
  ].map((part) => '$part'.padLeft(2, '0')).join(':');
}

class _LevelIcon extends StatelessWidget {
  const _LevelIcon(this.level);

  final SpringLogLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (level) {
      SpringLogLevel.error => Icon(Icons.error_outline, color: colors.error),
      SpringLogLevel.warning => Icon(
        Icons.warning_amber,
        color: colors.tertiary,
      ),
      SpringLogLevel.info => Icon(Icons.info_outline, color: colors.primary),
      _ => Icon(Icons.bug_report_outlined, color: colors.outline),
    };
  }
}
