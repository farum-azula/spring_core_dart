import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// The states a theme property may give a value for, by canonical name
/// (`default` is the value when no other state applies), in the order the
/// documentation lists them.
const themeStateNames = [
  'default',
  'hovered',
  'focused',
  'pressed',
  'dragged',
  'selected',
  'scrolledunder',
  'disabled',
  'error',
];

const _statesByName = <String, WidgetState>{
  'hovered': WidgetState.hovered,
  'focused': WidgetState.focused,
  'pressed': WidgetState.pressed,
  'dragged': WidgetState.dragged,
  'selected': WidgetState.selected,
  'scrolledunder': WidgetState.scrolledUnder,
  'disabled': WidgetState.disabled,
  'error': WidgetState.error,
};

/// Which state wins when a widget is in several at once, strongest
/// first: `disabled`, `error`, `pressed`, `dragged`, `hovered`,
/// `focused`, `selected`, `scrolled-under`, then `default`.
const themeStatePrecedence = <WidgetState>[
  WidgetState.disabled,
  WidgetState.error,
  WidgetState.pressed,
  WidgetState.dragged,
  WidgetState.hovered,
  WidgetState.focused,
  WidgetState.selected,
  WidgetState.scrolledUnder,
];

/// A value per widget state, as a property gives it with a map
/// (`{ default: primary, hovered: secondary, disabled: grey }`): the
/// value of the strongest state the widget is in ([themeStatePrecedence])
/// that has one, else the `default` one, else `null`, which makes the
/// component keep Flutter's own value. Internal to the starter.
@immutable
final class StateValues<T> extends WidgetStateProperty<T?> {
  /// The values by state; [fallback] is the `default`.
  StateValues(this.values, [this.fallback]);

  /// The value of each state that has one.
  final Map<WidgetState, T> values;

  /// The `default` value.
  final T? fallback;

