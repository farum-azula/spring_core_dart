import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show SpringLogLevel;
import 'package:spring_boot_starter_flutter/src/debug/theme/debug_theme_scope.dart';
import 'package:spring_boot_starter_flutter/src/theme/frame_meter_theme.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

/// Every colour and font of the debug tools: the panel, the console and
/// the frame meter over the app.
///
/// [DebugStyle.of] gives the style of the debug theme selected
/// (`spring.flutter.debug.theme`, a `DebugTheme` bean or one declared
/// under `spring.flutter.debug.themes`), or, in a build without debug
/// themes, [DebugStyle.fromApp]: the built-in look, from the app's theme.
@immutable
final class DebugStyle {
  /// A style of these values; [DebugStyle.fromApp] fills the ones a theme
  /// does not choose.
  const DebugStyle({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.number,
    required this.good,
    required this.warning,
    required this.bad,
    required this.error,
    required this.line,
    required this.levelError,
    required this.levelWarning,
    required this.levelInfo,
    required this.levelDebug,
    required this.time,
    required this.logger,
    required this.command,
    required this.argument,
    required this.title,
    required this.text,
    required this.code,
    this.meter = const FrameMeterTheme(),
    this.meterNumber,
    this.meterText,
    this.methodRead = const Color(0xFF29B8DB),
    this.methodWrite = const Color(0xFFFF9E57),
    this.graphFlash = const Color(0xFFFFE066),
    this._graphHot,
    this.graphLayers = const {},
  });

  /// The style of the debug theme selected above [context]; without
  /// debug themes in the build, [DebugStyle.fromApp].
  factory DebugStyle.of(BuildContext context) =>
      DebugThemeScope.styleOf(context) ?? DebugStyle.fromApp(context);

  /// The built-in look (the `default` debug theme), from the app's theme
  /// above [context] (a dark grey panel when there is none), with every
  /// value given here instead of its own.
  ///
  /// The colours of the logs and of the console's states are a
  /// terminal's: the palette of a dark background, or of a light one
  /// ([DebugConsoleColors]), by [background]'s luminance, so they stay
  /// readable on either. The commands are orange, and so are the methods
  /// that write in the Network tab; those that read are cyan. The fonts are the
  /// app theme's (`code` for the logs and the console), in [fontFamily]
  /// and [fontSize] when given. The frame meter keeps the app theme's
  /// `frame-meter` look but for what is given here.
  factory DebugStyle.fromApp(
    BuildContext context, {
    Color? background,
    Color? foreground,
    Color? muted,
    Color? accent,
    Color? number,
    Color? good,
    Color? warning,
    Color? bad,
    Color? error,
    Color? line,
    Color? levelError,
    Color? levelWarning,
    Color? levelInfo,
    Color? levelDebug,
    Color? time,
    Color? logger,
    Color? command,
    Color? argument,
    Color? methodRead,
    Color? methodWrite,
    Color? graphFlash,
    Color? graphHot,
    Map<String, Color> graphLayers = const {},
    String? fontFamily,
    double? fontSize,
  }) {
    final theme = SpringTheme.maybeOf(context);
    final colors = theme?.colorScheme;
    final fill =
        background ??
        (colors?.surface ?? const Color(0xFF16181D)).withValues(alpha: 1);
    final palette = fill.computeLuminance() < 0.5
        ? DebugConsoleColors.dark
        : DebugConsoleColors.light;
    final text = foreground ?? colors?.onSurface ?? const Color(0xFFE6E6E6);
    final primary = accent ?? colors?.primary ?? const Color(0xFF4FC3F7);
    final orange = command ?? palette.orange;
    final green = good ?? palette.green;
    final cyan = logger ?? palette.cyan;
    final amber = warning ?? palette.amber;
    TextStyle style(String name, double size) =>
        (theme?.textStyle(name) ?? TextStyle(fontSize: size)).copyWith(
          color: text,
          fontFamily: fontFamily,
        );
    final code = (theme?.textStyle('code') ?? const TextStyle(fontSize: 11))
        .copyWith(
          color: text,
          fontSize: fontSize ?? 11,
          fontFamily: fontFamily,
        );
    return DebugStyle(
      background: fill,
      foreground: text,
      muted: muted ?? colors?.onSurfaceVariant ?? const Color(0xFF9A9FAA),
      accent: primary,
      number: number ?? primary,
      good: green,
      warning: amber,
      bad: bad ?? palette.red,
      error: error ?? palette.red,
      line: line ?? colors?.outlineVariant ?? const Color(0xFF30343C),
      levelError: levelError ?? palette.red,
      levelWarning: levelWarning ?? palette.yellow,
      levelInfo: levelInfo ?? palette.green,
      levelDebug: levelDebug ?? palette.green,
      time: time ?? DebugConsoleColors.faint(text),
      logger: cyan,
      command: orange,
      argument: argument ?? DebugConsoleColors.faint(orange),
      title: style('titlemedium', 16),
      text: style('bodysmall', 12),
      code: code,
      meter: FrameMeterTheme(
        background: background?.withValues(alpha: 0.85),
        foreground: foreground,
        good: good,
        warning: warning,
        bad: bad,
      ),
      meterNumber: number ?? accent,
      meterText: fontFamily == null && fontSize == null ? null : code,
      methodRead: methodRead ?? palette.cyan,
      methodWrite: methodWrite ?? orange,
      graphFlash: graphFlash ?? palette.yellow,
      graphHot: graphHot ?? palette.magenta,
      graphLayers: {
        for (final MapEntry(:key, :value) in graphLayers.entries)
          key.toLowerCase(): value,
      },
    );
  }

