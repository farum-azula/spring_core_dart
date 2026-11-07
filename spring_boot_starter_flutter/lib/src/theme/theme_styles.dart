import 'dart:ui' show Color, lerpDouble;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/widgets.dart' show WidgetState;
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean, themeStateNames, themeStatePrecedence;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// A style of an app's own widget that can be read as typed values: what
/// `ThemeStates` takes. The generated class of a `styles.<name>` is one
/// (`NeonChipStyle`, whose [view] gives typed getters); [StateStyle] is
/// the runtime one, whose values are read by name.
abstract interface class ThemeStyle<V> {
  /// The style as the runtime reads it.
  StateStyle get style;

  /// The values of one state as the type [V] reads them.
  V view(StyleValues values);
}

/// The values of a `styles.<name>` of the theme: each property is one
/// value or a value per widget state, with `transition` for animating
/// between states.
///
/// ```yaml
/// styles:
///   neon-chip:
///     padding: [12, 6]
///     fill:
///       default: transparent
///       selected: { color: $colors.primary, alpha: 12% }
///     transition: 120ms ease-out
/// ```
///
/// Read it with `ThemeKeyReader.style`; the states are those of the
/// components: disabled > error > pressed > dragged > hovered > focused >
/// selected > scrolled-under > default.
final class StateStyle implements ThemeStyle<StyleValues> {
  StateStyle._(this._properties, this.transition, this.transitionCurve);

  /// Reads `styles.<name>` of [p], checking every value; throws a
  /// [ThemePropertyException] naming the property that cannot be read.
  factory StateStyle.parse(ThemeProperties p, String name) {
    final base = 'styles.$name';
    final properties = <String, Map<WidgetState?, Object>>{};
    var transition = Duration.zero;
    Curve curve = Curves.linear;
    for (final prop in p.children(base)) {
      final path = '$base.$prop';
      if (prop == 'transition') {
        final raw = p[path] ?? '';
        // The duration may have a space before its unit (`250 ms ease`).
        final split = _transition.firstMatch(raw.trim());
        final duration = split == null ? null : ThemeValues.duration(split[1]!);
        final curveText = split?[2]?.trim() ?? '';
        final parsed = curveText.isEmpty
            ? Curves.linear
            : ThemeValues.anyCurve(curveText);
        if (duration == null || parsed == null) {
          throw ThemePropertyException(
            p.propertyName(path),
            raw,
            'a duration and a curve like 120ms ease-out '
            '(${ThemeValues.curveNames.join(', ')}, or four numbers)',
          );
        }
        transition = duration;
        curve = parsed;
        continue;
      }
      properties[prop] = _property(p, path);
    }
    return StateStyle._(properties, transition, curve);
  }

  // A duration with an optional unit, then the curve.
  static final _transition = RegExp(
    r'^((?:\d+(?:\.\d+)?|\.\d+)(?:\s*(?:ms|s|m|h|d)(?![a-z]))?)(?:\s+(.*))?$',
    caseSensitive: false,
  );

  static Map<WidgetState?, Object> _property(ThemeProperties p, String path) {
    final children = p.children(path);
    final stateKeys = children.where((child) => int.tryParse(child) == null);
    if (stateKeys.isEmpty || children.contains('color')) {
      return {null: _value(p, path)};
    }
    final result = <WidgetState?, Object>{};
    for (final key in stateKeys) {
      if (!themeStateNames.contains(key)) {
        throw ThemePropertyException(
          p.propertyName('$path.$key'),
          p['$path.$key'] ?? '',
          'a state: ${themeStateNames.join(', ')}'
          '${didYouMean(key, themeStateNames)}',
        );
      }
      result[key == 'default' ? null : _stateOf(key)] = _value(
        p,
        '$path.$key',
      );
    }
    if (!result.containsKey(null)) {
      throw ThemePropertyException(
        p.propertyName(path),
        '',
        'a default value (the value when no other state applies)',
      );
    }
    _sameType(p, path, result);
    return result;
  }

