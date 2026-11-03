import 'package:spring_core_dart_generator/src/dart_names.dart';
import 'package:spring_core_dart_generator/src/did_you_mean.dart';
import 'package:spring_core_dart_generator/src/theme_references.dart';

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
/// with `colors`, `spacing`, `typography`, `tokens`, `styles`, `motion`,
/// `animations` and `background`, and `AppThemes` with the theme names.
///
/// The keys are those the application declares, in any theme (the union of
/// the base properties and every `themes.<name>.*`, whatever profile or
/// file they are in); the values are read at run time through the active
/// theme, so the generated code fixes the keys, not the values. To give a
/// token or a style property its type the references of each theme
/// (`$colors.primary`, `$neon.yellow`, color objects) are resolved at build
/// time, after `extends` (see [ThemeScope]).
///
/// ```yaml
/// spring.flutter.theme:
///   colors: { surface-container-low: grey.shade100 }
///   spacing: { s: 8, m: 16 }
///   typography: { code: { size: 13 } }
///   tokens:
///     brand: { accent: '#FF6B00' }
///     modal: { border: { width: 1, colors: [$brand.accent, white] } }
///   styles:
///     neon-chip:
///       padding: [12, 6]
///       fill:
///         default: transparent
///         selected: { color: $brand.accent, alpha: 12% }
///   motion: { durations: { fast: 120ms }, curves: { out: ease-out } }
///   themes: { ocean: { seed-color: teal } }
/// ```
///
/// ```dart
/// // Output
/// context.theme.colors.surfaceContainerLow; // Color
/// context.theme.spacing.m; // double
/// context.theme.typography.code; // TextStyle
/// context.theme.tokens.brand.accent; // Color
/// context.theme.tokens.modal.border.colors; // List<Color>
/// context.theme.styles.neonChip; // AppStyleNeonChip, a ThemeStyle
/// context.theme.motion.fast; // Duration
/// context.theme.motion.curves.out; // Curve
/// AppThemes.ocean; // 'ocean'
/// ```
final class TypedThemeKeys {
  TypedThemeKeys._(this._diagnostics);

  final KeysDiagnostics _diagnostics;

  /// The prefix of the properties read.
  static const String prefix = ThemeSet.prefix;

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

  // The states of a component, canonical.
  static const _states = {
    'default', 'hovered', 'focused', 'pressed', 'dragged', 'selected', //
    'scrolledunder', 'error', 'disabled',
  };

  final _colors = <String, String>{}; // canonical -> spelling
  final _spacing = <String, String>{};
  final _typography = <String, String>{};
  final _durations = <String, String>{};
  final _curves = <String, String>{};
  final _animations = <String, String>{};
  final _tokens = _Group();

  // Every class the file declares: the fixed ones, then each token group
  // and style as it is written.
  final _classNames = <String>{
    'AppTheme', 'AppThemes', 'AppThemeColors', 'AppThemeSpacing', //
    'AppThemeTypography', 'AppThemeTokens', 'AppThemeStyles', //
    'AppThemeMotion', 'AppThemeMotionCurves', 'AppThemeAnimations',
  };

  // Names the generated code uses from Flutter and the starter, which no
  // generated class may take (the `AppTheme` / `AppStyle` prefix keeps the
  // names apart already; this is the second guard).
  static const _reservedClasses = {
    'TextStyle', 'ButtonStyle', 'StateStyle', 'ThemeStyle', 'StyleValues', //
    'ThemeKeyReader', 'ThemeImage', 'ThemeBackgroundData', 'AnimationSpec', //
    'Color', 'Colors', 'Duration', 'Curve', 'Curves', 'EdgeInsets', //
    'BuildContext', 'ThemeData', 'ColorScheme', 'TextTheme', 'Widget', //
    'SpringTheme', 'SpringThemeData', 'List', 'String', 'Object',
  };

  // Takes [name] for a new class; reports and returns false when it is
  // reserved or another key already has it.
  bool _claim(String name, String path, String other) {
    if (_reservedClasses.contains(name) || !_classNames.add(name)) {
      _diagnostics.errors.add(
        '$path and $other both become the class $name: rename one.',
      );
      return false;
    }
    return true;
  }

