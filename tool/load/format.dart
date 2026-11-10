// Small helpers of the reports of tool/load.dart: reading the maps of
// report.json and writing the cells of a Markdown table.

/// A JSON object of report.json.
typedef Json = Map<String, Object?>;

/// A latency of report.json, kept there in milliseconds.
Duration milliseconds(num value) =>
    Duration(microseconds: (value * 1000).round());

/// [value] as a JSON object; empty when it is none.
Json jsonMap(Object? value) => (value as Map?)?.cast<String, Object?>() ?? {};

/// [value] as a list of JSON objects; empty when it is none.
List<Json> jsonList(Object? value) => [
  for (final item in (value as List?) ?? const <Object?>[]) jsonMap(item),
];

/// A cell's text with the characters that end a table cell escaped.
String cell(String text) => text.replaceAll('|', r'\|');

/// Bytes as whole megabytes.
String megabytes(Object? bytes, {String unit = ' MB'}) =>
    bytes is num ? '${(bytes / (1024 * 1024)).round()}$unit' : '-';

/// A share from 0 to 1 as a percentage.
String percent(Object? share) => switch (share) {
  final num value when value == 0 => '0 %',
  final num value => '${plain(value * 100)} %',
  _ => '-',
};

/// [value] over [base], as `1.88×`.
String ratio(num? value, num? base) =>
    value == null || base == null || base == 0
    ? '-'
    : '${(value / base).toStringAsFixed(2)}×';

/// A number of a table: whole from 100 up, else with up to two decimals.
String number(Object? value) => value is num ? plain(value) : '-';

/// A number without needless decimals: `1500`, `12.3`, `0.42`.
String plain(num value) {
  if (value == value.roundToDouble() || value.abs() >= 100) {
    return '${value.round()}';
  }
  final text = value.toStringAsFixed(value.abs() >= 10 ? 1 : 2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