  static WidgetState _stateOf(String key) => themeStatePrecedence.firstWhere(
    (state) => ThemeValues.canonical(state.name) == key,
  );

  // Every state of a property has the same type; a number next to insets
  // is widened to insets.
  static void _sameType(
    ThemeProperties p,
    String path,
    Map<WidgetState?, Object> values,
  ) {
    final types = {for (final v in values.values) _kind(v)};
    if (types.length == 1) {
      return;
    }
    if (types.length == 2 && types.containsAll(['number', 'insets'])) {
      for (final key in values.keys.toList()) {
        if (values[key] case final double number) {
          values[key] = EdgeInsets.all(number);
        }
      }
      return;
    }
    throw ThemePropertyException(
      p.propertyName(path),
      '',
      'the same kind of value in every state, found ${types.join(' and ')}',
    );
  }

  static String _kind(Object value) => switch (value) {
    Color() => 'color',
    double() => 'number',
    EdgeInsets() => 'insets',
    Duration() => 'duration',
    _ => 'text',
  };

  // The value at [path], typed by what it looks like (the rules of
  // ThemeValues.kindOf): a number, a list of numbers (insets), a duration
  // with a unit, a color, else text.
  static Object _value(ThemeProperties p, String path) {
    final scalar = p[path];
    // A map with a `color` is a color object.
    if (scalar == null && p.children(path).contains('color')) {
      return p.colorObject(path);
    }
    final list = scalar == null ? p.list(path) : null;
    if (scalar == null && (list == null || list.isEmpty)) {
      throw ThemePropertyException(p.propertyName(path), '', 'a value');
    }
    final parts = list ?? (scalar!.contains(',') ? scalar.split(',') : null);
    if (parts != null &&
        parts.every((part) => ThemeValues.number(part) != null)) {
      final n = [for (final part in parts) ThemeValues.number(part)!];
      return switch (n.length) {
        1 => EdgeInsets.all(n[0]),
        2 => EdgeInsets.symmetric(horizontal: n[0], vertical: n[1]),
        4 => EdgeInsets.fromLTRB(n[0], n[1], n[2], n[3]),
        _ => throw _insetsError(p, path, parts),
      };
    }
    if (list != null) {
      throw _insetsError(p, path, list);
    }
    final text = scalar!;
    return switch (ThemeValues.kindOf(text)) {
      'number' => ThemeValues.number(text)!,
      'duration' => ThemeValues.duration(text)!,
      'color' => ThemeValues.color(text)!,
      _ => text,
    };
  }

  static ThemePropertyException _insetsError(
    ThemeProperties p,
    String path,
    List<String> parts,
  ) => ThemePropertyException(
    p.propertyName(path),
    parts.join(', '),
    'insets: [all], [horizontal, vertical] or [left, top, right, bottom]',
  );

  final Map<String, Map<WidgetState?, Object>> _properties;

  /// How long the values take to change when the state does; zero (no
  /// animation) when the style has no `transition`.
  final Duration transition;

  /// The curve of the change; linear unless `transition` names one.
  final Curve transitionCurve;

  /// The names of the properties of the style, in canonical form
  /// (`borderwidth` for `border-width`), without `transition`.
  Set<String> get properties => Set.unmodifiable(_properties.keys);

  @override
  StateStyle get style => this;

  @override
  StyleValues view(StyleValues values) => values;

  /// The values for a widget in [states]: of each property the one of the
  /// strongest state it has a value for (disabled > error > pressed >
  /// dragged > hovered > focused > selected > scrolled-under), else its
  /// default.
  StyleValues resolve(Set<WidgetState> states) => StyleValues._({
    for (final MapEntry(:key, :value) in _properties.entries)
      key: _pick(value, states),
  });

  static Object _pick(Map<WidgetState?, Object> byState, Set<WidgetState> on) {
    for (final state in themeStatePrecedence) {
      if (on.contains(state) && byState.containsKey(state)) {
        return byState[state]!;
      }
    }
    return byState[null]!;
  }
}

