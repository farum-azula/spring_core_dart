import 'package:spring_core_dart/core.dart';
import 'package:spring_core_dart_generator/src/dart_names.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart';

/// Writes the typed accessors of the message files: `context.messages`
/// with a class per key prefix, a getter for a message without arguments
/// and a method with one `Object?` parameter per `{0}`, `{1}`, ...
/// argument for a message with some.
///
/// The files are `<basename>.properties` and `<basename>_<locale>.properties`
/// of `lib/resources/` for each `spring.messages.basename` (`messages` by
/// default). A key missing in a locale file, or only in a locale file, is a
/// warning; a key with a different number of arguments in two files, a key
/// that is both a message and a prefix of other keys (`basket` and
/// `basket.total`), a key with no Dart name and a placeholder that
/// `MessageFormat` rejects are errors.
///
/// ```properties
/// # messages.properties
/// basket.total=Total: {0}
/// basket.empty=Your basket is empty
/// ```
///
/// ```dart
/// // Output
/// context.messages.basket.total(price); // context.message('basket.total', args: [price])
/// context.messages.basket.empty; // context.message('basket.empty')
/// ```
final class TypedMessageKeys {
  TypedMessageKeys._(this._diagnostics);

  final KeysDiagnostics _diagnostics;

  /// The property that names the bases of the message files.
  static const basenameProperty = 'spring.messages.basename';

  // The tree of keys: a segment is a group (children) or a message.
  final _root = _Group('AppMessages', '');

  /// Reads the message files in [texts] (paths below `lib/resources/`);
  /// [properties] are the configuration's, for `spring.messages.basename`.
  /// Returns the Dart code of `AppMessages` and its groups, or `null` when
  /// there is no message file or a problem was found (reported in
  /// [diagnostics]).
  static String? generate(
    Map<String, String> texts,
    Iterable<ConfigProperty> properties,
    KeysDiagnostics diagnostics,
  ) {
    final keys = TypedMessageKeys._(diagnostics);
    var basenames = ['messages'];
    for (final property in properties) {
      if (property.name == basenameProperty) {
        basenames = [
          for (final part in property.value.split(','))
            if (part.trim().isNotEmpty) _withoutScheme(part.trim()),
        ];
        break;
      }
    }
    if (basenames.any((base) => base.contains(r'${'))) {
      diagnostics.warnings.add(
        '$basenameProperty has a placeholder, which the build cannot '
        'resolve: no typed messages are written.',
      );
      return null;
    }
    final before = diagnostics.errors.length;
    var found = false;
    final seen = <String>{};
    for (final base in basenames) {
      found |= keys._readBase(texts, base, seen);
    }
    if (!found || diagnostics.errors.length != before) {
      return null;
    }
    keys._root.collectErrors(diagnostics);
    return diagnostics.errors.length == before ? keys._emit() : null;
  }

  static String _withoutScheme(String base) {
    for (final scheme in const ['resources:']) {
      if (base.startsWith(scheme)) {
        return base.substring(scheme.length);
      }
    }
    return base;
  }

