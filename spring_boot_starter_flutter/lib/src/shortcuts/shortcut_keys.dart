import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show OrderComparator;
import 'package:spring_boot_starter_flutter/src/shortcuts/touch_pattern.dart';

/// The keys of a shortcut as the configuration writes them: what Flutter
/// listens for ([activator]) and how a label shows them.
abstract interface class ShortcutKeys {
  /// What Flutter listens for.
  ShortcutActivator get activator;

  /// The keys for a label on [platform]: `⌘K` on Apple's, `Ctrl+K`
  /// elsewhere.
  String label(TargetPlatform platform);
}

/// Reads one way of writing keys (`primary+k`, `char:?`).
/// [ShortcutNotations] asks its notations in order and the first that
/// [supports] a text reads it: a chain of responsibility, so a new way of
/// writing keys is a new notation, registered with
/// `SpringApplicationWidget`'s app as a bean.
///
/// ```dart
/// // `numpad:5`: a key of the number pad.
/// @Component()
/// @Order(0)
/// class NumpadNotation implements ShortcutNotation {
///   @override
///   bool supports(String text) => text.startsWith('numpad:');
///
///   @override
///   ShortcutKeys parse(String text, TargetPlatform platform) => ...;
/// }
/// ```
abstract interface class ShortcutNotation {
  /// Whether this notation reads [text].
  bool supports(String text);

  /// The keys [text] names on [platform]. Throws a [FormatException] that
  /// says what is wrong.
  ShortcutKeys parse(String text, TargetPlatform platform);
}

/// The notations of the shortcuts: the app's own first (by `Ordered`),
/// then the built-in [CharacterNotation], [TouchPatternNotation] and
/// [KeyCombinationNotation].
final class ShortcutNotations {
  /// The chain of [notations], then the built-in ones.
  const ShortcutNotations([this.notations = const []]);

  /// The built-in notations, asked after the app's.
  static const builtIn = <ShortcutNotation>[
    CharacterNotation(),
    TouchPatternNotation(),
    KeyCombinationNotation(),
  ];

  /// The app's own notations.
  final List<ShortcutNotation> notations;

  /// The whole chain, in the order it is asked.
  List<ShortcutNotation> get chain => [
    ...OrderComparator.sort(notations),
    ...builtIn,
  ];

  /// Reads [text], the value of [property], for [platform]. Throws an
  /// [ArgumentError] named after [property] when it names no keys.
  ShortcutKeys parse(
    String text, {
    required String property,
    required TargetPlatform platform,
  }) {
    final trimmed = text.trim();
    for (final notation in chain) {
      if (notation.supports(trimmed)) {
        try {
          return notation.parse(trimmed, platform);
        } on FormatException catch (error) {
          throw ArgumentError.value(text, property, error.message);
        }
      }
    }
    throw ArgumentError.value(text, property, 'is no keys');
  }
}

