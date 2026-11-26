import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show SecretNames;
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_model.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/debug_widget_fields.dart';

/// Where the card of a widget in the application graph takes the values it
/// shows: the rows of its `properties` block (the widget's) and of its
/// `state properties` block (its `State`'s). The widgets layer asks every
/// source in turn, the application's beans first, then Flutter's
/// diagnostics ([DiagnosticsWidgetProperties]) and the fields the
/// generator reads ([FieldWidgetProperties]); a name a source before has
/// told is not told again.
abstract interface class WidgetProperties {
  /// The block of the widget's own values.
  static const widget = 'properties';

  /// The block of its `State`'s values.
  static const state = 'state properties';

  /// The rows of [element]'s widget, and of its `State` for a
  /// `StatefulElement`.
  List<DebugGraphDetail> rowsOf(Element element);
}

/// The properties Flutter's diagnostics give a widget and its `State`
/// (`toDiagnosticsNode().getProperties()`, what `debugFillProperties`
/// adds), those not at their default value; in debug builds only,
/// elsewhere none.
final class DiagnosticsWidgetProperties implements WidgetProperties {
  /// The source.
  const DiagnosticsWidgetProperties();

  @override
  List<DebugGraphDetail> rowsOf(Element element) {
    if (!kDebugMode) {
      return const [];
    }
    return [
      ..._of(element.widget, WidgetProperties.widget),
      if (element case StatefulElement(:final state))
        ..._of(state, WidgetProperties.state),
    ];
  }

  static Iterable<DebugGraphDetail> _of(
    Diagnosticable holder,
    String section,
  ) sync* {
    List<DiagnosticsNode> properties;
    try {
      properties = holder.toDiagnosticsNode().getProperties();
    } on Object {
      return;
    }
    for (final property in properties) {
      final name = property.name;
      // Not those at their default value (`fine`), nor Flutter's own
      // bookkeeping (`debug`), as the inspector's summary leaves them.
      if (name == null ||
          name.isEmpty ||
          property.isFiltered(DiagnosticLevel.info)) {
        continue;
      }
      String description;
      try {
        description = property.toDescription();
      } on Object catch (error) {
        description = 'threw ${error.runtimeType}';
      }
      yield DebugValueText.textRow(name, description, section);
    }
  }
}

/// The public fields of the application's widgets and of their `State`
/// classes, read by what the generator writes ([DebugWidgetFields]); none
/// without it (a release build, a build without the widgets layer).
final class FieldWidgetProperties implements WidgetProperties {
  /// The fields [fields] gives, asked when a card first needs them.
  FieldWidgetProperties(this._fields);

  final DebugWidgetFields? Function() _fields;
  late final DebugWidgetFields? _known = _fields();

  @override
  List<DebugGraphDetail> rowsOf(Element element) {
    final fields = _known;
    if (fields == null) {
      return const [];
    }
    return [
      ..._of(fields, element.widget, WidgetProperties.widget),
      if (element case StatefulElement(:final state))
        ..._of(fields, state, WidgetProperties.state),
    ];
  }

  static Iterable<DebugGraphDetail> _of(
    DebugWidgetFields fields,
    Object holder,
    String section,
  ) sync* {
    for (final (name, read) in fields.of(holder)) {
      Object? value;
      try {
        value = read(holder);
      } on Error catch (error) {
        // A `late` field not set yet.
        yield DebugGraphDetail(
          name,
          '$error'.contains('LateInitializationError')
              ? 'not set'
              : 'threw ${error.runtimeType}',
          section: section,
        );
        continue;
      }
      yield DebugValueText.row(name, value, section);
    }
  }
}

/// A kind of value and how a card tells it: short ([short]), and whole on
/// a tap ([whole], `null`: the short text is all) when there is more to
/// tell ([opens]).
final class DebugValueKind {
  /// The kind of the values [matches] holds for.
  const DebugValueKind(this.matches, this.short, {this.whole, this.opens});

  /// Whether a value is of it.
  final bool Function(Object value) matches;

  /// Its short text: `List(6)`, `'Dune'`, `PassportCard`.
  final String Function(Object value) short;