  // Reads one base; whether any of its files exists.
  bool _readBase(Map<String, String> texts, String base, Set<String> seen) {
    final slash = base.lastIndexOf('/');
    final directory = slash == -1 ? '' : base.substring(0, slash + 1);
    final name = base.substring(slash + 1);
    final localeFile = RegExp(
      '^${RegExp.escape(directory)}${RegExp.escape(name)}_([^/]+)\\.properties\$',
    );
    final files = <String>[
      if (texts.containsKey('$base.properties')) '$base.properties',
      ...(texts.keys.where(localeFile.hasMatch).toList()..sort()),
    ];
    if (files.isEmpty) {
      return false;
    }
    // file -> key -> argument count
    final counts = <String, Map<String, int>>{};
    final defaults = <String, String>{};
    for (final file in files) {
      final Map<String, String> entries;
      try {
        entries = PropertiesParser.parse(texts[file]!);
      } on FormatException catch (e) {
        _diagnostics.errors.add('lib/resources/$file: ${e.message}');
        continue;
      }
      final fileCounts = counts[file] = {};
      for (final MapEntry(:key, :value) in entries.entries) {
        try {
          fileCounts[key] = argumentCount(value);
        } on FormatException catch (e) {
          _diagnostics.errors.add(
            'lib/resources/$file: $key: ${e.message} in "$value".',
          );
        }
        if (file == files.first) {
          defaults[key] = value;
        }
      }
    }
    final hasDefault = files.first == '$base.properties';
    final allKeys = {for (final c in counts.values) ...c.keys}.toList()..sort();
    for (final key in allKeys) {
      final having = [
        for (final file in files)
          if (counts[file]?.containsKey(key) ?? false) file,
      ];
      final reference = having.first;
      final expected = counts[reference]![key]!;
      for (final file in having.skip(1)) {
        final actual = counts[file]![key]!;
        if (actual != expected) {
          _diagnostics.errors.add(
            'lib/resources/$file: $key has $actual argument(s), '
            '$reference has $expected: the typed message needs the same '
            'number in every language.',
          );
        }
      }
      if (hasDefault && !having.contains(files.first)) {
        _diagnostics.warnings.add(
          'lib/resources/${having.join(', ')}: $key is not in ${files.first}.',
        );
      } else {
        for (final file in files) {
          if (counts.containsKey(file) && !having.contains(file)) {
            _diagnostics.warnings.add(
              'lib/resources/$file: $key is missing (it is in $reference).',
            );
          }
        }
      }
      if (seen.add(key)) {
        _add(key, expected, defaults[key] ?? '');
      }
    }
    return true;
  }

  void _add(String key, int arguments, String text) {
    var group = _root;
    final segments = key.split('.');
    final names = <String>[];
    for (final segment in segments) {
      final dart = DartNames.member(segment);
      if (dart == null) {
        _diagnostics.errors.add(
          'Message key $key: "$segment" cannot be written as a Dart name '
          '(letters, digits, - and _ only).',
        );
        return;
      }
      names.add(dart);
    }
    for (var i = 0; i < names.length - 1; i++) {
      if (group.messages.containsKey(names[i])) {
        _diagnostics.errors.add(
          'Message key $key: ${segments.take(i + 1).join('.')} is a message '
          'and also the prefix of other keys.',
        );
        return;
      }
      group = group.groups.putIfAbsent(
        names[i],
        () => _Group(
          '${group.className}${DartNames.upperFirst(names[i])}',
          segments.take(i + 1).join('.'),
        ),
      );
    }
    final leaf = names.last;
    if (group.groups.containsKey(leaf)) {
      _diagnostics.errors.add(
        'Message key $key is a message and also the prefix of other keys.',
      );
      return;
    }
    final previous = group.messages[leaf];
    if (previous != null && previous.key != key) {
      _diagnostics.errors.add(
        'Message keys ${previous.key} and $key both become '
        "'$leaf': rename one.",
      );
      return;
    }
    group.messages[leaf] = _Message(key, arguments, text);
  }

  String _emit() {
    final out = StringBuffer();
    _root.write(out);
    return out.toString();
  }

  /// The number of arguments [pattern] (a `MessageFormat` pattern) takes:
  /// the highest `{n}` index plus one, `0` without placeholders.
  /// Throws a [FormatException] for a pattern `MessageFormat` rejects
  /// (unmatched braces, a bad index, an unknown format type).
  static int argumentCount(String pattern) => _scan(pattern) + 1;

