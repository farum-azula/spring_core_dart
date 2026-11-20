import 'package:dart_spring_language_server/src/properties/property_entry.dart';
import 'package:spring_core_dart/core.dart'
    show Profiles, PropertyPlaceholderHelper;

/// The profiles values are read under, in the order they were activated.
///
/// As in the framework, an entry of a profile wins over an entry of every
/// profile, an entry of a later active profile over an earlier one's, a
/// profile's own file (`application-prod.yaml`) over a profile's document
/// of `application.yaml`, `.properties` over `.yaml` of the same name, and
/// within one file a later entry over an earlier one. The properties a
/// test sets for its context win over all of them.
final class ActiveProfiles {
  /// The profiles [names], in order; with none, the framework's `default`
  /// profile is active.
  ActiveProfiles(List<String> names)
    : names = List.unmodifiable(names.isEmpty ? const ['default'] : names);

  /// The profiles of a `spring.profiles.active` value (`dev, local`).
  factory ActiveProfiles.parse(String value) => ActiveProfiles([
    for (final name in value.split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ]);

  /// The active profiles, in order.
  final List<String> names;

  static final _profileFile = RegExp(r'^application-(.+)$');

  /// Where [entry] stands under these profiles, to compare with another
  /// entry of the same key (the greater wins); null when it is for a
  /// profile that is not active.
  ({int rank, int file, int line})? standingOf(PropertyEntry entry) {
    if (entry.path.endsWith('.dart')) {
      return (rank: names.length + 1, file: 0, line: entry.line);
    }
    final fileProfile = _profileFile.firstMatch(entry.fileName)?.group(1);
    if (fileProfile != null && !names.contains(fileProfile)) {
      return null;
    }
    final expression = entry.profile;
    if (expression != null && !_matches(expression)) {
      return null;
    }
    final rank = [
      if (fileProfile != null) names.indexOf(fileProfile) + 1,
      if (expression != null) _lastNamedIn(expression) + 1,
    ].fold(0, (best, rank) => rank > best ? rank : best);
    return (
      rank: rank,
      file:
          (fileProfile == null ? 0 : 2) +
          (entry.path.endsWith('.properties') ? 1 : 0),
      line: entry.line,
    );
  }

  bool _matches(String expression) {
    try {
      return Profiles.of([
        for (final part in expression.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ]).matches(names.contains);
    } on ArgumentError {
      return false; // a malformed expression activates nothing
    }
  }

  /// The position of the last active profile [expression] names; 0 when
  /// it names none (`!dev` with `prod` active).
  int _lastNamedIn(String expression) {
    var last = 0;
    for (var i = 0; i < names.length; i++) {
      if (RegExp('(?<![\\w.-])${RegExp.escape(names[i])}(?![\\w.-])')
          .hasMatch(expression)) {
        last = i;
      }
    }
    return last;
  }
}

/// What a property resolves to: [text], and the [entry] it comes from.
final class PropertyValue {
  /// The value [text] of [entry]; with no entry, a placeholder's default.
  const PropertyValue(this.text, {this.entry});

  /// The value, with the placeholders in it resolved.
  final String text;

  /// The entry that wins; null when [text] is a placeholder's default.
  final PropertyEntry? entry;

  /// Whether no entry gives the property, and [text] is a default.
  bool get fromDefault => entry == null;
}

/// The values of properties as the framework resolves them for
/// [profiles], from the entries a lookup gives for each key.
final class PropertyValues {
  /// Values from the entries a lookup gives for a key, under [profiles].
  PropertyValues(this._entriesOf, this.profiles);

  final List<PropertyEntry> Function(String key) _entriesOf;

  /// The profiles values are read under.
  final ActiveProfiles profiles;

  static final _placeholders = PropertyPlaceholderHelper(
    ignoreUnresolvablePlaceholders: true,
  );

  /// The entry of [key] that wins under [profiles]; null when none applies.
  PropertyEntry? winner(String key) {
    PropertyEntry? best;
    ({int rank, int file, int line})? bestStanding;
    for (final entry in _entriesOf(key)) {
      final standing = profiles.standingOf(entry);
      if (standing != null &&
          (bestStanding == null || _compare(standing, bestStanding) >= 0)) {
        best = entry;
        bestStanding = standing;
      }
    }
    return best;
  }

  /// The value of [key]: the winning entry's, its placeholders resolved
  /// (those that resolve to nothing stay as written, as do cycles); with no
  /// entry, [fallback] (a placeholder's default); null when there is
  /// neither.
  PropertyValue? valueOf(String key, {String? fallback}) {
    final entry = winner(key);
    if (entry != null) {
      return PropertyValue(_resolve(_text(entry), {key}), entry: entry);
    }
    return fallback == null ? null : PropertyValue(_resolve(fallback, {key}));
  }

  String _resolve(String text, Set<String> resolving) {
    if (!text.contains(r'${')) {
      return text;
    }
    try {
      return _placeholders.replacePlaceholders(text, (key) {
        if (resolving.contains(key)) {
          return null;
        }
        final inner = winner(key);
        return inner == null
            ? null
            : _resolve(_text(inner), {...resolving, key});
      });
    } on Object {
      return text;
    }
  }

  static final _stringLiteral = RegExp(r'''^r?(['"])(.*)\1$''', dotAll: true);

  /// The value of [entry] as text: a test's entry holds the source of its
  /// value, so a string literal (`'99'`) gives what it says (`99`).
  static String _text(PropertyEntry entry) {
    if (!entry.path.endsWith('.dart')) {
      return entry.value;
    }
    return _stringLiteral.firstMatch(entry.value)?.group(2) ?? entry.value;
  }

  static int _compare(
    ({int rank, int file, int line}) a,
    ({int rank, int file, int line}) b,
  ) {
    if (a.rank != b.rank) {
      return a.rank.compareTo(b.rank);
    }
    if (a.file != b.file) {
      return a.file.compareTo(b.file);
    }
    return a.line.compareTo(b.line);
  }
}