  final _styles = <String, _Style>{};
  var _background = false;

  /// Canonical form of a theme key: lower case, no `-` or `_`, as the
  /// runtime compares them.
  static String canonical(String name) => canonicalName(name);

  /// Reads the keys of [properties]; returns the Dart code of the theme
  /// classes (`AppTheme`, `AppThemes` and the classes of the groups), or
  /// `null` when the application declares no `spring.flutter.theme.*`
  /// property or a problem was found. Problems go to [diagnostics].
  static String? generate(
    Iterable<ConfigProperty> properties,
    KeysDiagnostics diagnostics,
  ) {
    final set = ThemeSet.read(properties, diagnostics);
    if (set == null) {
      return null;
    }
    final before = diagnostics.errors.length;
    final keys = TypedThemeKeys._(diagnostics);
    for (final name in set.names) {
      final scope = set.scope(name)..checkAll();
      keys._collect(scope);
    }
    if (diagnostics.errors.length != before) {
      return null;
    }
    final code = keys._emit(set.names);
    return diagnostics.errors.length == before ? code : null;
  }

  void _collect(ThemeScope scope) {
    for (final entry in scope.entries.values) {
      final segments = entry.segments;
      if (segments.length < 2) {
        continue;
      }
      switch (canonical(segments.first)) {
        case 'colors':
          _colors.putIfAbsent(canonical(segments[1]), () => segments[1]);
        case 'spacing':
          _spacing.putIfAbsent(canonical(segments[1]), () => segments[1]);
        case 'typography':
          if (segments.length >= 3 &&
              _textStyles.contains(canonical(segments[1]))) {
            _typography.putIfAbsent(canonical(segments[1]), () => segments[1]);
          }
        case 'motion':
          _collectMotion(segments);
        case 'animations':
          if (segments.length >= 3) {
            _animations.putIfAbsent(canonical(segments[1]), () => segments[1]);
          }
        case 'background':
          _background = true;
      }
    }
    if (scope.node(const ['tokens']) case final tokens?) {
      _collectTokens(scope, tokens, _tokens);
    }
    if (scope.node(const ['styles']) case final styles?) {
      _collectStyles(scope, styles);
    }
  }

  // `motion.durations.<n>` and `motion.curves.<n>`.
  void _collectMotion(List<String> segments) {
    final group = canonical(segments[1]);
    if (group == 'durations' && segments.length >= 3) {
      _durations.putIfAbsent(canonical(segments[2]), () => segments[2]);
    } else if (group == 'curves' && segments.length >= 3) {
      _curves.putIfAbsent(canonical(segments[2]), () => segments[2]);
    }
  }

  // The first property below [node], for error messages.
  static String _originOf(ThemeNode node) {
    if (node.entry case final entry?) {
      return entry.origin;
    }
    for (final child in node.children.values) {
      return _originOf(child);
    }
    return '?';
  }

  void _collectTokens(ThemeScope scope, ThemeNode node, _Group group) {
    for (final MapEntry(key: canon, value: child) in node.children.entries) {
      final kind = scope.nodeKind(child, image: true);
      final target = group.children.putIfAbsent(
        canon,
        () => _Child(child.spelling),
      );
      if (kind == null) {
        _collectTokens(scope, child, target.group ??= _Group());
      } else {
        target.kinds.putIfAbsent(kind, () => []).add(_originOf(child));
      }
    }
  }