  // The highest index in [pattern], -1 when none.
  static int _scan(String pattern) {
    var highest = -1;
    var quoted = false;
    var i = 0;
    while (i < pattern.length) {
      final c = pattern[i];
      if (c == "'") {
        if (i + 1 < pattern.length && pattern[i + 1] == "'") {
          i += 2;
          continue;
        }
        quoted = !quoted;
        i++;
        continue;
      }
      if (quoted || c != '{') {
        i++;
        continue;
      }
      final end = _closingBrace(pattern, i);
      final spec = pattern.substring(i + 1, end);
      final firstComma = spec.indexOf(',');
      final indexText =
          (firstComma == -1 ? spec : spec.substring(0, firstComma)).trim();
      final index = int.tryParse(indexText);
      if (index == null || index < 0) {
        throw FormatException("Invalid argument index '$indexText'");
      }
      if (index > highest) {
        highest = index;
      }
      if (firstComma != -1) {
        final rest = spec.substring(firstComma + 1);
        final secondComma = rest.indexOf(',');
        final type = (secondComma == -1 ? rest : rest.substring(0, secondComma))
            .trim()
            .toLowerCase();
        if (!const {'number', 'date', 'time', 'choice'}.contains(type)) {
          throw FormatException("Unknown format type '$type'");
        }
        if (type == 'choice' && secondComma != -1) {
          final nested = _scan(rest.substring(secondComma + 1));
          if (nested > highest) {
            highest = nested;
          }
        }
      }
      i = end + 1;
    }
    return highest;
  }

  static int _closingBrace(String pattern, int open) {
    var depth = 0;
    var quoted = false;
    for (var i = open; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == "'") {
        quoted = !quoted;
      } else if (!quoted && c == '{') {
        depth++;
      } else if (!quoted && c == '}') {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    throw const FormatException('Unmatched braces in the pattern');
  }
}

final class _Message {
  _Message(this.key, this.arguments, this.text);

  final String key;
  final int arguments;
  final String text;
}

final class _Group {
  _Group(this.className, this.prefix);

  final String className;
  final String prefix;
  final groups = <String, _Group>{};
  final messages = <String, _Message>{};

  // Two groups with one class name (`a.bC` and `a.b.c`).
  void collectErrors(KeysDiagnostics diagnostics) {
    final names = <String, String>{};
    void visit(_Group group) {
      final previous = names[group.className];
      if (previous != null && previous != group.prefix) {
        diagnostics.errors.add(
          'Message keys under "$previous" and "${group.prefix}" both become '
          'the class ${group.className}: rename one.',
        );
      }
      names[group.className] = group.prefix;
      group.groups.values.forEach(visit);
    }

    visit(this);
  }

  void write(StringBuffer out) {
    final isRoot = prefix.isEmpty;
    out
      ..writeln(
        isRoot
            ? '/// The messages of the message files: `context.messages`.'
            : '/// The messages `$prefix.*`.',
      )
      ..writeln('final class $className {')
      ..writeln('  const $className._(this._context);')
      ..writeln('  final BuildContext _context;');
    for (final name in groups.keys.toList()..sort()) {
      final group = groups[name]!;
      out
        ..writeln('  /// The messages `${group.prefix}.*`.')
        ..writeln(
          '  ${group.className} get $name => ${group.className}._(_context);',
        );
    }
    for (final name in messages.keys.toList()..sort()) {
      final message = messages[name]!;
      final doc = message.text.replaceAll(RegExp(r'\s+'), ' ');
      final key = DartNames.literal(message.key);
      out.writeln('  /// `${message.key}`: $doc');
      if (message.arguments == 0) {
        out.writeln('  String get $name => _context.message($key);');
      } else {
        final parameters = [
          for (var i = 0; i < message.arguments; i++) 'Object? arg$i',
        ];
        final arguments = [
          for (var i = 0; i < message.arguments; i++) 'arg$i',
        ];
        out.writeln(
          '  String $name(${parameters.join(', ')}) => '
          '_context.message($key, args: [${arguments.join(', ')}]);',
        );
      }
    }
    out.writeln('}\n');
    for (final name in groups.keys.toList()..sort()) {
      groups[name]!.write(out);
    }
  }
}