  /// Its whole text, worked out only when the row is opened.
  final String? Function(Object value)? whole;

  /// Whether a value tells more opened, a cheap test; `null`: whenever
  /// there is a [whole].
  final bool Function(Object value)? opens;
}

/// The [DebugValueKind]s of a starter, for the values only it knows (the
/// signals starter's `AsyncValue`): asked before the built-in
/// [DebugValueText.kinds] while registered. A bean of this type registers
/// itself while it lives:
///
/// ```dart
/// BeanDefinition<DebugValueKinds>(
///   name: 'signalsValueKinds',
///   types: const [DebugValueKinds],
///   create: (_) => DebugValueKinds([
///     DebugValueKind(
///       (value) => value is AsyncValue,
///       (value) => describeAsync(value as AsyncValue),
///     ),
///   ]),
///   postConstruct: DebugValueText.addKinds,
///   preDestroy: DebugValueText.removeKinds,
/// )
/// ```
///
/// Put the bean in the starter's debug modules only, so a build without
/// the debug tools has none of it.
///
/// Spring has no counterpart.
final class DebugValueKinds {
  /// The kinds [kinds], asked in their order.
  const DebugValueKinds(this.kinds);

  /// The kinds.
  final List<DebugValueKind> kinds;
}

/// How the debug tools tell a value (a widget's card, a starter's tab):
/// short, on one line, and whole only when its row is opened. A value of
/// a name that looks secret (`SecretNames.looksSecret`: `password`,
/// `apiKey`, `token`) is masked, and so is an address's password and its
/// secret query parameters (`SecretNames.maskedUrl`) in a string or a
/// `Uri`, and the value of a map's entry whose key looks secret.
///
/// The kinds are asked in turn, the first that matches tells the value:
/// those registered by the starters ([addKinds]), then the built-in
/// [kinds]: a string quoted, a number, a flag, an enum value, a list,
/// set, queue or map by its length (`List(6)`, `Map(2)`, its items when
/// opened), another iterable by its type alone (counting it would run
/// it), a function as `Function`, the values whose text is the value
/// (`Duration`, `DateTime`, `Uri`, a `Key`, a `Color`, an `Offset`, a
/// `Size`, a `Rect`) by their text, and any other object by its type
/// ([objectKind]), its `toString()` called only when the row is opened.
/// The short text is one line, cut at [shortLength] or the caller's `max`.
abstract final class DebugValueText {
  /// The longest short text.
  static const shortLength = 60;

  /// The longest whole text.
  static const wholeLength = 4000;

  /// How many items an opened collection lists.
  static const items = 20;

  /// Any other object: by its type, its `toString()` opened.
  static final DebugValueKind objectKind = DebugValueKind(
    (value) => true,
    (value) => '${value.runtimeType}',
    whole: (value) {
      final text = '$value';
      return text.startsWith('Instance of ') ? null : _cut(text, wholeLength);
    },
  );

  static final List<DebugValueKinds> _registered = [];

  /// Asks [kinds] before the built-in ones until [removeKinds] takes them
  /// out: a bean's `postConstruct`. The last added are asked first.
  static void addKinds(DebugValueKinds kinds) => _registered.add(kinds);

  /// Takes out [kinds], added by [addKinds]: a bean's `preDestroy`.
  static void removeKinds(DebugValueKinds kinds) => _registered.remove(kinds);

