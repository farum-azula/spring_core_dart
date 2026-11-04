import 'package:spring_core_dart_generator/src/did_you_mean.dart';
import 'package:spring_core_dart_generator/src/theme_value_syntax.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart';

/// The type of a value of a theme, as the generated getter returns it.
enum ValueKind {
  /// A color.
  color('Color', 'Color'),

  /// A number.
  number('double', 'number'),

  /// A duration (`250ms`).
  duration('Duration', 'duration'),

  /// Any other text.
  text('String', 'text'),

  /// Padding or margins of a style: one to four numbers.
  insets('EdgeInsets', 'insets'),

  /// A list of colors.
  colors('List<Color>', 'list of colors'),

  /// A list of numbers.
  numbers('List<double>', 'list of numbers'),

  /// A list of texts.
  texts('List<String>', 'list of texts'),

  /// An image: a map with a `source`.
  image('ThemeImage', 'image');

  ValueKind(this.dartType, this.label);

  /// The Dart type of the getter.
  final String dartType;

  /// The name in error messages.
  final String label;
}

/// Lower case without `-` and `_`, as the runtime compares theme keys.
String canonicalName(String name) =>
    name.toLowerCase().replaceAll('-', '').replaceAll('_', '');

/// One property of a theme: the path below the theme (`tokens.neon.yellow`,
/// list items as `.0`, `.1`), its value and the property it was written as.
final class ThemeEntry {
  /// An entry of the path [key] ([segments] as written).
  ThemeEntry(this.key, this.segments, this.value, this.origin);

  /// The canonical path, segments joined with dots.
  final String key;

  /// The path as written.
  final List<String> segments;

  /// The raw value.
  final String value;

  /// The full property name, for error messages.
  final String origin;
}

/// A node of the tree of a theme's properties.
final class ThemeNode {
  /// A node for a segment written as [spelling].
  ThemeNode(this.spelling);

  /// The segment as first written.
  final String spelling;

  /// The children by canonical segment.
  final children = <String, ThemeNode>{};

  /// The value of this node, when it has one.
  ThemeEntry? entry;

  /// How many segments lead here from the theme's root.
  int depth = 0;

  /// Whether the children are list items (`0`, `1`, ...).
  bool get isList =>
      children.isNotEmpty &&
      children.keys.every((key) => int.tryParse(key) != null);

  /// The items of a list node, in order.
  List<ThemeNode> get items => [
    for (final key
        in children.keys.toList()
          ..sort((a, b) => int.parse(a).compareTo(int.parse(b))))
      children[key]!,
  ];
}

/// Every theme the configuration declares: the shared base and a layer per
/// `themes.<name>`, resolved after `extends` the way the runtime does.
final class ThemeSet {
  ThemeSet._(this._diagnostics);

  final KeysDiagnostics _diagnostics;
  final _base = <String, ThemeEntry>{};
  final _layers =
      <String, ({String spelling, Map<String, ThemeEntry> entries})>{};
  final _reported = <String>{};

  /// The prefix of the properties read.
  static const prefix = 'spring.flutter.theme.';

  // Keys of a theme about where it comes from, not its look.
  static const _notLook = {'extends', 'source', 'sourcesha256', 'refresh'};

