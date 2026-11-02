import 'package:spring_core_dart_generator/src/dart_names.dart';

/// Warnings and errors found while reading the configuration for the typed
/// keys: an error fails the build and nothing is written.
final class KeysDiagnostics {
  /// The warnings, in the order found.
  final warnings = <String>[];

  /// The errors, in the order found.
  final errors = <String>[];
}

/// One property of the configuration: the file below `lib/resources/`, the
/// property name as written (YAML nesting already joined with dots) and its
/// value.
typedef ConfigProperty = ({String file, String name, String value});

/// Writes the typed accessors of `spring.flutter.theme.*`: `context.theme`
/// with `colors`, `spacing`, `typography` and `tokens`, and `AppThemes`
/// with the theme names.
///
/// The keys are those the application declares, in any theme (the union of
/// the base properties and every `themes.<name>.*`, whatever profile or
/// file they are in); the values are read at run time through the active
/// theme, so the generated code fixes the keys, not the values.
///
/// ```yaml
/// spring.flutter.theme:
///   colors: { surface-container-low: grey.shade100 }
///   spacing: { s: 8, m: 16 }
///   typography: { code: { size: 13 } }
///   tokens: { brand: { accent: '#FF6B00', hero-height: 240 } }
///   themes: { ocean: { seed-color: teal } }
/// ```
///
/// ```dart
/// // Output
/// context.theme.colors.surfaceContainerLow; // Color
/// context.theme.spacing.m; // double
/// context.theme.typography.code; // TextStyle
/// context.theme.tokens.brand.accent; // Color
/// context.theme.tokens.brand.heroHeight; // double
/// AppThemes.ocean; // 'ocean'
/// ```
final class TypedThemeKeys {
  TypedThemeKeys._(this._diagnostics);

  final KeysDiagnostics _diagnostics;

  /// The prefix of the properties read.
  static const prefix = 'spring.flutter.theme.';

  // The text styles that can be set by name (the 15 of Material's
  // TextTheme) and `code`, canonical.
  static const _textStyles = {
    'displaylarge', 'displaymedium', 'displaysmall', //
    'headlinelarge', 'headlinemedium', 'headlinesmall', //
    'titlelarge', 'titlemedium', 'titlesmall', //
    'bodylarge', 'bodymedium', 'bodysmall', //
    'labellarge', 'labelmedium', 'labelsmall', //
    'code',
  };