  void _collectStyles(ThemeScope scope, ThemeNode styles) {
    for (final MapEntry(key: canon, value: style) in styles.children.entries) {
      final target = _styles.putIfAbsent(canon, () => _Style(style.spelling));
      for (final MapEntry(key: propCanon, value: prop)
          in style.children.entries) {
        if (propCanon == 'transition') {
          continue;
        }
        final into = target.props.putIfAbsent(
          propCanon,
          () => _Child(prop.spelling),
        );
        final kind = scope.nodeKind(prop, insets: true);
        if (kind != null) {
          into.kinds.putIfAbsent(kind, () => []).add(_originOf(prop));
          continue;
        }
        // A map of states.
        for (final MapEntry(key: stateCanon, value: state)
            in prop.children.entries) {
          if (!_states.contains(stateCanon)) {
            final hint = closestName(stateCanon, _states);
            // An error, as the runtime throws for it.
            final error =
                '${_originOf(state)}: "${state.spelling}" is no state of a '
                'component${hint == null ? '' : ' (did you mean "$hint"?)'}.';
            if (!_diagnostics.errors.contains(error)) {
              _diagnostics.errors.add(error);
            }
          }
          final stateKind = scope.nodeKind(state, insets: true);
          if (stateKind == null) {
            _diagnostics.errors.add(
              '${_originOf(state)}: a style property is a value or a map of '
              'states to values, not a map in a map.',
            );
          } else {
            into.kinds.putIfAbsent(stateKind, () => []).add(_originOf(state));
          }
        }
      }
    }
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

  // The one kind of [child], or null (reported) when the themes differ.
  ValueKind? _single(String where, _Child child) {
    if (child.kinds.length == 1) {
      return child.kinds.keys.single;
    }
    final kinds = [
      for (final MapEntry(:key, :value) in child.kinds.entries)
        '${key.label} in ${value.join(', ')}',
    ].join('; ');
    _diagnostics.errors.add(
      '$where has values of different types: $kinds. Use one type in every '
      'theme.',
    );
    return null;
  }

  static String _read(ValueKind kind) => switch (kind) {
    ValueKind.color => 'tokenColor',
    ValueKind.number => 'tokenNumber',
    ValueKind.duration => 'tokenDuration',
    ValueKind.text => 'token',
    ValueKind.colors => 'tokenColors',
    ValueKind.numbers => 'tokenNumbers',
    ValueKind.texts => 'tokenTexts',
    ValueKind.image => 'tokenImage',
    ValueKind.insets => throw StateError('insets are no token'),
  };

  String _emit(List<String> themeNames) {
    final out = StringBuffer();
    final sections = <(String getter, String className)>[];

    void flat(
      String getter,
      String className,
      Map<String, String> spellings,
      String type,
      String read,
    ) {
      final names = _names(getter, spellings);
      if (names.isEmpty) {
        return;
      }
      sections.add((getter, className));
      out
        ..writeln('/// `$getter.*` of the active theme.')
        ..writeln('final class $className {')
        ..writeln('  const $className._(this._values);')
        ..writeln('  final ThemeKeyReader _values;');
      for (final (dart, spelling) in names) {
        out
          ..writeln('  /// `$getter.$spelling`')
          ..writeln(
            '  $type get $dart => '
            '_values.$read(${DartNames.literal(spelling)});',
          );
      }
      out.writeln('}\n');
    }

    flat('colors', 'AppThemeColors', _colors, 'Color', 'color');
    flat('spacing', 'AppThemeSpacing', _spacing, 'double', 'spacing');
    flat(
      'typography',
      'AppThemeTypography',
      _typography,
      'TextStyle',
      'textStyle',
    );
    _emitTokens(out, sections);
    _emitStyles(out, sections);
    _emitMotion(out, sections);
    flat(
      'animations',
      'AppThemeAnimations',
      _animations,
      'AnimationSpec',
      'animation',
    );
    final theme = StringBuffer()
      ..writeln('/// The values `spring.flutter.theme.*` declares, of the')
      ..writeln('/// active Spring theme: `context.theme`.')
      ..writeln('final class AppTheme {')
      ..writeln('  const AppTheme._(this._values);')
      ..writeln('  final ThemeKeyReader _values;');
    for (final (getter, className) in sections) {
      theme.writeln('  $className get $getter => $className._(_values);');
    }
    if (_background) {
      theme
        ..writeln(
          '  /// The `background` of the active theme; null in a theme without one.',
        )
        ..writeln(
          '  ThemeBackgroundData? get background => _values.theme.background;',
        );
    }
    theme.writeln('}\n');

    final themeNamesCode = StringBuffer()
      ..writeln('/// The names of the themes, for `ThemeSelection.select`.')
      ..writeln('abstract final class AppThemes {');
    final names = _names('themes', {
      for (final name in {'light', 'dark', 'system', ...themeNames})
        canonical(name): name,
    });
    for (final (dart, spelling) in names) {
      themeNamesCode
        ..writeln('  /// The theme `$spelling`.')
        ..writeln(
          '  static const String $dart = ${DartNames.literal(spelling)};',
        );
    }
    themeNamesCode.writeln('}');
    return '$theme$out$themeNamesCode';
  }

  void _emitTokens(StringBuffer out, List<(String, String)> sections) {
    if (_tokens.children.isEmpty) {
      return;
    }
    sections.add(('tokens', 'AppThemeTokens'));
    _emitGroup(out, _tokens, 'tokens', 'AppThemeTokens');
  }

  void _emitGroup(
    StringBuffer out,
    _Group group,
    String where,
    String className,
  ) {
    final byName = {
      for (final child in group.children.values) child.spelling: child,
    };
    final names = _names(where, {
      for (final MapEntry(:key, :value) in group.children.entries)
        key: value.spelling,
    });
    final body = StringBuffer();
    out
      ..writeln('/// `$where.*` of the active theme.')
      ..writeln('final class $className {')
      ..writeln('  const $className._(this._values);')
      ..writeln('  final ThemeKeyReader _values;');
    for (final (dart, spelling) in names) {
      final child = byName[spelling]!;
      final path = '$where.$spelling';
      if (child.group case final sub? when child.kinds.isEmpty) {
        final subClass = '$className${DartNames.upperFirst(dart)}';
        if (!_claim(subClass, path, 'another token')) {
          continue;
        }
        out
          ..writeln('  /// `$path`')
          ..writeln('  $subClass get $dart => $subClass._(_values);');
        _emitGroup(body, sub, path, subClass);
        continue;
      }
      if (child.group != null) {
        _diagnostics.errors.add(
          '$path is a group of tokens in some themes and a value in others.',
        );
        continue;
      }
      final kind = _single(path, child);
      if (kind == null) {
        continue;
      }
      final reader = DartNames.literal(
        path.substring('tokens.'.length),
      );
      out
        ..writeln('  /// `$path`')
        ..writeln(
          '  ${kind.dartType} get $dart => _values.${_read(kind)}($reader);',
        );
    }
    out
      ..writeln('}\n')
      ..write(body);
  }

  void _emitStyles(StringBuffer out, List<(String, String)> sections) {
    final styles = _names('styles', {
      for (final MapEntry(:key, :value) in _styles.entries) key: value.spelling,
    });
    if (styles.isEmpty) {
      return;
    }
    final byName = {for (final s in _styles.values) s.spelling: s};
    final classes = StringBuffer();
    final list = StringBuffer()
      ..writeln('/// `styles.*` of the active theme: a `ThemeStyle` per name.')
      ..writeln('final class AppThemeStyles {')
      ..writeln('  const AppThemeStyles._(this._values);')
      ..writeln('  final ThemeKeyReader _values;');
    for (final (dart, spelling) in styles) {
      // `AppStyle<Name>`, never a bare `TextStyle` or `ButtonStyle`.
      final base = 'AppStyle${DartNames.upperFirst(dart)}';
      if (!_claim(base, 'styles.$spelling', 'another style') ||
          !_claim('${base}Values', 'styles.$spelling', 'another style')) {
        continue;
      }
      list
        ..writeln('  /// `styles.$spelling`')
        ..writeln(
          '  $base get $dart => '
          '$base._(_values.style(${DartNames.literal(spelling)}));',
        );
      classes
        ..writeln('/// `styles.$spelling`: the states and typed values.')
        ..writeln(
          'final class $base '
          'implements ThemeStyle<${base}Values> {',
        )
        ..writeln('  const $base._(this.style);')
        ..writeln('  @override')
        ..writeln('  final StateStyle style;')
        ..writeln('  @override')
        ..writeln(
          '  ${base}Values view(StyleValues values) => '
          '${base}Values._(values);',
        )
        ..writeln('}\n')
        ..writeln('/// The values of `styles.$spelling` for one state.')
        ..writeln('final class ${base}Values {')
        ..writeln('  const ${base}Values._(this._values);')
        ..writeln('  final StyleValues _values;');
      final props = byName[spelling]!.props;
      final propNames = _names('styles.$spelling', {
        for (final MapEntry(:key, :value) in props.entries) key: value.spelling,
      });
      final propBySpelling = {for (final p in props.values) p.spelling: p};
      for (final (propDart, propSpelling) in propNames) {
        final kind = _single(
          'styles.$spelling.$propSpelling',
          propBySpelling[propSpelling]!,
        );
        if (kind == null) {
          continue;
        }
        final read = switch (kind) {
          ValueKind.color => 'color',
          ValueKind.number => 'number',
          ValueKind.insets => 'insets',
          ValueKind.duration => 'duration',
          ValueKind.text => 'text',
          _ => null,
        };
        if (read == null) {
          _diagnostics.errors.add(
            'styles.$spelling.$propSpelling is a ${kind.label}: a style '
            'value is a color, number, insets, text or duration.',
          );
          continue;
        }
        classes
          ..writeln('  /// `styles.$spelling.$propSpelling`')
          ..writeln(
            '  ${kind.dartType} get $propDart => '
            '_values.$read(${DartNames.literal(propSpelling)});',
          );
      }
      classes.writeln('}\n');
    }
    list.writeln('}\n');
    sections.add(('styles', 'AppThemeStyles'));
    out
      ..write(list)
      ..write(classes);
  }

  void _emitMotion(StringBuffer out, List<(String, String)> sections) {
    if (_durations.isEmpty && _curves.isEmpty) {
      return;
    }
    final durations = _names('motion', _durations);
    if (_durations.values.any((name) => canonical(name) == 'curves')) {
      _diagnostics.errors.add(
        'motion.durations.curves clashes with motion.curves: rename the '
        'duration.',
      );
    }
    final curves = _names('motion.curves', _curves);
    sections.add(('motion', 'AppThemeMotion'));
    out
      ..writeln('/// `motion.*` of the active theme: durations by name, and')
      ..writeln('/// the curves. Durations are zero when the system asks for')
      ..writeln('/// less motion.')
      ..writeln('final class AppThemeMotion {')
      ..writeln('  const AppThemeMotion._(this._values);')
      ..writeln('  final ThemeKeyReader _values;');
    for (final (dart, spelling) in durations) {
      out
        ..writeln('  /// `motion.durations.$spelling`')
        ..writeln(
          '  Duration get $dart => '
          '_values.motionDuration(${DartNames.literal(spelling)});',
        );
    }
    if (curves.isNotEmpty) {
      out
        ..writeln('  /// `motion.curves.*`')
        ..writeln(
          '  AppThemeMotionCurves get curves => '
          'AppThemeMotionCurves._(_values);',
        );
    }
    out.writeln('}\n');
    if (curves.isNotEmpty) {
      out
        ..writeln('/// `motion.curves.*` of the active theme.')
        ..writeln('final class AppThemeMotionCurves {')
        ..writeln('  const AppThemeMotionCurves._(this._values);')
        ..writeln('  final ThemeKeyReader _values;');
      for (final (dart, spelling) in curves) {
        out
          ..writeln('  /// `motion.curves.$spelling`')
          ..writeln(
            '  Curve get $dart => '
            '_values.motionCurve(${DartNames.literal(spelling)});',
          );
      }
      out.writeln('}\n');
    }
  }
}

// A group of tokens: its children by canonical name.
final class _Group {
  final children = <String, _Child>{};
}

// A token, style property or group: the spelling, the sub group if any, and
// the kinds it has with the properties that have them.
final class _Child {
  _Child(this.spelling);

  final String spelling;
  _Group? group;
  final kinds = <ValueKind, List<String>>{};
}

final class _Style {
  _Style(this.spelling);

  final String spelling;
  final props = <String, _Child>{};
}