  /// Reads the `spring.flutter.theme.*` properties; `null` when there are
  /// none.
  static ThemeSet? read(
    Iterable<ConfigProperty> properties,
    KeysDiagnostics diagnostics,
  ) {
    final set = ThemeSet._(diagnostics);
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
      var segments = name.substring(prefix.length).split('.');
      var target = set._base;
      if (canonicalName(segments.first) == 'themes') {
        if (segments.length < 3) {
          continue;
        }
        target = set._layers
            .putIfAbsent(
              canonicalName(segments[1]),
              () => (spelling: segments[1], entries: {}),
            )
            .entries;
        segments = segments.sublist(2);
      }
      final key = segments.map(canonicalName).join('.');
      target[key] = ThemeEntry(key, segments, property.value, property.name);
    }
    return any ? set : null;
  }

  /// The names of the themes, `light` and `dark` first, then the declared
  /// ones in order, as first written.
  late final List<String> names = () {
    final result = <String, String>{'light': 'light', 'dark': 'dark'};
    for (final MapEntry(:key, :value) in _layers.entries) {
      result.putIfAbsent(key, () => value.spelling);
    }
    return result.values.toList();
  }();

  /// The theme [name] resolved: brightness aside, the base (or the theme it
  /// extends) with the theme's own properties over it.
  ThemeScope scope(String name) =>
      ThemeScope._(this, name, _resolve(canonicalName(name), const []));

  Map<String, ThemeEntry> _resolve(String canon, List<String> chain) {
    final result = <String, ThemeEntry>{};
    if (chain.contains(canon)) {
      _error(
        'The themes extend each other in a cycle: '
        '${[...chain, canon].join(' -> ')} '
        '(spring.flutter.theme.themes.*.extends).',
      );
      return {..._base};
    }
    final layer = _layers[canon];
    final parent = layer?.entries['extends']?.value.trim();
    if (parent != null && parent.isNotEmpty) {
      final parentCanon = canonicalName(parent);
      final known = names.map(canonicalName).toList();
      if (!known.contains(parentCanon) || parentCanon == canon) {
        final hint = closestName(parent, names.where((n) => n != canon));
        _error(
          "Theme '$canon' extends '$parent', which is no theme"
          '${hint == null ? '' : "; did you mean '$hint'?"}',
        );
        _merge(result, _base);
      } else {
        _merge(result, _resolve(parentCanon, [...chain, canon]));
      }
    } else {
      _merge(result, _base);
    }
    if (layer != null) {
      _merge(result, {
        for (final MapEntry(:key, :value) in layer.entries.entries)
          if (!_notLook.contains(key)) key: value,
      });
    }
    return result;
  }

  static final _indexed = RegExp(r'^(.*)\.(\d+)$');

  // In a style property (`styles.chip.fill`) a later layer's plain value,
  // list or map of states replaces one of another shape of an earlier
  // layer; maps of states merge state by state.
  static void _dropOtherShape(Map<String, ThemeEntry> target, String key) {
    final segments = key.split('.');
    if (segments.length < 3 || segments.first != 'styles') {
      return;
    }
    final property = segments.take(3).join('.');
    if (segments.length == 3) {
      target.removeWhere((existing, _) => existing.startsWith('$property.'));
      return;
    }
    final isItem = int.tryParse(segments[3]) != null;
    target.removeWhere((existing, _) {
      if (existing == property) {
        return true;
      }
      final other = existing.split('.');
      return other.length > 3 &&
          existing.startsWith('$property.') &&
          (int.tryParse(other[3]) != null) != isItem;
    });
  }

  // Puts [source] over [target]; a list in [source] replaces the whole
  // list of [target].
  static void _merge(
    Map<String, ThemeEntry> target,
    Map<String, ThemeEntry> source,
  ) {
    final replaced = <String>{};
    for (final key in source.keys) {
      _dropOtherShape(target, key);
      final list = _indexed.firstMatch(key)?.group(1) ?? key;
      if (replaced.add(list)) {
        target.removeWhere(
          (existing, _) =>
              existing == list ||
              _indexed.firstMatch(existing)?.group(1) == list,
        );
      }
    }
    target.addAll(source);
  }

  // An error found in several themes (a base value) is reported once.
  void _error(String message, {String? theme}) {
    if (_reported.add(message)) {
      _diagnostics.errors.add(
        theme == null || theme == 'light'
            ? message
            : "$message (theme '$theme')",
      );
    }
  }
}

/// One theme with its references resolved: gives the type of any value,
/// following `$path` references and color objects, and reports an
/// unknown reference or a cycle.
final class ThemeScope {
  ThemeScope._(this._set, this.name, this.entries) {
    for (final entry in entries.values) {
      var node = root;
      for (final segment in entry.segments) {
        final parent = node;
        node = node.children.putIfAbsent(
          canonicalName(segment),
          () => ThemeNode(segment)..depth = parent.depth + 1,
        );
      }
      node.entry = entry;
    }
  }

  final ThemeSet _set;

  /// The theme's name.
  final String name;

  /// The resolved properties by canonical path.
  final Map<String, ThemeEntry> entries;

  /// The tree of [entries].
  final root = ThemeNode('');

  final _memo = <String, ValueKind>{};
  final _stack = <ThemeEntry>[];