  static final _colorLiteral = RegExp(
    r'^(#|0[xX])([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
  );
  static final _number = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)$');

  final _colors = <String, String>{}; // canonical -> spelling
  final _spacing = <String, String>{};
  final _typography = <String, String>{};
  final _themes = <String, String>{};
  // group -> key -> token
  final _tokens = <String, ({String spelling, Map<String, _Token> keys})>{};

  /// Canonical form of a theme key: lower case, no `-` or `_`, as the
  /// runtime compares them.
  static String canonical(String name) =>
      name.toLowerCase().replaceAll('-', '').replaceAll('_', '');

  /// Reads the keys of [properties]; returns the Dart code of the theme
  /// classes (`AppTheme`, `AppThemes` and the classes of the groups), or
  /// `null` when the application declares no `spring.flutter.theme.*`
  /// property. Problems go to [diagnostics].
  static String? generate(
    Iterable<ConfigProperty> properties,
    KeysDiagnostics diagnostics,
  ) {
    final keys = TypedThemeKeys._(diagnostics);
    var any = false;
    for (final property in properties) {
      final name = property.name.replaceAllMapped(
        RegExp(r'\[(\d+)\]'),
        (m) => '.${m[1]}',
      );
      if (!name.startsWith(prefix)) {
        continue;
      }
      any = true;
      keys._add(property.name, name.substring(prefix.length), property.value);
    }
    if (!any) {
      return null;
    }
    final before = diagnostics.errors.length;
    final code = keys._emit();
    return diagnostics.errors.length == before ? code : null;
  }

  void _add(String original, String relative, String value) {
    var segments = relative.split('.');
    if (canonical(segments.first) == 'themes') {
      if (segments.length < 3) {
        return;
      }
      _themes.putIfAbsent(canonical(segments[1]), () => segments[1]);
      segments = segments.sublist(2);
    }
    if (segments.length < 2) {
      return;
    }
    final section = canonical(segments.first);
    switch (section) {
      case 'colors':
        _colors.putIfAbsent(canonical(segments[1]), () => segments[1]);
      case 'spacing':
        _spacing.putIfAbsent(canonical(segments[1]), () => segments[1]);
      case 'typography':
        if (segments.length >= 3 &&
            _textStyles.contains(canonical(segments[1]))) {
          _typography.putIfAbsent(canonical(segments[1]), () => segments[1]);
        }
      case 'tokens':
        if (segments.length != 3) {
          _diagnostics.errors.add(
            '$original: a token is tokens.<group>.<key> (two levels), as '
            'SpringThemeData.token reads it.',
          );
          return;
        }
        final group = _tokens.putIfAbsent(
          canonical(segments[1]),
          () => (spelling: segments[1], keys: {}),
        );
        group.keys
            .putIfAbsent(canonical(segments[2]), () => _Token(segments[2]))
            .types
            .putIfAbsent(_typeOf(value), () => [])
            .add(original);
    }
  }

  static _TokenType _typeOf(String value) {
    final text = value.trim();
    if (_colorLiteral.hasMatch(text)) {
      return _TokenType.color;
    }
    return _number.hasMatch(text) ? _TokenType.number : _TokenType.string;
  }

  // Dart names of [spellings] (canonical -> spelling) in sorted order;
  // reports a name that has none and two keys of one name.
  List<(String dart, String spelling)> _names(
    String where,
    Map<String, String> spellings,
  ) {
    final result = <String, String>{};
    for (final spelling in spellings.values) {
      final dart = DartNames.member(spelling);
      if (dart == null) {
        _diagnostics.errors.add(
          '$where.$spelling cannot be written as a Dart name (letters, digits, '
          '- and _ only).',
        );
      } else if (result.containsKey(dart)) {
        _diagnostics.errors.add(
          '$where.${result[dart]} and $where.$spelling both become '
          "'$dart': rename one.",
        );
      } else {
        result[dart] = spelling;
      }
    }
    return [
      for (final dart in result.keys.toList()..sort()) (dart, result[dart]!),
    ];
  }

  String _emit() {
    final out = StringBuffer();
    final sections = <(String getter, String className)>[];

    void group(
      String getter,
      String className,
      String where,
      Map<String, String> spellings,
      String Function(String dart, String spelling) member,
    ) {
      final names = _names(where, spellings);
      if (names.isEmpty) {
        return;
      }
      sections.add((getter, className));
      out
        ..writeln('/// `$where.*` of the active theme.')
        ..writeln('final class $className {')
        ..writeln('  const $className._(this._values);')
        ..writeln('  final ThemeKeyReader _values;');
      for (final (dart, spelling) in names) {
        out.writeln(member(dart, spelling));
      }
      out.writeln('}\n');
    }

    group(
      'colors',
      'AppThemeColors',
      'colors',
      _colors,
      (dart, spelling) =>
          '  /// `colors.$spelling`\n'
          '  Color get $dart => '
          '_values.color(${DartNames.literal(spelling)});',
    );
    group(
      'spacing',
      'AppThemeSpacing',
      'spacing',
      _spacing,
      (dart, spelling) =>
          '  /// `spacing.$spelling`\n'
          '  double get $dart => '
          '_values.spacing(${DartNames.literal(spelling)});',
    );
    group(
      'typography',
      'AppThemeTypography',
      'typography',
      _typography,
      (dart, spelling) =>
          '  /// `typography.$spelling`\n'
          '  TextStyle get $dart => '
          '_values.textStyle(${DartNames.literal(spelling)});',
    );
    _emitTokens(out, sections);

    final names = _themeNames();
    final theme = StringBuffer()
      ..writeln('/// The values `spring.flutter.theme.*` declares, of the')
      ..writeln('/// active Spring theme: `context.theme`.')
      ..writeln('final class AppTheme {')
      ..writeln('  const AppTheme._(this._values);')
      ..writeln('  final ThemeKeyReader _values;');
    for (final (getter, className) in sections) {
      theme.writeln('  $className get $getter => $className._(_values);');
    }
    theme.writeln('}\n');

    final themeNames = StringBuffer()
      ..writeln('/// The names of the themes, for `ThemeSelection.select`.')
      ..writeln('abstract final class AppThemes {');
    for (final (dart, spelling) in names) {
      themeNames
        ..writeln('  /// The theme `$spelling`.')
        ..writeln(
          '  static const String $dart = ${DartNames.literal(spelling)};',
        );
    }
    themeNames.writeln('}');
    return '$theme$out$themeNames';
  }

  List<(String, String)> _themeNames() {
    final all = {
      'light': 'light',
      'dark': 'dark',
      'system': 'system',
      ..._themes,
    };
    return _names('themes', all);
  }

  void _emitTokens(StringBuffer out, List<(String, String)> sections) {
    final groups = _names('tokens', {
      for (final MapEntry(:key, :value) in _tokens.entries) key: value.spelling,
    });
    if (groups.isEmpty) {
      return;
    }
    final canonicalOf = {
      for (final MapEntry(:key, :value) in _tokens.entries) value.spelling: key,
    };
    final body = StringBuffer();
    for (final (dart, spelling) in groups) {
      final entry = _tokens[canonicalOf[spelling]]!;
      final className = 'AppThemeTokens${DartNames.upperFirst(dart)}';
      final keys = _names('tokens.$spelling', {
        for (final MapEntry(:key, :value) in entry.keys.entries)
          key: value.spelling,
      });
      final byName = {
        for (final token in entry.keys.values) token.spelling: token,
      };
      body
        ..writeln('/// `tokens.$spelling.*` of the active theme.')
        ..writeln('final class $className {')
        ..writeln('  const $className._(this._values);')
        ..writeln('  final ThemeKeyReader _values;');
      for (final (keyDart, keySpelling) in keys) {
        final token = byName[keySpelling]!;
        final path = DartNames.literal('$spelling.$keySpelling');
        if (token.types.length > 1) {
          final types = [
            for (final MapEntry(:key, :value) in token.types.entries)
              '${key.name} in ${value.join(', ')}',
          ].join('; ');
          _diagnostics.errors.add(
            'tokens.$spelling.$keySpelling has values of different types: '
            '$types. Use one type (color #RRGGBB, number or text) in '
            'every theme.',
          );
          continue;
        }
        final (type, read) = switch (token.types.keys.single) {
          _TokenType.color => ('Color', 'tokenColor'),
          _TokenType.number => ('double', 'tokenNumber'),
          _TokenType.string => ('String', 'token'),
        };
        body
          ..writeln('  /// `tokens.$spelling.$keySpelling`')
          ..writeln('  $type get $keyDart => _values.$read($path);');
      }
      body.writeln('}\n');
    }
    sections.add(('tokens', 'AppThemeTokens'));
    out
      ..writeln('/// `tokens.*` of the active theme: a group per name.')
      ..writeln('final class AppThemeTokens {')
      ..writeln('  const AppThemeTokens._(this._values);')
      ..writeln('  final ThemeKeyReader _values;');
    for (final (dart, _) in groups) {
      final className = 'AppThemeTokens${DartNames.upperFirst(dart)}';
      out.writeln('  $className get $dart => $className._(_values);');
    }
    out
      ..writeln('}\n')
      ..write(body);
  }
}

enum _TokenType { color, number, string }

final class _Token {
  _Token(this.spelling);

  final String spelling;

  // Type -> the properties that have it.
  final types = <_TokenType, List<String>>{};
}