/// The values of a [StateStyle] for one state, read by property name
/// (`values.color('fill')`; `-`, `_` and case do not matter). A property
/// that is missing or of another type throws a [StateError].
final class StyleValues {
  StyleValues._(this._values);

  final Map<String, Object> _values;

  /// The color property [prop].
  Color color(String prop) => _get<Color>(prop, 'a color');

  /// The number property [prop].
  double number(String prop) => _get<double>(prop, 'a number');

  /// The insets property [prop]: a list of numbers (`[12, 6]`) or one
  /// number for all sides.
  EdgeInsets insets(String prop) => switch (_get<Object>(prop, 'insets')) {
    final EdgeInsets insets => insets,
    final double number => EdgeInsets.all(number),
    _ => _wrong(prop, 'insets'),
  };

  /// The text property [prop].
  String text(String prop) => _get<String>(prop, 'text');

  /// The duration property [prop] (`250ms`).
  Duration duration(String prop) => _get<Duration>(prop, 'a duration');

  /// The true-or-false property [prop] (`fill: false`).
  bool flag(String prop) => switch (_get<Object>(prop, 'true or false')) {
    final bool value => value,
    'true' => true,
    'false' => false,
    _ => _wrong(prop, 'true or false'),
  };

  T _get<T extends Object>(String prop, String kind) {
    final value = _values[ThemeValues.canonical(prop)];
    if (value is T) {
      return value;
    }
    if (value == null) {
      throw StateError(
        "The style has no property '$prop'; it has "
        '${_values.keys.join(', ')}.',
      );
    }
    return _wrong(prop, kind);
  }

  Never _wrong(String prop, String kind) => throw StateError(
    "The style's property '$prop' is not $kind but "
    '${StateStyle._kind(_values[ThemeValues.canonical(prop)]!)}.',
  );

  /// The values between [a] and [b] at [t] (0 is [a], 1 is [b]): colors,
  /// numbers, insets and durations are interpolated, text switches at the
  /// middle. A property only one of them has is taken as it is.
  static StyleValues lerp(StyleValues a, StyleValues b, double t) {
    final result = <String, Object>{};
    for (final key in {...a._values.keys, ...b._values.keys}) {
      final from = a._values[key];
      final to = b._values[key];
      result[key] = switch ((from, to)) {
        (null, final Object value) || (final Object value, null) => value,
        (final Color x, final Color y) => Color.lerp(x, y, t)!,
        (final double x, final double y) => lerpDouble(x, y, t)!,
        (final EdgeInsets x, final EdgeInsets y) => _nonNegative(
          EdgeInsets.lerp(x, y, t)!,
        ),
        (final Duration x, final Duration y) => Duration(
          microseconds: lerpDouble(
            x.inMicroseconds,
            y.inMicroseconds,
            t,
          )!.round(),
        ),
        (final double x, final EdgeInsets y) => _nonNegative(
          EdgeInsets.lerp(EdgeInsets.all(x), y, t)!,
        ),
        (final EdgeInsets x, final double y) => _nonNegative(
          EdgeInsets.lerp(x, EdgeInsets.all(y), t)!,
        ),
        (final Object x, final Object y) => t < 0.5 ? x : y,
        _ => throw StateError('unreachable'),
      };
    }
    return StyleValues._(result);
  }

  // A curve that overshoots (back, elastic) must not make a padding
  // negative.
  static EdgeInsets _nonNegative(EdgeInsets i) => EdgeInsets.fromLTRB(
    i.left < 0 ? 0 : i.left,
    i.top < 0 ? 0 : i.top,
    i.right < 0 ? 0 : i.right,
    i.bottom < 0 ? 0 : i.bottom,
  );

  @override
  bool operator ==(Object other) =>
      other is StyleValues && mapEquals(_values, other._values);

  @override
  int get hashCode => Object.hashAllUnordered(
    _values.entries.map((e) => Object.hash(e.key, e.value)),
  );
}