  // Material 3 colors a theme has without declaring them.
  static final Map<String, String> _roles = {
    for (final role in const [
      'primary', 'on-primary', 'primary-container', 'on-primary-container', //
      'primary-fixed', 'primary-fixed-dim', 'on-primary-fixed', //
      'on-primary-fixed-variant', 'secondary', 'on-secondary', //
      'secondary-container', 'on-secondary-container', 'secondary-fixed', //
      'secondary-fixed-dim', 'on-secondary-fixed', //
      'on-secondary-fixed-variant', 'tertiary', 'on-tertiary', //
      'tertiary-container', 'on-tertiary-container', 'tertiary-fixed', //
      'tertiary-fixed-dim', 'on-tertiary-fixed', 'on-tertiary-fixed-variant', //
      'error', 'on-error', 'error-container', 'on-error-container', //
      'surface', 'on-surface', 'on-surface-variant', 'surface-dim', //
      'surface-bright', 'surface-container-lowest', 'surface-container-low', //
      'surface-container', 'surface-container-high', //
      'surface-container-highest', 'surface-tint', 'inverse-surface', //
      'on-inverse-surface', 'inverse-primary', 'outline', //
      'outline-variant', 'shadow', 'scrim',
    ])
      canonicalName(role): role,
  };

  // The corner radii of the Material 3 shape scale.
  static final Map<String, String> _shapes = {
    for (final shape in const [
      'none', 'extra-small', 'small', 'medium', 'large', 'large-increased', //
      'extra-large', 'extra-large-increased', 'extra-extra-large', 'full',
    ])
      canonicalName(shape): shape,
  };

  static final _ref = RegExp(r'^\$([A-Za-z][\w\-]*(?:\.[\w\-]+)*)$');

  /// Reports every unresolvable reference of the theme, and a color object
  /// (`colors.<role>`, `seed-color`) that is wrong.
  void checkAll() {
    entries.values.toList().forEach(_evaluate);
    final colorNodes = [
      ...?root.children['colors']?.children.values,
      ?root.children['seedcolor'],
    ];
    for (final node in colorNodes) {
      if (node.entry == null && node.children.isNotEmpty) {
        _colorObject(node);
      }
    }
  }

  static const _objectKeys = ['color', 'mix', 'alpha'];
  static const _mixKeys = ['with', 'amount'];
  static const _percentText = 'a percent: 0% to 100% or 0 to 1';
  final _objects = <ThemeNode>{};

  // The first property below [node], for error messages.
  String _origin(ThemeNode node) {
    if (node.entry case final entry?) {
      return entry.origin;
    }
    for (final child in node.children.values) {
      return _origin(child);
    }
    return name;
  }

  // The checks of the color object [node], once; always a color.
  ValueKind _colorObject(ThemeNode node) {
    if (!_objects.add(node)) {
      return ValueKind.color;
    }
    final origin = _origin(node);
    for (final MapEntry(:key, value: child) in node.children.entries) {
      if (!_objectKeys.contains(key)) {
        final hint = closestName(key, _objectKeys);
        _error(
          '${_origin(child)}: a key of a color object: '
          '${_objectKeys.join(', ')}'
          "${hint == null ? '' : " (did you mean '$hint'?)"}.",
        );
      }
    }
    final color = node.children['color'];
    if (color == null) {
      _error("$origin: a color object with a 'color' is expected.");
    } else {
      _colorOperand(color);
    }
    if (node.children['mix'] case final mix?) {
      _mix(mix);
    }
    if (node.children['alpha'] case final alpha?) {
      _percent(alpha);
    }
    return ValueKind.color;
  }

  void _mix(ThemeNode mix) {
    final origin = _origin(mix);
    if (mix.entry != null ||
        mix.children.length != 2 ||
        !_mixKeys.every(mix.children.containsKey)) {
      for (final MapEntry(:key, value: child) in mix.children.entries) {
        if (!_mixKeys.contains(key)) {
          final hint = closestName(key, _mixKeys);
          _error(
            '${_origin(child)}: a key of mix: ${_mixKeys.join(', ')}'
            "${hint == null ? '' : " (did you mean '$hint'?)"}.",
          );
        }
      }
      _error(
        "$origin: mix as an object with 'with' (a color) and 'amount' "
        '(a percent).',
      );
      return;
    }
    _colorOperand(mix.children['with']!);
    _percent(mix.children['amount']!);
  }