  /// The fill of the panel and the console.
  final Color background;

  /// The text.
  final Color foreground;

  /// Secondary text: labels, hints, the echo of a command typed.
  final Color muted;

  /// What is selected or on.
  final Color accent;

  /// A number of the console's header and the frame meter's rate.
  final Color number;

  /// A state that is fine (a header segment, a load).
  final Color good;

  /// A warning.
  final Color warning;

  /// A state that is wrong.
  final Color bad;

  /// What a command reports as gone wrong.
  final Color error;

  /// Lines between rows, borders.
  final Color line;

  /// The level of an error record.
  final Color levelError;

  /// The level of a warning record.
  final Color levelWarning;

  /// The level of an info record.
  final Color levelInfo;

  /// The level of a debug or trace record.
  final Color levelDebug;

  /// The time of a record, and the `:` after its logger.
  final Color time;

  /// The logger of a record.
  final Color logger;

  /// A command's word (in `help`).
  final Color command;

  /// How a command's arguments are written (in `help`).
  final Color argument;

  /// Titles.
  final TextStyle title;

  /// Text.
  final TextStyle text;

  /// Logs, keys and values, the console.
  final TextStyle code;

  /// What the frame meter takes from this style; a `null` value is the
  /// app theme's `frame-meter` look.
  final FrameMeterTheme meter;

  /// The frame meter's rate; `null`: the app theme's primary colour.
  final Color? meterNumber;

  /// The frame meter's text; `null`: the app theme's.
  final TextStyle? meterText;

  /// A method that reads, in the Network tab: `GET`, `HEAD`, `OPTIONS`,
  /// `TRACE`.
  final Color methodRead;

  /// A method that writes, in the Network tab: `POST`, `PUT`, `PATCH`,
  /// `DELETE`.
  final Color methodWrite;

  /// What lights a node of the application graph that just changed or
  /// ran: its border, its glow, at most a quarter of its fill, and the
  /// pulse along its edges (`graph-flash`).
  final Color graphFlash;

  final Color? _graphHot;

  /// The outline of a hot branch of the application graph, the nodes that
  /// rebuild often and the links between them (`graph-hot`); a terminal's
  /// magenta by default, a hue no built-in layer has (the signals are
  /// orange, the flash yellow, warnings amber), so a hot plate reads apart
  /// from a signal whatever its layer.
  Color get graphHot =>
      _graphHot ??
      (background.computeLuminance() < 0.5
              ? DebugConsoleColors.dark
              : DebugConsoleColors.light)
          .magenta;

  /// The colours of the application graph's layers by layer id, lower
  /// case: those a theme sets (`graph-<layer id>` of a declared theme,
  /// `graph-beans` as well as a layer of the app's).
  final Map<String, Color> graphLayers;

  /// The colour of the nodes of the graph layer [id]: [graphLayers]' for
  /// it, else [orElse] (a layer's own default, as the beans layer's
  /// [good] green), else a colour of [graphPalette] that [id] picks, the
  /// same for an id in every run.
  ///
  /// ```dart
  /// @override
  /// Color colorOf(DebugStyle style) =>
  ///     style.graphLayer(id, orElse: style.good);
  /// ```
  Color graphLayer(String id, {Color? orElse}) =>
      graphLayers[id] ??
      graphLayers[id.toLowerCase()] ??
      orElse ??
      graphPalette[_stableHash(id) % graphPalette.length];

