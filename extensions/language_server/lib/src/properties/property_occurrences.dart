import 'package:dart_spring_language_server/src/config/config_format.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';
import 'package:dart_spring_language_server/src/properties/reference_finder.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/templates.dart';

/// A place that names a property key: where a config file defines it,
/// where a value's `${key}` or the code reads it.
final class KeyOccurrence {
  /// [name] at [range], defining the key when [definition] is set.
  const KeyOccurrence(
    this.range,
    this.name, {
    required this.definition,
    this.derived = false,
    this.below,
  });

  /// The text that names the key.
  final SourceRange range;

  /// That text: the key, its last part (a key of nested YAML, a name under
  /// a prefix), or the name of a field it is [derived] from.
  final String name;

  /// Whether a config file defines the key here, rather than a value or
  /// the code reading it.
  final bool definition;

  /// Whether the key is derived from a field's name here (a field of a
  /// `@ConfigurationProperties` class), not written as text.
  final bool derived;

  /// The key of a `Map` or `List` field this place binds when the key
  /// looked for lies below it (`shop.tags` for `shop.tags.x`); null when
  /// the place names the key itself.
  final String? below;
}

/// The places of a package that name a property key, for find references
/// and rename: the entries of its config files, the `${key}` of their
/// values, and what its Dart files read (placeholders, `getProperty`,
/// `@ConditionalOnProperty`, `@ConfigurationProperties` fields). Keys
/// match as the framework binds them (`max-basket-size`, `maxBasketSize`).
final class PropertyOccurrences {
  /// The occurrences in [model].
  const PropertyOccurrences(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  /// The key named at [line] and [column] (zero-based, UTF-16) of [path],
  /// with the range of the text that names it there; `null` where no key
  /// is named.
  ({String key, SourceRange range})? keyAt(String path, int line, int column) {
    final file = model.files.dartFile(path);
    if (file != null) {
      final offset = file.lineInfo.getOffsetOfLine(line) + column;
      for (final reference in PropertyReferenceFinder(model).referencesIn(
        path,
      )) {
        if (reference.nameStart <= offset && offset <= reference.nameEnd) {
          return (
            key: reference.key,
            range: model.locations.rangeOf(
              file,
              reference.nameStart,
              reference.nameEnd,
            ),
          );
        }
      }
      return null;
    }
    for (final entry
        in model.files.configFiles[path] ?? const <PropertyEntry>[]) {
      if (entry.line == line &&
          entry.keyStart <= column &&
          column <= entry.keyEnd) {
        return (
          key: entry.key,
          range: SourceRange(path, line, entry.keyStart, line, entry.keyEnd),
        );
      }
    }
    final lines = model.files.textOf(path)?.split('\n') ?? const <String>[];
    if (line < lines.length) {
      for (final placeholder in _placeholders(path, line, lines[line])) {
        if (placeholder.range.startColumn <= column &&
            column <= placeholder.range.endColumn) {
          return (key: placeholder.name, range: placeholder.range);
        }
      }
    }
    return null;
  }

  /// Every place of [path]'s package that names [key], sorted by file and
  /// position.
  List<KeyOccurrence> of(String path, String key) {
    final canonical = canonicalName(key);
    final found = <String, KeyOccurrence>{};
    void add(KeyOccurrence occurrence) {
      final range = occurrence.range;
      found.putIfAbsent(
        '${range.path}:${range.startLine}:${range.startColumn}',
        () => occurrence,
      );
    }

    for (final entry in model.properties.property(key, from: path)) {
      if (entry.provider != null) {
        continue; // provided by a container, written nowhere
      }
      final range = SourceRange(
        entry.path,
        entry.line,
        entry.keyStart,
        entry.line,
        entry.keyEnd,
      );
      add(KeyOccurrence(range, _textAt(range), definition: true));
    }
    for (final config in model.properties.configFilesOf(path)) {
      final lines = model.files.textOf(config)?.split('\n') ?? const <String>[];
      for (final (line, text) in lines.indexed) {
        for (final placeholder in _placeholders(config, line, text)) {
          if (canonicalName(placeholder.name) == canonical) {
            add(
              KeyOccurrence(
                placeholder.range,
                placeholder.name,
                definition: false,
              ),
            );
          }
        }
      }
    }
    final package = model.packages.packageRootOf(path);
    final finder = PropertyReferenceFinder(model);
    for (final file in [...model.files.dartFiles]) {
      if (model.packages.packageRootOf(file.path) != package) {
        continue;
      }
      for (final reference in finder.referencesOf(file, keep: false)) {
        final named = canonicalName(reference.key);
        final below =
            reference.subtree &&
            (canonical.startsWith('$named.') ||
                canonical.startsWith('$named['));
        if (named == canonical || below) {
          add(
            KeyOccurrence(
              model.locations.rangeOf(
                file,
                reference.nameStart,
                reference.nameEnd,
              ),
              file.text.substring(reference.nameStart, reference.nameEnd),
              definition: false,
              derived: reference.derived,
              below: below ? reference.key : null,
            ),
          );
        }
      }
    }
    return [...found.values]..sort(_byPlace);
  }

  /// The keys of the `${key}` placeholders on [line] of the config file
  /// [path], whose text is [line], each with its range; none in a comment
  /// (a `#` or `!` line of a properties file, what follows an unquoted
  /// ` #` in YAML).
  static Iterable<({String name, SourceRange range})> _placeholders(
    String path,
    int line,
    String whole,
  ) sync* {
    final text = ConfigFormat.of(path).content(whole);
    for (final part in scanTemplate(text)) {
      if (part.kind != TemplatePartKind.placeholder) {
        continue;
      }
      final name = part.inner(text);
      if (name.isEmpty) {
        continue;
      }
      final written = text.substring(part.innerStart, part.keyEnd);
      final start =
          part.innerStart + written.length - written.trimLeft().length;
      yield (
        name: name,
        range: SourceRange(path, line, start, line, start + name.length),
      );
    }
  }

  String _textAt(SourceRange range) {
    final lines =
        model.files.textOf(range.path)?.split('\n') ?? const <String>[];
    if (range.startLine >= lines.length) {
      return '';
    }
    final line = lines[range.startLine];
    return line.substring(
      range.startColumn.clamp(0, line.length),
      range.endColumn.clamp(0, line.length),
    );
  }

  static int _byPlace(KeyOccurrence a, KeyOccurrence b) {
    final x = a.range;
    final y = b.range;
    return x.path != y.path
        ? x.path.compareTo(y.path)
        : x.startLine != y.startLine
        ? x.startLine.compareTo(y.startLine)
        : x.startColumn.compareTo(y.startColumn);
  }
}
