import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/theme/debug_theme.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// A debug theme declared in the configuration,
/// `spring.flutter.debug.themes.<name>.*`: the colours and the font it
/// sets, the rest as the built-in theme makes them ([DebugStyle.fromApp]).
final class ConfiguredDebugTheme implements DebugTheme {
  /// The theme [name] of these values.
  const ConfiguredDebugTheme(
    this.name, {
    this.background,
    this.text,
    this.dim,
    this.accent,
    this.number,
    this.good,
    this.warning,
    this.bad,
    this.error,
    this.line,
    this.levelError,
    this.levelWarning,
    this.levelInfo,
    this.levelDebug,
    this.time,
    this.logger,
    this.command,
    this.argument,
    this.methodRead,
    this.methodWrite,
    this.graphFlash,
    this.graphHot,
    this.graphLayers = const {},
    this.fontFamily,
    this.fontSize,
  });

  /// The prefix of the declared themes.
  static const prefix = 'spring.flutter.debug.themes';

  /// The keys of a declared theme, as written.
  static const keys = [
    'background',
    'text',
    'dim',
    'accent',
    'number',
    'good',
    'warning',
    'bad',
    'error',
    'line',
    'level-error',
    'level-warning',
    'level-info',
    'level-debug',
    'time',
    'logger',
    'command',
    'argument',
    'method-read',
    'method-write',
    'graph-flash',
    'graph-hot',
    'font-family',
    'font-size',
  ];

  /// A key of a declared theme that colours the graph layer of the id
  /// after it, `graph-routes`: any layer of the app's.
  static final RegExp graphLayerKey = RegExp(
    '^graph[-_](.+)\$',
    caseSensitive: false,
  );

  /// The themes declared under [prefix] of [environment], in the order of
  /// their names; fails the start naming every key no theme has and every
  /// value that is not a colour or a size.
  static List<ConfiguredDebugTheme> declaredIn(
    ConfigurableEnvironment environment,
    Map<String, FlutterDebugThemeProperties> themes,
  ) {
    final errors = <String>[];
    final known = {for (final key in keys) _canonical(key)};
    final written = Binder.get(environment)
        .bind(prefix, const MapType(ClassType<String>(), ClassType<String>()))
        .orElse(const <String, String>{});
    // The colours of the app's own graph layers, by theme and layer id.
    final layers = <String, Map<String, String>>{};
    for (final MapEntry(:key, :value) in written.entries) {
      final dot = key.indexOf('.');
      final own = dot < 0 ? '' : key.substring(dot + 1);
      if (dot >= 0 && known.contains(_canonical(own))) {
        continue;
      }
      if (graphLayerKey.firstMatch(own) case final match?) {
        (layers[key.substring(0, dot)] ??= {})[match.group(1)!.toLowerCase()] =
            value;
        continue;
      }
      errors.add(
        '$prefix.$key: not a key of a debug theme; the keys are '
        '${keys.join(', ')}, graph-<layer id>',
      );
    }
    final declared = [
      for (final MapEntry(key: name, value: values) in themes.entries)
        _read(name, values, layers[name] ?? const {}, errors),
    ];
    if (errors.isNotEmpty) {
      throw ConfigurationPropertiesBindException(
        'spring.flutter.debug',
        'debugThemes',
        errors,
      );
    }
    return declared;
  }

  static String _canonical(String key) =>
      key.toLowerCase().replaceAll(RegExp('[-_]'), '');

  static ConfiguredDebugTheme _read(
    String name,
    FlutterDebugThemeProperties values,
    Map<String, String> layers,
    List<String> errors,
  ) {
    Color? color(String key, String? value) {
      if (value == null) {
        return null;
      }
      final color = ThemeValues.color(value);
      if (color == null) {
        errors.add(
          "$prefix.$name.$key: '$value' is not a colour (#RRGGBB, "
          '#AARRGGBB or a Colors name)',
        );
      }
      return color;
    }

    final size = values.fontSize;
    if (size != null && !(size > 0)) {
      errors.add('$prefix.$name.font-size: must be over 0 (was $size)');
    }
    return ConfiguredDebugTheme(
      name,
      background: color('background', values.background),
      text: color('text', values.text),
      dim: color('dim', values.dim),
      accent: color('accent', values.accent),
      number: color('number', values.number),
      good: color('good', values.good),
      warning: color('warning', values.warning),
      bad: color('bad', values.bad),
      error: color('error', values.error),
      line: color('line', values.line),
      levelError: color('level-error', values.levelError),
      levelWarning: color('level-warning', values.levelWarning),
      levelInfo: color('level-info', values.levelInfo),
      levelDebug: color('level-debug', values.levelDebug),
      time: color('time', values.time),
      logger: color('logger', values.logger),
      command: color('command', values.command),
      argument: color('argument', values.argument),
      methodRead: color('method-read', values.methodRead),
      methodWrite: color('method-write', values.methodWrite),
      graphFlash: color('graph-flash', values.graphFlash),
      graphHot: color('graph-hot', values.graphHot),
      graphLayers: {
        for (final MapEntry(key: layer, :value) in layers.entries)
          layer: ?color('graph-$layer', value),
      },
      fontFamily: values.fontFamily,
      fontSize: size != null && size > 0 ? size : null,
    );
  }

  @override
  final String name;

  /// The fill of the panel and the console.
  final Color? background;

  /// The text.
  final Color? text;

  /// Secondary text.
  final Color? dim;

  /// What is selected or on.
  final Color? accent;

  /// Numbers.
  final Color? number;

  /// A state that is fine.
  final Color? good;

  /// A warning.
  final Color? warning;

  /// A state that is wrong.
  final Color? bad;

  /// A command's error.
  final Color? error;

  /// Lines and borders.
  final Color? line;

  /// An error record's level.
  final Color? levelError;

  /// A warning record's level.
  final Color? levelWarning;

  /// An info record's level.
  final Color? levelInfo;

  /// A debug or trace record's level.
  final Color? levelDebug;

  /// A record's time.
  final Color? time;

  /// A record's logger.
  final Color? logger;

  /// A command's word.
  final Color? command;

  /// A command's arguments.
  final Color? argument;

  /// A method that reads, in the Network tab.
  final Color? methodRead;

  /// A method that writes, in the Network tab.
  final Color? methodWrite;

  /// The flash of a node of the application graph that changed or ran.
  final Color? graphFlash;

  /// The outline of a hot branch of the graph.
  final Color? graphHot;

  /// The nodes of the graph's layers, by layer id (`graph-<layer id>`:
  /// `graph-beans`, `graph-widgets`, `graph-signals` and a layer of the
  /// app's).
  final Map<String, Color> graphLayers;

  /// The font family of every debug tool's text.
  final String? fontFamily;

  /// The size of the logs and the console's text.
  final double? fontSize;

  @override
  DebugStyle styleOf(BuildContext context) => DebugStyle.fromApp(
    context,
    background: background,
    foreground: text,
    muted: dim,
    accent: accent,
    number: number,
    good: good,
    warning: warning,
    bad: bad,
    error: error,
    line: line,
    levelError: levelError,
    levelWarning: levelWarning,
    levelInfo: levelInfo,
    levelDebug: levelDebug,
    time: time,
    logger: logger,
    command: command,
    argument: argument,
    methodRead: methodRead,
    methodWrite: methodWrite,
    graphFlash: graphFlash,
    graphHot: graphHot,
    graphLayers: graphLayers,
    fontFamily: fontFamily,
    fontSize: fontSize,
  );
}