  /// The built-in kinds in the order they are asked, after the registered
  /// ones.
  static final List<DebugValueKind> kinds = [
    DebugValueKind(
      (value) => value is String,
      (value) => "'${SecretNames.maskedUrl(value as String)}'",
      whole: (value) =>
          _cut(SecretNames.maskedUrl(value as String), wholeLength),
      opens: (value) => (value as String).length + 2 > shortLength,
    ),
    DebugValueKind(
      (value) => value is Uri,
      (value) => SecretNames.maskedUrl('$value'),
    ),
    DebugValueKind(
      (value) => value is num || value is bool,
      (value) => '$value',
    ),
    DebugValueKind(
      (value) => value is Enum,
      (value) => '${value.runtimeType}.${(value as Enum).name}',
    ),
    DebugValueKind(
      (value) => value is Map,
      (value) => 'Map(${(value as Map).length})',
      whole: (value) => _list([
        for (final MapEntry(:key, :value) in (value as Map).entries.take(items))
          '${shortOf(key)}: '
              '${key is String && SecretNames.looksSecret(key) ? SecretNames.masked : shortOf(value)}',
      ], value.length),
      opens: (value) => (value as Map).isNotEmpty,
    ),
    DebugValueKind(
      (value) => value is List || value is Set || value is Queue,
      (value) => '${_collection(value)}(${(value as Iterable).length})',
      whole: (value) => _list([
        for (final item in (value as Iterable).take(items)) shortOf(item),
      ], value.length),
      opens: (value) => (value as Iterable).isNotEmpty,
    ),
    DebugValueKind((value) => value is Iterable, (value) => 'Iterable'),
    DebugValueKind((value) => value is Function, (value) => 'Function'),
    DebugValueKind(
      (value) =>
          value is Duration ||
          value is DateTime ||
          value is Key ||
          value is Color ||
          value is Offset ||
          value is Size ||
          value is Rect,
      (value) => '$value',
    ),
    objectKind,
  ];

  /// The short text of [value], one line of at most [max] characters.
  /// With [objectText], a value of [objectKind] is told by its own
  /// `toString()` (`Loaded(3)`, an error's message), its type when it has
  /// none of its own: for a tool that shows values, not fields.
  static String shortOf(
    Object? value, {
    int max = shortLength,
    bool objectText = false,
  }) {
    if (value == null) {
      return 'null';
    }
    try {
      final kind = _kindOf(value);
      final text = objectText && identical(kind, objectKind)
          ? _ownText(value)
          : kind.short(value);
      return _cut(text.replaceAll('\n', ' '), max);
    } on Object catch (error) {
      return 'threw ${error.runtimeType}';
    }
  }

  static String _ownText(Object value) {
    final text = '$value';
    return text.startsWith('Instance of ') ? '${value.runtimeType}' : text;
  }

  /// The row [name] of [value] in [section]: masked when [name] looks
  /// secret, else short, opening into the whole value when there is more.
  static DebugGraphDetail row(String name, Object? value, String section) {
    if (SecretNames.looksSecret(name)) {
      return DebugGraphDetail(name, SecretNames.masked, section: section);
    }
    final kind = value == null ? null : _kindOf(value);
    final whole = kind != null && (kind.opens?.call(value!) ?? true)
        ? kind.whole
        : null;
    return DebugGraphDetail(
      name,
      shortOf(value),
      section: section,
      more: whole == null
          ? null
          : () {
              try {
                return whole(value!) ?? shortOf(value);
              } on Object catch (error) {
                return 'threw ${error.runtimeType}';
              }
            },
    );
  }

  /// The row [name] of a value already told as [text] (a diagnostics
  /// property's description) in [section]: masked when [name] looks
  /// secret, else cut, opening into the whole text when it is longer.
  static DebugGraphDetail textRow(String name, String text, String section) {
    if (SecretNames.looksSecret(name)) {
      return DebugGraphDetail(name, SecretNames.masked, section: section);
    }
    final long = text.length > shortLength || text.contains('\n');
    final masked = SecretNames.maskedUrl(text);
    return DebugGraphDetail(
      name,
      _cut(masked.split('\n').first, shortLength),
      section: section,
      more: long ? () => _cut(masked, wholeLength) : null,
    );
  }

  static DebugValueKind _kindOf(Object value) {
    for (final registered in _registered.reversed) {
      for (final kind in registered.kinds) {
        if (kind.matches(value)) {
          return kind;
        }
      }
    }
    return kinds.firstWhere((kind) => kind.matches(value));
  }

  static String _collection(Object value) => switch (value) {
    List<Object?>() => 'List',
    Set<Object?>() => 'Set',
    _ => 'Queue',
  };

  static String _list(List<String> shown, int length) => [
    ...shown,
    if (length > shown.length) '… ${length - shown.length} more',
  ].join('\n');

  static String _cut(String text, int length) =>
      text.length <= length ? text : '${text.substring(0, length - 1)}…';
}
