import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/did_you_mean.dart';
import 'package:dart_spring_language_server/src/index/property_index.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// A `$path` in a value: the segments and the span of the whole `$path`.
final class ThemeReference {
  /// The reference to [path], from [start] to [end] of its value.
  const ThemeReference(this.path, this.start, this.end);

  /// The segments after the `$`.
  final List<String> path;

  /// The offset of the `$` in the value.
  final int start;

  /// The offset just after the reference.
  final int end;
}

/// The `$` references of the theme value [value]; `$$` is a plain `$`.
List<ThemeReference> themeReferences(String value) {
  final result = <ThemeReference>[];
  for (final match in RegExp(
    r'\$\$|\$([A-Za-z_][A-Za-z0-9_.\-]*)',
  ).allMatches(value)) {
    final path = match.group(1);
    if (path == null) {
      continue;
    }
    var text = path;
    while (text.endsWith('.') || text.endsWith('-')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isEmpty) {
      continue;
    }
    result.add(
      ThemeReference(
        text.split('.'),
        match.start,
        match.start + 1 + text.length,
      ),
    );
  }
  return result;
}

/// The declared values of the themes of a package and its dependencies, for
/// `$` references.
final class ThemeReferences {
  /// The declarations of the themes the file [path] sees, from
  /// [properties].
  ThemeReferences(PropertyIndex properties, String path) {
    for (final entry in properties.configEntries(path)) {
      final segments = splitKey(entry.key);
      if (!isThemeKey(segments)) {
        continue;
      }
      var rest = segments.sublist(themePrefix.length);
      String? theme;
      if (rest.length >= 2 && canonicalName(rest[0]) == 'themes') {
        theme = rest[1];
        rest = rest.sublist(2);
      }
      if (rest.isEmpty) {
        continue;
      }
      declarations.add((entry, theme, rest));
      for (var i = 1; i <= rest.length; i++) {
        final key = rest.sublist(0, i).map(canonicalName).join('.');
        declared.putIfAbsent(key, () => rest.sublist(0, i));
      }
    }
  }

  /// Each theme entry, with its theme (`null` for the root) and its key
  /// without the theme's prefix.
  final declarations = <(PropertyEntry, String?, List<String>)>[];

  /// Canonical dotted path to the path as written.
  final declared = <String, List<String>>{};

  static const _sections = {
    'brightness', 'seedcolor', 'schemevariant', 'contrast', 'colors', //
    'typography', 'shape', 'elevation', 'spacing', 'visualdensity',
    'taptargetsize', 'splash', 'motion', 'components', 'tokens',
    'cupertino', 'styles', 'animations', 'background', 'loaders',
  };

  // The built-in names a reference may use without writing them.
  Iterable<List<String>> get _builtin sync* {
    for (final role in colorRoles) {
      yield ['colors', role];
    }
    for (final name in defaultShapeNames) {
      yield ['shape', name];
    }
    for (var i = 0; i < 6; i++) {
      yield ['elevation', 'level$i'];
    }
    for (final name in const ['xs', 's', 'm', 'l', 'xl']) {
      yield ['spacing', name];
    }
    for (final name in const ['short', 'medium', 'long']) {
      yield ['motion', 'durations', name];
    }
  }

  List<List<String>> _candidates(List<String> reference) => [
    reference,
    if (!_sections.contains(canonicalName(reference.first)))
      ['tokens', ...reference],
  ];

  String _key(List<String> segments) => segments.map(canonicalName).join('.');

  late final Set<String> _builtinKeys = {
    for (final path in _builtin)
      for (var i = 1; i <= path.length; i++) _key(path.sublist(0, i)),
  };

  /// Whether [reference] is declared or built in.
  bool exists(List<String> reference) {
    for (final candidate in _candidates(reference)) {
      final key = _key(candidate);
      if (declared.containsKey(key) || _builtinKeys.contains(key)) {
        return true;
      }
    }
    return false;
  }

