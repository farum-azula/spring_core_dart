import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source_utils.dart';
import 'package:spring_boot_starter_data/src/log_values.dart';

/// The short switches for what the templates log (the properties
/// `spring.data.jdbc.*`; the auto-configuration reads them).
///
/// By default nothing changes: the SQL is logged at debug, the values at
/// trace, as Spring's loggers `spring.jdbc.core.JdbcTemplate` and
/// `spring.jdbc.core.StatementCreatorUtils` do.
final class JdbcLogSettings {
  /// Switches; all off and no threshold by default.
  const JdbcLogSettings({
    this.showSql = false,
    this.showParameters = false,
    this.formatSql = false,
    this.slowQueryThreshold,
  });

  /// `show-sql`: the statements are logged at info, so they show with the
  /// default level (Spring Boot's `spring.jpa.show-sql`).
  final bool showSql;

  /// `show-parameters`: the bound values are logged at info too, instead of
  /// trace; those of secret-looking names stay masked, and so do those
  /// bound without a name (a plain list given to a `JdbcTemplate`).
  final bool showParameters;

  /// `format-sql`: the SQL in the log on several lines.
  final bool formatSql;

  /// `slow-query-threshold`: a statement slower than this is logged at
  /// warn, whatever the level of the debug line; null: never.
  final Duration? slowQueryThreshold;
}

/// Writes the logs of the statements the templates run: the SQL and its
/// time at debug (logger `spring.jdbc.core.JdbcTemplate`), the values at
/// trace (`spring.jdbc.core.StatementCreatorUtils`), the slow ones at warn.
///
/// A line starts with `[datasource tx#12]` (the transaction's number, when
/// inside one), and ends with `{request=7f3a}` when the request id of the
/// web starter's `SpringLog.withFields` is set, so a slow page leads to its
/// statements. Values never go into the SQL log; they appear only in the
/// trace log, and a value whose name looks secret is masked.
final class StatementLogger {
  /// A logger for the statements of [dataSource].
  const StatementLogger(
    this.dataSource, [
    this.settings = const JdbcLogSettings(),
  ]);

  /// The data source whose name the lines show.
  final DataSource dataSource;

  /// The switches.
  final JdbcLogSettings settings;

  static const _sqlLog = SpringLog('spring.jdbc.core.JdbcTemplate');
  static const _valuesLog = SpringLog('spring.jdbc.core.StatementCreatorUtils');

  String get _label {
    final holder = DataSourceUtils.currentHolder(dataSource);
    if (holder == null) {
      return dataSource.name;
    }
    final name = holder.name;
    return '${dataSource.name} tx#${holder.id}'
        '${name == null ? '' : ' $name'}';
  }

  static String _request() {
    final request = SpringLog.currentFields['request'];
    return request == null ? '' : ' {request=$request}';
  }

  SpringLogLevel get _sqlLevel =>
      settings.showSql ? SpringLogLevel.info : SpringLogLevel.debug;

  SpringLogLevel get _valuesLevel =>
      settings.showParameters ? SpringLogLevel.info : SpringLogLevel.trace;

  /// Logs the bound [values] of a statement about to run; [names] says
  /// what each is (`:id`, a column), else they are `?1`, `?2`...
  ///
  /// The value of a name that looks secret is masked. A value without a
  /// name cannot be told from a secret: it is shown at trace (the log of
  /// development) and masked when `show-parameters` puts it at info.
  void parameters(List<Object?> values, [List<String>? names]) {
    if (values.isEmpty || !_valuesLog.isEnabled(_valuesLevel)) {
      return;
    }
    final label = _label;
    for (final (i, value) in values.indexed) {
      final named = names != null && i < names.length;
      final name = named ? names[i] : '?${i + 1}';
      final hidden =
          LogValues.looksSecret(name) || (!named && settings.showParameters);
      final shown = hidden ? LogValues.masked : LogValues.value(name, value);
      final type = hidden || value == null ? '' : ' (${value.runtimeType})';
      _valuesLog.log(_valuesLevel, '[$label]   $name = $shown$type');
    }
  }

  /// Logs a statement that ran: [sql], [elapsed], and the [rows] it gave
  /// or changed when it has a count.
  void executed(String sql, Duration elapsed, {int? rows}) {
    final threshold = settings.slowQueryThreshold;
    final slow = threshold != null && elapsed > threshold;
    final label = _label;
    if (slow) {
      _sqlLog.warning(
        '[$label] slow statement, ${elapsed.inMilliseconds} ms: '
        '${_text(sql)}${_request()}',
      );
    }
    if (_sqlLog.isEnabled(_sqlLevel)) {
      final count = rows == null ? '' : '${_rows(rows)}, ';
      _sqlLog.log(
        _sqlLevel,
        '[$label] ${_text(sql)}  ($count${elapsed.inMilliseconds} ms)'
        '${_request()}',
      );
    }
  }

  /// Logs a statement that failed after [elapsed].
  void failed(String sql, Duration elapsed, Object error) {
    if (_sqlLog.isEnabled(_sqlLevel)) {
      _sqlLog.log(
        _sqlLevel,
        '[$_label] ${_text(sql)}  (failed after ${elapsed.inMilliseconds} '
        'ms: ${error.runtimeType})${_request()}',
      );
    }
  }

  static String _rows(int rows) => rows == 1 ? '1 row' : '$rows rows';

  String _text(String sql) => settings.formatSql ? formatSql(sql) : sql.trim();

  static final _breaks = RegExp(
    r'\s+(from|where|group by|order by|having|limit|offset|union|values|set|'
    r'(?:inner |left |right |full |cross )?join|returning)\b',
    caseSensitive: false,
  );

  /// [sql] on several lines: a line for each main clause.
  static String formatSql(String sql) {
    final one = sql.trim().replaceAll(RegExp(r'\s+'), ' ');
    return '\n  ${one.replaceAllMapped(_breaks, (m) => '\n  ${m[1]}')}';
  }
}