  // A color or a color object.
  void _colorOperand(ThemeNode node) {
    if (node.entry != null && node.children.isEmpty) {
      final kind = _evaluate(node.entry!);
      if (kind != ValueKind.color) {
        _error(
          '${node.entry!.origin}: a color is expected, found ${kind.label}.',
        );
      }
    } else if (node.children.containsKey('color')) {
      _colorObject(node);
    } else {
      _error('${_origin(node)}: a color is expected, found a group of values.');
    }
  }

  void _percent(ThemeNode node) {
    final value = node.entry?.value.trim();
    // A reference gives its text at run time.
    if (value == null ||
        (!value.contains(r'$') && !ThemeValueSyntax.isPercent(value))) {
      _error('${_origin(node)}: $_percentText.');
    }
  }

  /// The node at the canonical [path] below the theme, or `null`.
  ThemeNode? node(Iterable<String> path) {
    var node = root;
    for (final segment in path) {
      final next = node.children[segment];
      if (next == null) {
        return null;
      }
      node = next;
    }
    return node;
  }

  /// The type of [node]: `null` for a group of values. A list of numbers is
  /// [ValueKind.insets] when [insets] (so is a text of two or four numbers;
  /// without [insets] that is text). A token map at least
  /// `tokens.<group>.<key>` deep with a `source` and only image keys is
  /// [ValueKind.image] when [image] (the runtime's rule: any other child
  /// makes it a group). With [groups] a map with a `color` and other keys
  /// is a group, not a color object (the keys of a loader). Problems are
  /// reported.
  ValueKind? nodeKind(
    ThemeNode node, {
    bool insets = false,
    bool image = false,
    bool groups = false,
  }) {
    if (node.entry != null && node.children.isEmpty) {
      final kind = _evaluate(node.entry!);
      return kind == ValueKind.insets && !insets ? ValueKind.text : kind;
    }
    // A map with a `color` is a color; with [groups] only when it has
    // nothing but the keys of a color object (`door: {color, edge}` is a
    // group with a color in it).
    if (node.entry == null &&
        node.children.containsKey('color') &&
        (!groups || node.children.keys.every(_objectKeys.contains))) {
      return _colorObject(node);
    }
    if (node.isList) {
      return _listKind(node, insets: insets);
    }
    if (image &&
        node.depth >= 3 &&
        node.children['source']?.entry != null &&
        node.children.keys.every(ThemeValueSyntax.imageKeys.contains)) {
      return ValueKind.image;
    }
    if (node.entry != null) {
      return _evaluate(node.entry!);
    }
    return null;
  }

  ValueKind _listKind(ThemeNode list, {bool insets = false}) {
    final items = list.items;
    final kinds = <ValueKind>{
      for (final item in items)
        if (item.entry case final entry?) _evaluate(entry),
    };
    final origin = items.first.entry?.origin ?? name;
    if (kinds.length == 1) {
      switch (kinds.single) {
        case ValueKind.color:
          return ValueKind.colors;
        case ValueKind.number:
          if (!insets) {
            return ValueKind.numbers;
          }
          if (items.length == 3 || items.length > 4) {
            _error(
              '$origin: insets are [all], [horizontal, vertical] or '
              '[left, top, right, bottom], not ${items.length} numbers.',
            );
          }
          return ValueKind.insets;
        case ValueKind.text:
          return ValueKind.texts;
        case ValueKind.duration ||
            ValueKind.insets ||
            ValueKind.colors ||
            ValueKind.numbers ||
            ValueKind.texts ||
            ValueKind.image:
      }
    }
    _error(
      '$origin: a list holds one type (colors, numbers or texts), found '
      '${kinds.map((k) => k.label).join(', ')}.',
    );
    return ValueKind.texts;
  }