  /// The declared or built-in name closest to [reference], for a
  /// did-you-mean.
  String? closest(List<String> reference) {
    final all = <String>{
      for (final path in declared.values)
        if (_isTokenPath(path)) path.skip(1).join('.') else path.join('.'),
      for (final path in _builtin) path.join('.'),
    }.toList();
    // A leaf for a leaf: `neon.cyna` means `neon.cyan`, not the group.
    final same = [
      for (final name in all)
        if (name.split('.').length == reference.length) name,
    ];
    return didYouMean(reference.join('.'), same) ??
        didYouMean(reference.join('.'), all);
  }

  static bool _isTokenPath(List<String> path) =>
      path.first.toLowerCase() == 'tokens' && path.length > 1;

  /// Where the reference is declared: the entries of its own theme, else of
  /// the root, else of any theme.
  List<SourceRange> definitions(List<String> reference, String? theme) {
    final wanted = {for (final c in _candidates(reference)) _key(c)};
    final matches = [
      for (final (entry, entryTheme, rest) in declarations)
        for (var i = 1; i <= rest.length; i++)
          if (wanted.contains(_key(rest.sublist(0, i))))
            (entry, entryTheme, i == rest.length),
    ];
    // Prefer the exact key; a group only when nothing is exact.
    var exact = [
      for (final m in matches)
        if (m.$3) m,
    ];
    if (exact.isEmpty) {
      exact = matches;
    }
    List<(PropertyEntry, String?, bool)> pick(bool Function(String?) test) => [
      for (final m in exact)
        if (test(m.$2)) m,
    ];
    var chosen = pick(
      (t) =>
          t != null &&
          theme != null &&
          canonicalName(t) == canonicalName(theme),
    );
    if (chosen.isEmpty) {
      chosen = pick((t) => t == null);
    }
    if (chosen.isEmpty) {
      chosen = exact;
    }
    final seen = <String>{};
    return [
      for (final (entry, _, _) in chosen)
        if (seen.add('${entry.path}:${entry.line}'))
          SourceRange(
            entry.path,
            entry.line,
            entry.keyStart,
            entry.line,
            entry.keyEnd,
          ),
    ];
  }

  /// The hover of [reference]: its values in each theme.
  String hover(List<String> reference) {
    final name = reference.join('.');
    final sites = definitions(reference, null);
    final lines = <String>['**`\$$name`**'];
    if (sites.isEmpty) {
      final builtin = exists(reference);
      lines.add(
        builtin
            ? 'A Material role or default of the palette (made from the seed).'
            : 'Not declared in any theme of this package or its dependencies.',
      );
      return lines.join('\n');
    }
    lines.add('');
    final wanted = {for (final c in _candidates(reference)) _key(c)};
    for (final (entry, theme, rest) in declarations) {
      if (wanted.contains(_key(rest))) {
        lines.add(
          '- `${entry.fileName}`'
          "${theme == null ? '' : ' (theme `$theme`)'}: `${entry.value}`",
        );
      }
    }
    return lines.join('\n');
  }

  /// Names below [parent] (a path without the `$`): the sections, tokens,
  /// roles and declared keys.
  List<Completion> complete(List<String> parent) {
    final names = <String, (int, String)>{};
    void add(String name, int kind, String detail) =>
        names.putIfAbsent(name, () => (kind, detail));
    final candidates = parent.isEmpty ? [<String>[]] : _candidates(parent);
    for (final base in candidates) {
      final baseKey = base.map(canonicalName).toList();
      void visit(List<String> path, String detail) {
        if (path.length <= base.length) {
          return;
        }
        for (var i = 0; i < base.length; i++) {
          if (canonicalName(path[i]) != baseKey[i]) {
            return;
          }
        }
        final isLeaf = path.length == base.length + 1;
        add(path[base.length], isLeaf ? 12 : 9, detail);
      }

      for (final path in declared.values) {
        visit(path, 'declared');
      }
      for (final path in _builtin) {
        visit(path, 'built in');
      }
    }
    if (parent.isEmpty) {
      // `$brand.`: the groups of tokens may drop the `tokens.`.
      for (final path in declared.values) {
        if (path.length > 2 && path.first.toLowerCase() == 'tokens') {
          add(path[1], 9, 'token group');
        }
      }
    }
    return [
      for (final MapEntry(key: name, value: (kind, detail)) in names.entries)
        Completion(name, kind: kind, detail: detail),
    ];
  }
}
