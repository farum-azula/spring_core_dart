import 'package:dart_spring_language_server/src/schema.dart';

/// The Markdown that describes the property [key] of the schema ([prop]):
/// its type, description, default, deprecation, range and values, the
/// Flutter field it sets and where it is declared; with [value], what the
/// file sets it to.
String propertyHover(String key, SchemaProp prop, {String? value}) {
  final lines = <String>['**`$key`**'];
  void section(String text) => lines
    ..add('')
    ..add(text);
  section(
    'Type: `${typeText(prop)}`${prop.states ? ' (a value per state)' : ''}',
  );
  if (prop.description case final text?) {
    section(text);
  }
  if (prop.defaultValue != null) {
    section('Default: `${prop.defaultValue}`');
  }
  if (prop.deprecated != null && prop.deprecated != false) {
    section(
      '**Deprecated**: ${prop.deprecated == true ? '' : prop.deprecated}',
    );
  }
  final hint = prop.hint;
  if (hint != null) {
    if (hint.range case (final low, final high)?) {
      section('Range: $low to $high');
    }
    if (hint.values.isNotEmpty) {
      section('Values:');
      for (final (v, description) in hint.values) {
        lines.add('- `$v`${description == null ? '' : ': $description'}');
      }
    }
  } else if (prop.values.isNotEmpty) {
    section('Values: ${[for (final v in prop.values) '`${v.$1}`'].join(', ')}');
  }
  if (prop.flutter case final field?) {
    section('Sets: `$field`');
  }
  if (prop.source != null) {
    section(
      'Source: ${prop.className == null ? '' : '`${prop.className}` in '}'
      '`${prop.source}`${prop.line == null ? '' : ':${prop.line}'}',
    );
  }
  if (prop.fromCode) {
    section('Read by code (`@Value`, `@ConditionalOnProperty`, ...)');
  }
  return lines.join('\n');
}

/// The type of [prop] as shown: a theme choice lists its values.
String typeText(SchemaProp prop) =>
    prop.theme && prop.type == 'choice' && prop.values.isNotEmpty
    ? 'one of ${[for (final v in prop.values) v.$1].join(' | ')}'
    : prop.type;

/// The detail of a completion of [prop]: its type and default.
String propertyDetail(SchemaProp prop) => prop.defaultValue == null
    ? typeText(prop)
    : '${typeText(prop)} = ${prop.defaultValue}';
