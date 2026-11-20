import 'package:dart_spring_language_server/src/diagnostics/fix.dart';
import 'package:dart_spring_language_server/src/properties/property_occurrences.dart';

/// What renaming a property key changes, or why it cannot be renamed.
sealed class KeyRenamePlan {
  const KeyRenamePlan();
}

/// The edits of a rename: one for each place that names the key.
final class KeyRenameEdits extends KeyRenamePlan {
  /// The [edits] that rename the key.
  const KeyRenameEdits(this.edits);

  /// The edits, in the order of the places.
  final List<TextEdit> edits;
}

/// A rename that would leave a place reading the old key, and why.
final class KeyRenameRefused extends KeyRenamePlan {
  /// A refusal for [reason].
  const KeyRenameRefused(this.reason);

  /// Why, for the user.
  final String reason;
}

/// Renames a property key at every place of its package that names it
/// (the config files' entries, the `${key}` of values, the code's
/// placeholders, `getProperty` and `@ConditionalOnProperty` keys).
///
/// A place that names only the key's last part (a key of nested YAML,
/// `@ConditionalOnProperty('cache', prefix: 'shop')`) gets the new key's
/// last part, so the new key must keep the old one's prefix there. The
/// rename is refused where it would leave a place reading the old key: a
/// field of a `@ConfigurationProperties` class binds it (rename the
/// field), or a place writes it in another form (`maxBasketSize` for
/// `max-basket-size`).
final class KeyRename {
  /// Renames over [occurrences].
  const KeyRename(this.occurrences);

  /// Where keys are named.
  final PropertyOccurrences occurrences;

  static final _validKey = RegExp(r'^[A-Za-z0-9_\-]+(\.[A-Za-z0-9_\-\[\]]+)*$');

  /// The plan for renaming [key], named in [path], to [newKey].
  KeyRenamePlan plan(String path, String key, String newKey) {
    final renamed = newKey.trim();
    if (!_validKey.hasMatch(renamed)) {
      return KeyRenameRefused(
        "'$renamed' is not a property key: dot-separated names of letters, "
        'digits, - and _',
      );
    }
    final edits = <TextEdit>[];
    for (final occurrence in occurrences.of(path, key)) {
      final range = occurrence.range;
      final where = '${_fileName(range.path)}:${range.startLine + 1}';
      final name = occurrence.name;
      if (occurrence.derived) {
        return KeyRenameRefused(
          "'$key' is bound by the field '$name' of a "
          '@ConfigurationProperties class ($where): rename the field instead',
        );
      }
      final text = _renamed(name, key, renamed);
      if (text == null) {
        final prefix = key.endsWith('.$name')
            ? key.substring(0, key.length - name.length - 1)
            : null;
        return KeyRenameRefused(
          prefix != null && name != key
              ? "'$key' is written as '$name' under the prefix '$prefix' "
                    '($where): the new key must keep that prefix'
              : "'$key' is written as '$name' ($where): rename it by hand",
        );
      }
      edits.add(TextEdit(range, text));
    }
    return KeyRenameEdits(edits);
  }

  /// What a place naming [key] as [name] becomes for [newKey]; `null` when
  /// it cannot name the new key.
  static String? _renamed(String name, String key, String newKey) {
    if (name == key) {
      return newKey;
    }
    if (!key.endsWith('.$name')) {
      return null;
    }
    final prefix = key.substring(0, key.length - name.length);
    return newKey.startsWith(prefix) && newKey.length > prefix.length
        ? newKey.substring(prefix.length)
        : null;
  }

  static String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;
}