  @override
  T? resolve(Set<WidgetState> states) {
    for (final state in themeStatePrecedence) {
      if (states.contains(state)) {
        final value = values[state];
        if (value != null) {
          return value;
        }
      }
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is StateValues<T> &&
      other.fallback == fallback &&
      other.values.length == values.length &&
      values.entries.every((e) => other.values[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    fallback,
    Object.hashAllUnordered(values.entries.map((e) => (e.key, e.value))),
  );
}

/// One property a component reads: its key in kebab case, what it holds
/// and whether it takes a value per state.
@immutable
final class ThemeProperty {
  /// A property called [name] holding a [kind].
  const ThemeProperty(this.name, this.kind, this.states, {this.alias = false});

  /// The key, in kebab case (`background-color`).
  final String name;

  /// What the value is (`color`, `text style`, `enum: a | b`).
  final String kind;

  /// Whether the value may be a map per state.
  final bool states;

  /// Whether the key is a shorter spelling of another one.
  final bool alias;
}

/// The closest of [options] to [wrong] (a typo of at most a third of the
/// name), for a "did you mean" hint; `null` when none is close.
String? closestName(String wrong, Iterable<String> options) {
  final target = ThemeValues.canonical(wrong);
  String? best;
  var bestDistance = 1 << 30;
  for (final option in options) {
    final distance = _distance(target, ThemeValues.canonical(option));
    if (distance < bestDistance) {
      bestDistance = distance;
      best = option;
    }
  }
  final limit = (target.length / 3).ceil().clamp(1, 3);
  return bestDistance <= limit ? best : null;
}

int _distance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      row[j] = [
        previous[j] + 1,
        row[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = row;
  }
  return previous[b.length];
}

/// `, did you mean 'x'?` for the closest of [options], else nothing.
String didYouMean(String wrong, Iterable<String> options) {
  final close = closestName(wrong, options);
  return close == null ? '' : " (did you mean '$close'?)";
}

/// The mouse cursors a property may name, by canonical name.
final _cursors = <String, MouseCursor>{
  for (final (name, cursor) in [
    ('basic', SystemMouseCursors.basic),
    ('click', SystemMouseCursors.click),
    ('forbidden', SystemMouseCursors.forbidden),
    ('text', SystemMouseCursors.text),
    ('grab', SystemMouseCursors.grab),
    ('grabbing', SystemMouseCursors.grabbing),
    ('move', SystemMouseCursors.move),
    ('wait', SystemMouseCursors.wait),
    ('progress', SystemMouseCursors.progress),
    ('help', SystemMouseCursors.help),
    ('precise', SystemMouseCursors.precise),
    ('none', SystemMouseCursors.none),
    ('alias', SystemMouseCursors.alias),
    ('copy', SystemMouseCursors.copy),
    ('cell', SystemMouseCursors.cell),
    ('nodrop', SystemMouseCursors.noDrop),
    ('allscroll', SystemMouseCursors.allScroll),
    ('zoomin', SystemMouseCursors.zoomIn),
    ('zoomout', SystemMouseCursors.zoomOut),
    ('verticaltext', SystemMouseCursors.verticalText),
    ('contextmenu', SystemMouseCursors.contextMenu),
    ('resizecolumn', SystemMouseCursors.resizeColumn),
    ('resizerow', SystemMouseCursors.resizeRow),
  ])
    name: cursor,
};

const _alignments = <String, Alignment>{
  'topleft': Alignment.topLeft,
  'topcenter': Alignment.topCenter,
  'topright': Alignment.topRight,
  'centerleft': Alignment.centerLeft,
  'center': Alignment.center,
  'centerright': Alignment.centerRight,
  'bottomleft': Alignment.bottomLeft,
  'bottomcenter': Alignment.bottomCenter,
  'bottomright': Alignment.bottomRight,
};

// Shorter spellings of Flutter's property names, kept from the first
// components (`background` for `backgroundColor`).
const _aliases = <String, List<String>>{
  'backgroundcolor': ['background'],
  'foregroundcolor': ['foreground'],
  'titletextstyle': ['titlestyle'],
};

/// Reads the properties of one component (`components.card.*`) by
/// Flutter's own property names in camel case (`backgroundColor` is
/// `background-color` in the files), parsing each by its type: colors,
/// shapes, border sides, insets, text styles, numbers, enums, durations,
/// cursors, and a value per state for those Flutter models as a
/// `WidgetStateProperty`. A component's mapping is its constructor call
/// written with these readers, so adding a property is one line.
///
/// The reader remembers every property it was asked for, which gives
/// the list of valid keys: [checkUnknown] fails the start for any other
/// key present, naming the valid ones. Internal to the starter.
final class ThemeReader {
  /// A reader of the properties below [root] (a canonical path such as
  /// `components.card`), whose component is called [label] in messages.
  /// [shapeToken] is the Material 3 shape token the component's `shape`
  /// follows when the theme changed it; [topShape] rounds the top
  /// corners only.
  ThemeReader({
    required this.theme,
    required this.properties,
    required this.root,
    required this.label,
    required this.namedStyle,
    this.shapeToken,
    this.topShape = false,
  }) : _prefix = '',
       _display = '',
       _entries = {},
       _containers = {};

  ThemeReader._sub(ThemeReader parent, String name)
    : theme = parent.theme,
      properties = parent.properties,
      root = parent.root,
      label = parent.label,
      namedStyle = parent.namedStyle,
      shapeToken = null,
      topShape = false,
      _prefix = '${parent._prefix}${ThemeValues.canonical(name)}.',
      _display = '${parent._display}${_kebab(name)}.',
      _entries = parent._entries,
      _containers = parent._containers;

  /// The theme the values refer to (color roles, shape tokens, ...).
  final SpringThemeData theme;

  /// The theme's resolved properties.
  final ThemeProperties properties;

  /// The canonical path of the component (`components.card`).
  final String root;

  /// The component's name in messages, in kebab case.
  final String label;

  /// The text style the theme calls [name] (`title-large`, `code`).
  final TextStyle Function(String name) namedStyle;

  /// The Material 3 shape token the `shape` property follows.
  final String? shapeToken;

  /// Whether `shape` rounds the top corners only.
  final bool topShape;

  final String _prefix;
  final String _display;
  final Map<String, ThemeProperty> _entries;
  final Set<String> _containers;

  /// The properties asked for so far, in the order of the asking
  /// (nested ones as `style.background-color`).
  List<ThemeProperty> get asked => [
    for (final entry in _entries.values)
      if (!entry.alias && entry.kind != 'group') entry,
  ];

  /// Whether the component is themed: it has properties, or follows a
  /// shape token the theme changed.
  bool get has => _prefix.isNotEmpty
      ? properties
            .children('$root.${_prefix.substring(0, _prefix.length - 1)}')
            .isNotEmpty
      : properties.children(root).isNotEmpty ||
            (shapeToken != null && theme.shapes.containsKey(shapeToken));

  // ---------------------------------------------------------------------
  // Bookkeeping
  // ---------------------------------------------------------------------

  static String _kebab(String name) => name.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '-${m[0]!.toLowerCase()}',
  );

  String _find(String name, String kind, {bool states = false}) {
    final canonical = ThemeValues.canonical(name);
    final alternatives = _aliases[canonical] ?? const <String>[];
    _entries.putIfAbsent(
      '$_prefix$canonical',
      () => ThemeProperty('$_display${_kebab(name)}', kind, states),
    );
    for (final alias in alternatives) {
      _entries.putIfAbsent(
        '$_prefix$alias',
        () => ThemeProperty('$_display$alias', kind, states, alias: true),
      );
    }
    for (final candidate in [canonical, ...alternatives]) {
      final path = '$root.$_prefix$candidate';
      if (properties[path] != null || properties.children(path).isNotEmpty) {
        return path;
      }
    }
    return '$root.$_prefix$canonical';
  }

  ThemeReader _child(String name) {
    _find(name, 'group');
    _containers.add('$_prefix${ThemeValues.canonical(name)}');
    return ThemeReader._sub(this, name);
  }

  /// Fails with a [ThemePropertyException] for a key of the component
  /// that no reader asked for, naming the valid ones.
  void checkUnknown() {
    for (final key in properties.values.keys) {
      if (!key.startsWith('$root.')) {
        continue;
      }
      final segments = key.substring(root.length + 1).split('.');
      var current = segments.first;
      var index = 0;
      while (_entries.containsKey(current) &&
          _containers.contains(current) &&
          index + 1 < segments.length) {
        index++;
        current = '$current.${segments[index]}';
      }
      if (_entries.containsKey(current)) {
        continue;
      }
      final parent = current.contains('.')
          ? current.substring(0, current.lastIndexOf('.') + 1)
          : '';
      final valid = [
        for (final MapEntry(:key, :value) in _entries.entries)
          if (!value.alias &&
              key.startsWith(parent) &&
              !key.substring(parent.length).contains('.'))
            value.name.substring(value.name.lastIndexOf('.') + 1),
      ];
      final bad = current.substring(parent.length);
      final path = '$root.${segments.take(index + 1).join('.')}';
      final where = parent.isEmpty
          ? label
          : '$label.${_entries[parent.substring(0, parent.length - 1)]!.name}';
      throw ThemePropertyException(
        properties.propertyName(path),
        properties[path] ?? '',
        'a property of $where: ${valid.join(', ')}${didYouMean(bad, valid)}',
      );
    }
  }

  // ---------------------------------------------------------------------
  // One value or a value per state
  // ---------------------------------------------------------------------

  T? _plain<T>(String name, String kind, T? Function(String path) at) =>
      at(_find(name, kind));

  // The path whose states are being read: its direct children named like
  // states are not part of its own value.
  String? _statesOf;

  Set<String> _kids(String path) {
    final children = properties.children(path);
    return path == _statesOf
        ? children.where((c) => !themeStateNames.contains(c)).toSet()
        : children;
  }

  WidgetStateProperty<T?>? _states<T extends Object>(
    String name,
    String kind,
    T? Function(String path) at,
  ) {
    final path = _find(name, kind, states: true);
    final children = properties.children(path);
    final stateKeys = children.where(themeStateNames.contains).toSet();
    final previous = _statesOf;
    _statesOf = path;
    try {
      if (stateKeys.isEmpty) {
        final value = at(path);
        return value == null ? null : WidgetStatePropertyAll<T?>(value);
      }
      for (final child in children) {
        if (!stateKeys.contains(child)) {
          throw ThemePropertyException(
            properties.propertyName('$path.$child'),
            properties['$path.$child'] ?? '',
            'a state of $name: ${themeStateNames.join(', ')} '
            '(a map per state holds states only)'
            "${didYouMean(child, themeStateNames)}",
          );
        }
      }
      final values = <WidgetState, T>{};
      // A plain value next to the states is the default.
      T? fallback = properties[path] == null ? null : at(path);
      for (final key in stateKeys) {
        _statesOf = null;
        final value = at('$path.$key');
        _statesOf = path;
        if (value == null) {
          continue;
        }
        if (key == 'default') {
          fallback = value;
        } else {
          values[_statesByName[key]!] = value;
        }
      }
      if (values.isEmpty) {
        return fallback == null ? null : WidgetStatePropertyAll<T?>(fallback);
      }
      return StateValues<T>(values, fallback);
    } finally {
      _statesOf = previous;
    }
  }

  T? _leaf<T>(String path, T? Function(String raw) parse, String expected) {
    final raw = properties[path];
    if (raw == null) {
      final children = _kids(path);
      if (children.isNotEmpty) {
        final child = children.first;
        throw ThemePropertyException(
          properties.propertyName('$path.$child'),
          properties['$path.$child'] ?? '',
          path == _statesOf
              ? 'a state of ${path.split('.').last}: '
                    '${themeStateNames.join(', ')}'
                    '${didYouMean(child, themeStateNames)}'
              : '$expected; this property takes one value'
                    '${themeStateNames.contains(child) ? ', no states' : ''}',
        );
      }
      return null;
    }
    return parse(raw) ??
        (throw ThemePropertyException(
          properties.propertyName(path),
          raw,
          expected,
        ));
  }

  /// The values of the map at [path] checked against [allowed]: a key
  /// outside it fails naming the valid ones.
  Set<String> _keys(String path, Set<String> allowed, String what) {
    final children = _kids(path);
    for (final child in children) {
      if (!allowed.contains(child)) {
        throw ThemePropertyException(
          properties.propertyName('$path.$child'),
          properties['$path.$child'] ?? '',
          'a key of $what: ${allowed.join(', ')}'
          '${didYouMean(child, allowed)}',
        );
      }
    }
    return children;
  }

  // ---------------------------------------------------------------------
  // The parsers by type, each from a full path
  // ---------------------------------------------------------------------

  Color? _colorAt(String path) {
    // An object { color, mix, alpha }; a map of states is read per state.
    final kids = _kids(path);
    if (properties[path] == null &&
        kids.any(const {'color', 'mix', 'alpha'}.contains)) {
      return properties.colorObject(path);
    }
    return _leaf(path, ThemeValues.color, ThemeProperties.colorFormats);
  }

  static double? _number(String raw) {
    final text = raw.trim().toLowerCase();
    return switch (text) {
      'infinity' || 'inf' => double.infinity,
      _ => double.tryParse(text),
    };
  }

  double? _numberAt(String path) => _leaf(path, _number, 'a number');

  double? _elevationAt(String path) => _leaf(path, (raw) {
    final level = ThemeValues.canonical(raw);
    return m3Elevations.containsKey(level)
        ? theme.elevation(level)
        : _number(raw);
  }, 'level0 … level5 or a number');

  bool? _boolAt(String path) =>
      _leaf(path, ThemeValues.boolean, 'true or false');

  EdgeInsets? _insetsAt(String path) {
    const expected =
        "'all', 'horizontal, vertical' or 'left, top, right, bottom', or a "
        'map of all, horizontal, vertical, left, top, right, bottom';
    final children = _kids(path);
    if (children.isEmpty || properties[path] != null) {
      final parsed = _leaf(path, (raw) {
        final parts = [for (final part in raw.split(',')) _number(part)];
        if (parts.contains(null) ||
            parts.isEmpty ||
            parts.length > 4 ||
            parts.length == 3) {
          return null;
        }
        return switch (parts) {
          [final all] => EdgeInsets.all(all!),
          [final h, final v] => EdgeInsets.symmetric(
            horizontal: h!,
            vertical: v!,
          ),
          [final l, final t, final r, final b] => EdgeInsets.fromLTRB(
            l!,
            t!,
            r!,
            b!,
          ),
          _ => null,
        };
      }, expected);
      if (parsed != null || children.isEmpty) {
        return parsed;
      }
    }
    _keys(path, {
      'all',
      'horizontal',
      'vertical',
      'left',
      'top',
      'right',
      'bottom',
    }, 'insets');
    double? side(String key) => _numberAt('$path.$key');
    final all = side('all');
    final horizontal = side('horizontal') ?? all;
    final vertical = side('vertical') ?? all;
    return EdgeInsets.only(
      left: side('left') ?? horizontal ?? 0,
      top: side('top') ?? vertical ?? 0,
      right: side('right') ?? horizontal ?? 0,
      bottom: side('bottom') ?? vertical ?? 0,
    );
  }

  Size? _sizeAt(String path) {
    final children = _kids(path);
    if (children.isNotEmpty) {
      _keys(path, {'width', 'height'}, 'a size');
      final width = _numberAt('$path.width');
      final height = _numberAt('$path.height');
      return Size(width ?? 0, height ?? 0);
    }
    return _leaf(path, (raw) {
      final parts = [for (final part in raw.split(',')) _number(part)];
      if (parts.contains(null) || parts.isEmpty || parts.length > 2) {
        return null;
      }
      return Size(parts.first!, parts.last!);
    }, "a size: 'width, height', one number for a square, or a map");
  }

  Offset? _offsetAt(String path) => _leaf(path, (raw) {
    final parts = [for (final part in raw.split(',')) _number(part)];
    return parts.length == 2 && !parts.contains(null)
        ? Offset(parts[0]!, parts[1]!)
        : null;
  }, "an offset: 'x, y'");

  BoxConstraints? _constraintsAt(String path) {
    if (_kids(path).isEmpty) {
      return null;
    }
    _keys(path, {
      'minwidth',
      'maxwidth',
      'minheight',
      'maxheight',
    }, 'constraints');
    return BoxConstraints(
      minWidth: _numberAt('$path.minwidth') ?? 0,
      maxWidth: _numberAt('$path.maxwidth') ?? double.infinity,
      minHeight: _numberAt('$path.minheight') ?? 0,
      maxHeight: _numberAt('$path.maxheight') ?? double.infinity,
    );
  }

  static const _shapeFormats =
      'a shape token (none, extra-small, ..., full), a radius, stadium or '
      'circle, or a map of radius, type (rounded, continuous, beveled, '
      'stadium, circle) and side';

  double _radiusValue(String path, String raw) {
    final token = ThemeValues.canonical(raw);
    if (m3ShapeScale.containsKey(token)) {
      return theme.shape(token);
    }
    return _number(raw) ??
        (throw ThemePropertyException(
          properties.propertyName(path),
          raw,
          _shapeFormats,
        ));
  }

  OutlinedBorder _border(
    double radius, {
    bool top = false,
    BorderSide side = BorderSide.none,
    String type = 'rounded',
  }) {
    if (radius.isInfinite && type == 'rounded') {
      return StadiumBorder(side: side);
    }
    final corner = Radius.circular(radius.isInfinite ? 999 : radius);
    final borderRadius = top
        ? BorderRadius.vertical(top: corner)
        : BorderRadius.all(corner);
    return switch (type) {
      'continuous' => ContinuousRectangleBorder(
        borderRadius: borderRadius,
        side: side,
      ),
      'beveled' => BeveledRectangleBorder(
        borderRadius: borderRadius,
        side: side,
      ),
      _ => RoundedRectangleBorder(borderRadius: borderRadius, side: side),
    };
  }

  OutlinedBorder? _shapeAt(String path, {bool top = false}) {
    final raw = properties[path];
    final children = _kids(path);
    if (children.isEmpty) {
      if (raw == null) {
        return null;
      }
      return switch (ThemeValues.canonical(raw)) {
        'stadium' => const StadiumBorder(),
        'circle' => const CircleBorder(),
        _ => _border(_radiusValue(path, raw), top: top),
      };
    }
    _keys(path, {'radius', 'type', 'side'}, 'a shape');
    final type =
        _leaf(
          '$path.type',
          (value) =>
              const {
                'rounded',
                'continuous',
                'beveled',
                'stadium',
                'circle',
              }.contains(ThemeValues.canonical(value))
              ? ThemeValues.canonical(value)
              : null,
          'rounded, continuous, beveled, stadium or circle',
        ) ??
        'rounded';
    final side = _sideAt('$path.side') ?? BorderSide.none;
    switch (type) {
      case 'stadium':
        return StadiumBorder(side: side);
      case 'circle':
        return CircleBorder(side: side);
    }
    final radiusRaw = properties['$path.radius'] ?? raw;
    final radius = radiusRaw == null
        ? 0.0
        : _radiusValue('$path.radius', radiusRaw);
    return _border(radius, top: top, side: side, type: type);
  }

  BorderSide? _sideAt(String path) {
    final raw = properties[path];
    final children = _kids(path);
    if (children.isEmpty) {
      if (raw == null) {
        return null;
      }
      if (ThemeValues.canonical(raw) == 'none') {
        return BorderSide.none;
      }
      final color = _colorAt(path);
      return color == null ? null : BorderSide(color: color);
    }
    _keys(path, {'color', 'width', 'style', 'strokealign'}, 'a border side');
    final style =
        _leaf(
          '$path.style',
          (value) => ThemeValues.enumValue(BorderStyle.values, value),
          'solid or none',
        ) ??
        BorderStyle.solid;
    return BorderSide(
      color: _colorAt('$path.color') ?? const Color(0xFF000000),
      width: _numberAt('$path.width') ?? 1,
      style: style,
      strokeAlign:
          _leaf(
            '$path.strokealign',
            (value) => switch (ThemeValues.canonical(value)) {
              'inside' => BorderSide.strokeAlignInside,
              'center' => BorderSide.strokeAlignCenter,
              'outside' => BorderSide.strokeAlignOutside,
              _ => _number(value),
            },
            'inside, center, outside or a number from -1 to 1',
          ) ??
          BorderSide.strokeAlignInside,
    );
  }

  static const _textFormats =
      'a text style: displayLarge … labelSmall (kebab case) or code, or a map '
      'of style, color, font-family, size, weight, height, letter-spacing, '
      'italic, decoration';

  TextStyle? _textAt(String path, {TextStyle? base}) {
    final raw = properties[path];
    final children = _kids(path);
    if (children.isEmpty) {
      return raw == null ? null : _namedText(path, raw);
    }
    _keys(path, {
      'style',
      'color',
      'fontfamily',
      'size',
      'weight',
      'height',
      'letterspacing',
      'italic',
      'decoration',
    }, 'a text style');
    final named = properties['$path.style'] ?? raw;
    final start = named == null ? base : _namedText('$path.style', named);
    final spec = SpringTextSpec(
      fontFamily: properties['$path.fontfamily'],
      size: _numberAt('$path.size'),
      weight: _leaf(
        '$path.weight',
        ThemeValues.weight,
        '100 … 900, thin, light, normal, medium, semibold, bold, black',
      ),
      height: _numberAt('$path.height'),
      letterSpacing: _numberAt('$path.letterspacing'),
    );
    final italic = _boolAt('$path.italic');
    final decoration = _leaf(
      '$path.decoration',
      (value) => switch (ThemeValues.canonical(value)) {
        'none' => TextDecoration.none,
        'underline' => TextDecoration.underline,
        'linethrough' => TextDecoration.lineThrough,
        'overline' => TextDecoration.overline,
        _ => null,
      },
      'none, underline, line-through or overline',
    );
    return spec
        .applyTo(start)
        .copyWith(
          color: _colorAt('$path.color'),
          fontStyle: italic == null
              ? null
              : (italic ? FontStyle.italic : FontStyle.normal),
          decoration: decoration,
        );
  }

  static String _textKebab(String name) => name.replaceFirstMapped(
    RegExp(r'^(display|headline|title|body|label)(large|medium|small)$'),
    (m) => '${m[1]}-${m[2]}',
  );

  TextStyle _namedText(String path, String raw) {
    final key = ThemeValues.canonical(raw);
    if (!textStyleNames.contains(key) && key != 'code') {
      throw ThemePropertyException(
        properties.propertyName(path),
        raw,
        '$_textFormats${didYouMean(raw, [...textStyleNames.map(_textKebab), 'code'])}',
      );
    }
    return namedStyle(key);
  }

  IconThemeData? _iconAt(String path) {
    final children = _kids(path);
    if (children.isEmpty) {
      final color = _colorAt(path);
      return color == null ? null : IconThemeData(color: color);
    }
    _keys(path, {
      'color',
      'size',
      'fill',
      'weight',
      'grade',
      'opticalsize',
      'opacity',
    }, 'an icon theme');
    return IconThemeData(
      color: _colorAt('$path.color'),
      size: _numberAt('$path.size'),
      fill: _numberAt('$path.fill'),
      weight: _numberAt('$path.weight'),
      grade: _numberAt('$path.grade'),
      opticalSize: _numberAt('$path.opticalsize'),
      opacity: _numberAt('$path.opacity'),
    );
  }

  MouseCursor? _cursorAt(String path) => _leaf(
    path,
    (raw) => _cursors[ThemeValues.canonical(raw)],
    'a mouse cursor: ${_cursors.keys.join(', ')}',
  );

  AlignmentGeometry? _alignmentAt(String path) => _leaf(path, (raw) {
    final named = _alignments[ThemeValues.canonical(raw)];
    if (named != null) {
      return named;
    }
    final parts = [for (final part in raw.split(',')) _number(part)];
    return parts.length == 2 && !parts.contains(null)
        ? Alignment(parts[0]!, parts[1]!)
        : null;
  }, "an alignment: ${_alignments.keys.join(', ')} or 'x, y' from -1 to 1");

  BorderRadius? _borderRadiusAt(String path) => _leaf(path, (raw) {
    final token = ThemeValues.canonical(raw);
    final radius = m3ShapeScale.containsKey(token)
        ? theme.shape(token)
        : _number(raw);
    return radius == null
        ? null
        : BorderRadius.circular(radius.isInfinite ? 999 : radius);
  }, 'a shape token or a radius');

  Radius? _radiusAt(String path) => _leaf(path, (raw) {
    final token = ThemeValues.canonical(raw);
    final radius = m3ShapeScale.containsKey(token)
        ? theme.shape(token)
        : _number(raw);
    return radius == null
        ? null
        : Radius.circular(radius.isInfinite ? 999 : radius);
  }, 'a shape token or a radius');

  Decoration? _decorationAt(String path) {
    final children = _kids(path);
    if (children.isEmpty) {
      final color = _colorAt(path);
      return color == null ? null : BoxDecoration(color: color);
    }
    _keys(path, {'color', 'radius', 'border', 'shape'}, 'a decoration');
    final side = _sideAt('$path.border');
    final circle =
        _leaf(
          '$path.shape',
          (raw) => switch (ThemeValues.canonical(raw)) {
            'rectangle' => false,
            'circle' => true,
            _ => null,
          },
          'rectangle or circle',
        ) ??
        false;
    return BoxDecoration(
      color: _colorAt('$path.color'),
      borderRadius: circle ? null : _borderRadiusAt('$path.radius'),
      border: side == null ? null : Border.fromBorderSide(side),
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
    );
  }

  // ---------------------------------------------------------------------
  // The readers components use, by Flutter's property names
  // ---------------------------------------------------------------------

  /// A color: a role, a Colors name or hex, with an optional opacity.
  Color? color(String name) => _plain(name, 'color', _colorAt);

  /// A color, or a color per state.
  WidgetStateProperty<Color?>? stateColor(String name) =>
      _states(name, 'color', _colorAt);

  /// A number.
  double? number(String name) => _plain(name, 'number', _numberAt);

  /// A number, or a number per state.
  WidgetStateProperty<double?>? stateNumber(String name) =>
      _states(name, 'number', _numberAt);

  /// An elevation: a level token or a number.
  double? elevation(String name) => _plain(name, 'elevation', _elevationAt);

  /// An elevation, or one per state.
  WidgetStateProperty<double?>? stateElevation(String name) =>
      _states(name, 'elevation', _elevationAt);

  /// `true` or `false`.
  bool? flag(String name) => _plain(name, 'true / false', _boolAt);

  /// `true` or `false`, or one per state.
  WidgetStateProperty<bool?>? stateFlag(String name) =>
      _states(name, 'true / false', _boolAt);

  /// A whole number.
  int? count(String name) => _plain(
    name,
    'whole number',
    (path) => _leaf(path, int.tryParse, 'a whole number'),
  );

  /// A duration (`250ms`, `1s`).
  Duration? duration(String name) => _plain(
    name,
    'duration',
    (path) => _leaf(path, ThemeValues.duration, 'a duration like 250ms'),
  );

  /// One of the [values] of an enum, in kebab or camel case.
  T? choice<T extends Enum>(String name, List<T> values) => _plain(
    name,
    'one of: ${values.map((v) => _kebab(v.name)).join(' | ')}',
    (path) => _leaf(
      path,
      (raw) => ThemeValues.enumValue(values, raw),
      values.map((v) => v.name).join(', '),
    ),
  );

  /// Insets (`8`, `16, 8`, `1, 2, 3, 4`, or a map), or per state.
  EdgeInsets? insets(String name) => _plain(name, 'insets', _insetsAt);

  /// Insets, or insets per state.
  WidgetStateProperty<EdgeInsetsGeometry?>? stateInsets(String name) =>
      _states<EdgeInsetsGeometry>(name, 'insets', _insetsAt);

  /// A size (`48`, `64, 48`, or a map).
  Size? size(String name) => _plain(name, 'size', _sizeAt);

  /// A size, or a size per state.
  WidgetStateProperty<Size?>? stateSize(String name) =>
      _states(name, 'size', _sizeAt);

  /// An offset (`x, y`).
  Offset? offset(String name) => _plain(name, 'offset', _offsetAt);

  /// Box constraints from `min-width`, `max-width`, `min-height`,
  /// `max-height`.
  BoxConstraints? constraints(String name) =>
      _plain(name, 'constraints', _constraintsAt);

  OutlinedBorder? _tokenShape(String name, bool top) =>
      ThemeValues.canonical(name) == 'shape' &&
          shapeToken != null &&
          theme.shapes.containsKey(shapeToken)
      ? _border(theme.shape(shapeToken!), top: top)
      : null;

  /// A shape: a token, a radius, `stadium`, `circle` or a map. The
  /// property called `shape` follows the component's shape token.
  OutlinedBorder? shape(String name, {bool? top}) {
    final t = top ?? topShape;
    return _shapeAt(_find(name, 'shape'), top: t) ?? _tokenShape(name, t);
  }

  /// A shape, or a shape per state.
  WidgetStateProperty<OutlinedBorder?>? stateShape(String name) {
    final value = _states(name, 'shape', _shapeAt);
    if (value != null) {
      return value;
    }
    final token = _tokenShape(name, topShape);
    return token == null
        ? null
        : WidgetStatePropertyAll<OutlinedBorder?>(token);
  }

  /// A border side: a color, or a map of color, width, style and
  /// stroke-align.
  BorderSide? side(String name) => _plain(name, 'border side', _sideAt);

  /// A border side, or one per state.
  WidgetStateProperty<BorderSide?>? stateSide(String name) =>
      _states(name, 'border side', _sideAt);

  /// A text style: a named one or a map.
  TextStyle? text(String name, {TextStyle? base}) =>
      _plain(name, 'text style', (path) => _textAt(path, base: base));

  /// A text style, or one per state.
  WidgetStateProperty<TextStyle?>? stateText(String name) =>
      _states(name, 'text style', _textAt);

  /// An icon theme: a color or a map of color, size, fill, weight, grade,
  /// optical-size and opacity.
  IconThemeData? icon(String name) => _plain(name, 'icon theme', _iconAt);

  /// An icon theme, or one per state.
  WidgetStateProperty<IconThemeData?>? stateIcon(String name) =>
      _states(name, 'icon theme', _iconAt);

  /// The icon theme whose properties are the component's own, not under
  /// one name: `color`, `size`, `fill`, `weight`, `grade`, `optical-size`,
  /// `opacity`.
  IconThemeData? iconFields() {
    final result = IconThemeData(
      color: color('color'),
      size: number('size'),
      fill: number('fill'),
      weight: number('weight'),
      grade: number('grade'),
      opticalSize: number('opticalSize'),
      opacity: number('opacity'),
    );
    return has ? result : null;
  }

  /// A mouse cursor by name (`click`, `forbidden`), or one per state.
  WidgetStateProperty<MouseCursor?>? stateCursor(String name) =>
      _states(name, 'mouse cursor', _cursorAt);

  /// An alignment (`center`, `top-left`, `x, y`).
  AlignmentGeometry? alignment(String name) =>
      _plain(name, 'alignment', _alignmentAt);

  /// A corner radius or shape token for all four corners.
  BorderRadius? borderRadius(String name) =>
      _plain(name, 'corner radius', _borderRadiusAt);

  /// A corner radius.
  Radius? radius(String name) => _plain(name, 'corner radius', _radiusAt);

  /// A box decoration: a color, or a map of color, radius, border, shape.
  Decoration? decoration(String name) =>
      _plain(name, 'decoration', _decorationAt);

  /// A value of a kind this reader has no method for (a design's own: an
  /// input border, an ink splash). [at] reads it at the property's path
  /// with [leaf], [keys], [kids], [sideAt] and [borderRadiusAt]; [kind]
  /// names it in the reference of the properties.
  T? custom<T>(String name, String kind, T? Function(String path) at) =>
      _plain(name, kind, at);

  /// Like [custom], or one value per state.
  WidgetStateProperty<T?>? customStates<T extends Object>(
    String name,
    String kind,
    T? Function(String path) at,
  ) => _states(name, kind, at);

  /// The single value at [path], parsed by [parse]; `null` when it is not
  /// set. Throws a [ThemePropertyException] saying [expected] when [parse]
  /// gives `null` or the property is a map.
  T? leaf<T>(String path, T? Function(String raw) parse, String expected) =>
      _leaf(path, parse, expected);

  /// The keys of the map at [path]; empty for a single value.
  Set<String> kids(String path) => _kids(path);

  /// The keys of the map at [path], each of which must be one of
  /// [allowed]; [what] names the map in the error.
  Set<String> keys(String path, Set<String> allowed, String what) =>
      _keys(path, allowed, what);

  /// The border side at [path], as [side] reads one.
  BorderSide? sideAt(String path) => _sideAt(path);

  /// The corner radius at [path], as [borderRadius] reads one.
  BorderRadius? borderRadiusAt(String path) => _borderRadiusAt(path);

  /// [raw] as a number; `null` when it is none.
  static double? parseNumber(String raw) => _number(raw);

  /// The overlay style of the status bar: `light` or `dark`.
  SystemUiOverlayStyle? overlayStyle(String name) => _plain(
    name,
    'one of: light | dark',
    (path) => _leaf(
      path,
      (raw) => switch (ThemeValues.canonical(raw)) {
        'light' => SystemUiOverlayStyle.light,
        'dark' => SystemUiOverlayStyle.dark,
        _ => null,
      },
      'light or dark',
    ),
  );

  /// An animation style: a map of `duration` and `reverse-duration`.
  AnimationStyle? animation(String name) => _plain(name, 'animation', (path) {
    if (properties.children(path).isEmpty) {
      return null;
    }
    _keys(path, {'duration', 'reverseduration'}, 'an animation style');
    return AnimationStyle(
      duration: _leaf(
        '$path.duration',
        ThemeValues.duration,
        'a duration like 250ms',
      ),
      reverseDuration: _leaf(
        '$path.reverseduration',
        ThemeValues.duration,
        'a duration like 250ms',
      ),
    );
  });

  /// A reader of the nested group [name] (`input-decoration`,
  /// `cancel-button-style`), whose keys are checked with the component's.
  ThemeReader group(String name) => _child(name);
}