/// Whether [platform] is Apple's, where `primary` is ⌘.
bool isApplePlatform(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

/// `char:?`: the character typed, whatever keys type it (`?` is Shift+/
/// on one keyboard and a key of its own on another).
final class CharacterNotation implements ShortcutNotation {
  /// The notation of characters.
  const CharacterNotation();

  static const _prefix = 'char:';

  @override
  bool supports(String text) => text.startsWith(_prefix);

  @override
  ShortcutKeys parse(String text, TargetPlatform platform) {
    final character = text.substring(_prefix.length);
    if (character.characters.length != 1) {
      throw const FormatException('char: takes one character, as char:?');
    }
    return _CharacterKeys(character);
  }
}

final class _CharacterKeys implements ShortcutKeys {
  const _CharacterKeys(this.character);

  final String character;

  @override
  ShortcutActivator get activator => CharacterActivator(character);

  @override
  String label(TargetPlatform platform) => character;
}

/// `primary+shift+k`: modifiers and one key, joined by `+`. The modifiers
/// are `shift`, `alt` (`option`), `control` (`ctrl`), `meta` (`cmd`,
/// `command`) and `primary`, which is ⌘ on macOS and iOS and Ctrl
/// elsewhere. The keys are letters, digits, `f1` to `f12`, `enter`,
/// `escape`, `space`, `tab`, `backspace`, `delete`, `home`, `end`,
/// `page-up`, `page-down`, `up`, `down`, `left`, `right`, `slash`,
/// `backslash`, `comma`, `period`, `semicolon`, `quote`, `minus`,
/// `equal`, `bracket-left`, `bracket-right` and `backquote`.
final class KeyCombinationNotation implements ShortcutNotation {
  /// The notation of key combinations.
  const KeyCombinationNotation();

  static const _modifiers = {
    'shift': _Modifier.shift,
    'alt': _Modifier.alt,
    'option': _Modifier.alt,
    'control': _Modifier.control,
    'ctrl': _Modifier.control,
    'meta': _Modifier.meta,
    'cmd': _Modifier.meta,
    'command': _Modifier.meta,
  };

  static final Map<String, (LogicalKeyboardKey, String, String)> _keys = {
    for (var c = 0; c < 26; c++)
      String.fromCharCode(0x61 + c): (
        LogicalKeyboardKey(0x61 + c),
        String.fromCharCode(0x41 + c),
        String.fromCharCode(0x41 + c),
      ),
    for (var d = 0; d < 10; d++)
      '$d': (LogicalKeyboardKey(0x30 + d), '$d', '$d'),
    for (var f = 1; f <= 12; f++)
      'f$f': (LogicalKeyboardKey(0x00100000800 + f), 'F$f', 'F$f'),
    'enter': (LogicalKeyboardKey.enter, '↩', 'Enter'),
    'escape': (LogicalKeyboardKey.escape, '⎋', 'Esc'),
    'esc': (LogicalKeyboardKey.escape, '⎋', 'Esc'),
    'space': (LogicalKeyboardKey.space, 'Space', 'Space'),
    'tab': (LogicalKeyboardKey.tab, '⇥', 'Tab'),
    'backspace': (LogicalKeyboardKey.backspace, '⌫', 'Backspace'),
    'delete': (LogicalKeyboardKey.delete, '⌦', 'Del'),
    'home': (LogicalKeyboardKey.home, '↖', 'Home'),
    'end': (LogicalKeyboardKey.end, '↘', 'End'),
    'page-up': (LogicalKeyboardKey.pageUp, '⇞', 'PgUp'),
    'page-down': (LogicalKeyboardKey.pageDown, '⇟', 'PgDn'),
    'up': (LogicalKeyboardKey.arrowUp, '↑', '↑'),
    'down': (LogicalKeyboardKey.arrowDown, '↓', '↓'),
    'left': (LogicalKeyboardKey.arrowLeft, '←', '←'),
    'right': (LogicalKeyboardKey.arrowRight, '→', '→'),
    'slash': (LogicalKeyboardKey.slash, '/', '/'),
    'backslash': (LogicalKeyboardKey.backslash, r'\', r'\'),
    'comma': (LogicalKeyboardKey.comma, ',', ','),
    'period': (LogicalKeyboardKey.period, '.', '.'),
    'semicolon': (LogicalKeyboardKey.semicolon, ';', ';'),
    'quote': (LogicalKeyboardKey.quote, "'", "'"),
    'minus': (LogicalKeyboardKey.minus, '-', '-'),
    'equal': (LogicalKeyboardKey.equal, '=', '='),
    'bracket-left': (LogicalKeyboardKey.bracketLeft, '[', '['),
    'bracket-right': (LogicalKeyboardKey.bracketRight, ']', ']'),
    'backquote': (LogicalKeyboardKey.backquote, '`', '`'),
  };

  static final _plain = RegExp(r'^([a-z0-9]|f[0-9]+)$');

  /// The names of the keys, for messages and completion.
  static Iterable<String> get keyNames => _keys.keys;

  @override
  bool supports(String text) => true;

  @override
  ShortcutKeys parse(String text, TargetPlatform platform) {
    final parts = [
      for (final part in text.toLowerCase().split('+')) part.trim(),
    ];
    final modifiers = <_Modifier>{};
    for (final part in parts.take(parts.length - 1)) {
      final modifier = part == 'primary'
          ? (isApplePlatform(platform) ? _Modifier.meta : _Modifier.control)
          : _modifiers[part];
      if (modifier == null) {
        throw FormatException(
          "'$part' is no modifier: primary, shift, alt, control, meta",
        );
      }
      modifiers.add(modifier);
    }
    final name = parts.last;
    final key = _keys[name];
    if (key == null) {
      throw FormatException(
        "'$name' is no key: a letter, a digit, f1 to f12, or one of "
        '${_keys.keys.where((k) => !_plain.hasMatch(k)).join(', ')}',
      );
    }
    return _Combination(key, modifiers);
  }
}

enum _Modifier {
  control('⌃', 'Ctrl'),
  alt('⌥', 'Alt'),
  shift('⇧', 'Shift'),
  meta('⌘', 'Meta');

  const _Modifier(this.apple, this.other);

  final String apple;
  final String other;
}

final class _Combination implements ShortcutKeys {
  const _Combination(this.key, this.modifiers);

  final (LogicalKeyboardKey, String, String) key;
  final Set<_Modifier> modifiers;

  @override
  ShortcutActivator get activator => SingleActivator(
    key.$1,
    control: modifiers.contains(_Modifier.control),
    alt: modifiers.contains(_Modifier.alt),
    shift: modifiers.contains(_Modifier.shift),
    meta: modifiers.contains(_Modifier.meta),
  );

  @override
  String label(TargetPlatform platform) {
    final ordered = [
      for (final modifier in _Modifier.values)
        if (modifiers.contains(modifier)) modifier,
    ];
    return isApplePlatform(platform)
        ? [for (final m in ordered) m.apple, key.$2].join()
        : [for (final m in ordered) m.other, key.$3].join('+');
  }
}