  ValueKind _evaluate(ThemeEntry entry) {
    final known = _memo[entry.key];
    if (known != null) {
      return known;
    }
    if (_stack.any((e) => e.key == entry.key)) {
      final chain = [
        for (final e in _stack.skipWhile((e) => e.key != entry.key)) e.origin,
        entry.origin,
      ];
      _error('References form a cycle: ${chain.join(' -> ')}.');
      return ValueKind.text;
    }
    _stack.add(entry);
    var kind = _classify(entry.value.trim(), entry);
    _stack.removeLast();
    final section = entry.key.split('.').first;
    if (section == 'colors' && entry.key.split('.').length == 2) {
      if (kind != ValueKind.color) {
        _error('${entry.origin}: a color is expected, found ${kind.label}.');
        kind = ValueKind.color;
      }
    } else if ((section == 'spacing' || section == 'shape') &&
        entry.key.contains('.')) {
      kind = ValueKind.number;
    } else if (entry.key.startsWith('motion.durations.')) {
      kind = ValueKind.duration;
    }
    return _memo[entry.key] = kind;
  }

  // `$$` is a literal `$`, `$` + name anywhere in a text is a reference
  // (as the runtime replaces it); `${...}` is Spring's placeholder.
  static final _embedded = RegExp(r'\$\$|\$([A-Za-z][A-Za-z0-9_.\-]*)');

  ValueKind _classify(String value, ThemeEntry entry) {
    final kind = _classifyExpression(value, entry);
    if (kind == ValueKind.text && value.contains(r'$')) {
      // A text with references in it: they must exist, and the text is text.
      for (final match in _embedded.allMatches(value)) {
        final path = match[1]?.replaceAll(RegExp(r'[.\-]+$'), '');
        if (path != null && path.isNotEmpty) {
          _reference(path, entry);
        }
      }
    }
    return kind;
  }

  ValueKind _classifyExpression(String value, ThemeEntry entry) {
    if (value.isEmpty || value.startsWith(r'$$') || value.startsWith(r'${')) {
      return ValueKind.text;
    }
    if (ThemeValueSyntax.isNumber(value)) {
      return ValueKind.number;
    }
    if (ThemeValueSyntax.isDuration(value)) {
      return ValueKind.duration;
    }
    if (ThemeValueSyntax.isInsets(value)) {
      return ValueKind.insets;
    }
    // A one-line color with changes is text: it is an object now.
    if (value.contains(RegExp(r'\s'))) {
      return ValueKind.text;
    }
    return _operand(value, entry);
  }

  ValueKind _operand(String word, ThemeEntry entry) {
    if (_ref.firstMatch(word) case final match?) {
      return _reference(match[1]!, entry);
    }
    return ThemeValueSyntax.isPlainColor(word)
        ? ValueKind.color
        : ValueKind.text;
  }

  ValueKind _reference(String path, ThemeEntry from) {
    final written = path.split('.');
    var canon = written.map(canonicalName).toList();
    if (!ThemeValueSyntax.rootSections.contains(canon.first)) {
      canon = ['tokens', ...canon];
    }
    final target = node(canon);
    if (target != null) {
      final kind = nodeKind(target, image: true);
      if (kind != null) {
        return kind;
      }
      _error(
        '${from.origin}: \$$path is a group of values, not a value '
        '(${_chain(from, path)}).',
      );
      return ValueKind.text;
    }
    if (canon.length == 2 &&
        canon[0] == 'colors' &&
        _roles.containsKey(canon[1])) {
      return ValueKind.color;
    }
    if (canon.length == 2 &&
        canon[0] == 'shape' &&
        _shapes.containsKey(canon[1])) {
      return ValueKind.number;
    }
    final candidates = <String, String>{
      for (final entry in entries.values)
        if (entry.key.contains('.')) entry.key: entry.segments.join('.'),
      for (final MapEntry(:key, :value) in _roles.entries)
        'colors.$key': 'colors.$value',
      for (final MapEntry(:key, :value) in _shapes.entries)
        'shape.$key': 'shape.$value',
    };
    final close = closestName(canon.join('.'), candidates.keys);
    _error(
      '${from.origin}: unknown reference \$$path (${_chain(from, path)})'
      '${close == null ? '' : '. Did you mean \$${candidates[close]}?'}',
    );
    return ValueKind.text;
  }

  String _chain(ThemeEntry from, String path) => [
    for (final entry in _stack) entry.origin.replaceFirst(ThemeSet.prefix, ''),
    '\$$path',
  ].join(' -> ');

  void _error(String message) => _set._error(message, theme: name);
}