  /// The colours a layer of the app gets when the theme sets none for it:
  /// apart from the built-in layers' green, cyan blue and orange and the
  /// hot magenta, for this style's background, dark or light.
  List<Color> get graphPalette => background.computeLuminance() < 0.5
      ? const [
          Color(0xFFA48CF2),
          Color(0xFFC3E06A),
          Color(0xFFC8A27A),
          Color(0xFF9FB0C8),
          Color(0xFFE88A9A),
          Color(0xFF8C9EFF),
        ]
      : const [
          Color(0xFF6A4FC2),
          Color(0xFF7A9A1E),
          Color(0xFF8A6A3E),
          Color(0xFF5A6A82),
          Color(0xFFB5475C),
          Color(0xFF3D5AFE),
        ];

  // A hash of [text] that is the same in every run (String.hashCode is
  // not promised to be).
  static int _stableHash(String text) {
    var hash = 0;
    for (final unit in text.codeUnits) {
      hash = (hash * 31 + unit) & 0x3FFFFFFF;
    }
    return hash;
  }

  /// The colour of the level [level], as the console's `%clr(%5p)`.
  Color level(SpringLogLevel level) => switch (level) {
    SpringLogLevel.error || SpringLogLevel.off => levelError,
    SpringLogLevel.warning => levelWarning,
    SpringLogLevel.info => levelInfo,
    _ => levelDebug,
  };
}

/// The ANSI colours the framework's console gives a log line (Spring
/// Boot's default pattern, `LogPattern.springBootDefault`, and
/// `printLogHandler`), as Flutter colours, on a dark background and on a
/// light one: the time and the `:` after the logger faint, the level
/// green, yellow for a warning, red for an error, the logger cyan. The
/// built-in debug theme ([DebugStyle.fromApp]) takes the palette of its
/// background's luminance, with an amber for warnings and an orange for
/// the commands.
@immutable
final class DebugConsoleColors {
  /// A palette of these colours.
  const DebugConsoleColors({
    required this.red,
    required this.green,
    required this.yellow,
    required this.cyan,
    required this.amber,
    required this.orange,
    this.magenta = const Color(0xFFD670D6),
  });

  /// A terminal's colours on a dark background.
  static const dark = DebugConsoleColors(
    red: Color(0xFFF14C4C),
    green: Color(0xFF23D18B),
    yellow: Color(0xFFF5F543),
    cyan: Color(0xFF29B8DB),
    amber: Color(0xFFFFB020),
    orange: Color(0xFFFF9E57),
    magenta: Color(0xFFD670D6),
  );

  /// A terminal's colours on a light background.
  static const light = DebugConsoleColors(
    red: Color(0xFFCD3131),
    green: Color(0xFF00BC00),
    yellow: Color(0xFF949800),
    cyan: Color(0xFF0598BC),
    amber: Color(0xFFB26A00),
    orange: Color(0xFFC25400),
    magenta: Color(0xFFBC05BC),
  );

  /// ANSI 31: an error's level.
  final Color red;

  /// ANSI 32: the level of info, debug and trace.
  final Color green;

  /// ANSI 33: a warning's level.
  final Color yellow;

  /// ANSI 36: the logger.
  final Color cyan;

  /// A warning state of the console's header.
  final Color amber;

  /// The commands of the console.
  final Color orange;

  /// ANSI 35: the hot branches of the application graph.
  final Color magenta;

  /// ANSI 2 (faint) of [color]: the time and the `:`.
  static Color faint(Color color) => color.withValues(alpha: color.a * 0.6);
}

/// A tappable label of the panel: a tab, a filter, a switch.
class DebugChip extends StatelessWidget {
  /// [label], [selected] or not, calling [onTap].
  const DebugChip(
    this.label, {
    required this.onTap,
    this.selected = false,
    super.key,
  });

  /// The label.
  final String label;

  /// Whether it is selected.
  final bool selected;

  /// Called when tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? style.accent.withValues(alpha: 0.18) : null,
          border: Border.all(color: selected ? style.accent : style.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: style.text.copyWith(
            color: selected ? style.accent : style.foreground,
          ),
        ),
      ),
    );
  }
}

/// A one-line filter of a section's rows.
class DebugFilter extends StatefulWidget {
  /// A filter calling [onChanged] with its text, starting with [initial]
  /// (what was typed before the panel was closed).
  const DebugFilter({required this.onChanged, this.initial = '', super.key});

  /// Called with the text.
  final ValueChanged<String> onChanged;

  /// The text it starts with.
  final String initial;

  @override
  State<DebugFilter> createState() => _DebugFilterState();
}

class _DebugFilterState extends State<DebugFilter> {
  late final _controller = TextEditingController(text: widget.initial);
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: style.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.text.isEmpty
                ? Text('Filter', style: style.text.copyWith(color: style.muted))
                : const SizedBox.shrink(),
          ),
          EditableText(
            controller: _controller,
            focusNode: _focus,
            style: style.text,
            cursorColor: style.accent,
            backgroundCursorColor: style.muted,
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}
