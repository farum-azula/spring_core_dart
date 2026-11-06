part of 'config_editor.dart';

// The keys each built-in loader kind takes (the starter's
// `ThemeLoaderSpec`), besides the keys every loader has.
const _builtInLoaderKeys = {
  'spinner': ['color', 'size', 'stroke', 'track', 'animation'],
  'dots': ['color', 'size', 'count', 'gap', 'animation'],
  'pulse': ['color', 'size', 'animation'],
  'bar': ['color', 'track', 'height', 'width', 'radius', 'animation'],
  'skeleton': ['base', 'highlight', 'radius', 'shimmer'],
};

// The keys every loader has, as the generator's `loaderOwnKeys`.
const _loaderCommonKeys = ['kind', 'phases', 'tracks', 'web', 'web-sha256'];

// Loaders and the splash in the editor: the keys a kind takes, the names
// `splash.loader` and `splash.animation` refer to, and the `web:` file.
extension _LoaderEditor on ConfigEditor {
  // The key without `spring.flutter.theme` and `themes.<name>`.
  ({String? theme, List<String> rest})? _themeRelative(List<String> segments) {
    if (!ConfigEditor._isTheme(segments)) {
      return null;
    }
    var rest = segments.sublist(themePrefix.length);
    String? theme;
    if (rest.length >= 2 && canonicalName(rest[0]) == 'themes') {
      theme = rest[1];
      rest = rest.sublist(2);
    }
    return (theme: theme, rest: rest);
  }

  // The keys a kind takes, canonical, or `null` when unknown or not
  // listed (a kind of the app's own without `props`).
  List<String>? _loaderKindKeys(String path, String kind) {
    final canon = canonicalName(kind);
    if (_builtInLoaderKeys[canon] case final keys?) {
      return keys;
    }
    for (final custom in workspace.metadataFor(path).loaderKinds) {
      if (canonicalName(custom.name) == canon) {
        return custom.props;
      }
    }
    return null;
  }

  // `loaders.<name>.kind` of each theme of [keys], by `theme|name`.
  Map<String, String> _loaderKinds(List<_Key> keys) {
    final result = <String, String>{};
    for (final key in keys) {
      final rel = _themeRelative(key.segments);
      if (rel == null ||
          key.value == null ||
          rel.rest.length != 3 ||
          canonicalName(rel.rest[0]) != 'loaders' ||
          canonicalName(rel.rest[2]) != 'kind') {
        continue;
      }
      result['${rel.theme}|${canonicalName(rel.rest[1])}'] = key.value!;
    }
    return result;
  }

  // The names declared below [section] (`loaders`, `animations`) in any
  // theme of the package and its dependencies.
  List<String> _declaredNames(String path, String section) {
    final names = <String>{};
    for (final (_, _, rest) in _RefIndex(workspace, path).declarations) {
      if (rest.length >= 2 && canonicalName(rest[0]) == section) {
        names.add(rest[1]);
      }
    }
    return names.toList()..sort();
  }

  void _checkLoaders(String path, List<_Key> keys, List<Problem> problems) {
    final kinds = _loaderKinds(keys);
    final reported = <String>{};
    for (final key in keys) {
      final rel = _themeRelative(key.segments);
      if (rel == null || rel.rest.isEmpty) {
        continue;
      }
      final rest = rel.rest;
      final head = canonicalName(rest[0]);
      if (head == 'loaders' && rest.length >= 3) {
        _checkLoaderKey(path, key, rel.theme, rest, kinds, reported, problems);
      }
      if (head == 'loaders' &&
          rest.length == 3 &&
          canonicalName(rest[2]) == 'web' &&
          key.value != null) {
        _checkWebFile(path, key, problems);
      }
      if (head == 'splash' && rest.length == 2 && key.value != null) {
        final field = canonicalName(rest[1]);
        if (field == 'loader') {
          _checkNameOf(path, key, 'loaders', 'loader', problems);
        } else if (field == 'animation') {
          _checkNameOf(path, key, 'animations', 'animation', problems);
        }
      }
    }
  }

  void _checkLoaderKey(
    String path,
    _Key key,
    String? theme,
    List<String> rest,
    Map<String, String> kinds,
    Set<String> reported,
    List<Problem> problems,
  ) {
    final kind = kinds['$theme|${canonicalName(rest[1])}'];
    if (kind == null) {
      return;
    }
    final allowed = _loaderKindKeys(path, kind);
    if (allowed == null) {
      return;
    }
    final name = rest[2];
    final index = key.segments.length - rest.length + 2 - key.parentCount;
    if (index < 0 || index >= key.spans.length) {
      // The segment is on a line above, which reports it.
      return;
    }
    final known = [..._loaderCommonKeys, ...allowed];
    if (known.any((k) => canonicalName(k) == canonicalName(name)) ||
        !reported.add('${key.line}|$name')) {
      return;
    }
    final (from, to) = key.spans[index];
    final guess = didYouMean(name, known);
    problems.add(
      Problem(
        ConfigEditor._range(path, key.line, from, to),
        "'$name' is not a key of a '$kind' loader. It takes: "
        '${known.join(', ')}'
        "${guess == null ? '' : ". Did you mean '$guess'?"}",
        error: true,
      ),
    );
  }

  // `splash.loader` and `splash.animation` name something declared.
  void _checkNameOf(
    String path,
    _Key key,
    String section,
    String what,
    List<Problem> problems,
  ) {
    final value = key.value!;
    if (value.isEmpty || value.contains(r'$') || value.contains('#{')) {
      return;
    }
    final names = _declaredNames(path, section);
    if (names.any((n) => canonicalName(n) == canonicalName(value))) {
      return;
    }
    final guess = didYouMean(value, names);
    problems.add(
      Problem(
        ConfigEditor._range(path, key.line, key.valueStart, key.valueEnd),
        "'$value' is no $what ($section.<name>) of any theme"
        "${guess == null ? '' : ". Did you mean '$guess'?"}",
        error: true,
      ),
    );
  }

  // The `web:` file of a loader: a path below the app's directory.
  void _checkWebFile(String path, _Key key, List<Problem> problems) {
    final value = key.value!;
    if (value.isEmpty || value.contains(r'${')) {
      return;
    }
    final range = ConfigEditor._range(
      path,
      key.line,
      key.valueStart,
      key.valueEnd,
    );
    if (value.startsWith('/') ||
        RegExp(r'(^|[\\/])\.\.([\\/]|$)').hasMatch(value) ||
        RegExp(r'^[A-Za-z]:|\\').hasMatch(value)) {
      problems.add(
        Problem(
          range,
          "'$value' must be a path below the app's directory "
          '(no .. and not absolute)',
          error: true,
        ),
      );
      return;
    }
    if (_webFile(path, value) == null) {
      problems.add(
        Problem(
          range,
          "The file '$value' does not exist (the path is relative to the "
          "app's directory, or `lib/resources/` of a package it uses)",
          error: true,
        ),
      );
    }
  }

  // The file of a `web:` path: in the app's directory, else in
  // `lib/resources/` of a dependency (a library shipping its loader).
  String? _webFile(String path, String value) {
    final view = workspace.metadataFor(path);
    for (final root in [
      workspace.packageRootOf(path),
      for (final root in view.packageRoots.values) '$root/lib/resources',
    ]) {
      final file = File('$root/$value');
      if (file.existsSync()) {
        return file.path;
      }
    }
    return null;
  }

  // Completion of the value of `splash.loader`, `splash.animation`, `kind`
  // and `web`; `null` when the key is none of them.
  CompletionResult? _loaderValueCompletion(
    String path,
    int line,
    int column,
    List<String> segments,
    String valueText,
    int valueStart,
  ) {
    final rel = _themeRelative(segments);
    if (rel == null || rel.rest.isEmpty) {
      return null;
    }
    final rest = rel.rest.map(canonicalName).toList();
    final word = RegExp(r'[A-Za-z0-9_.\-/$]*$').firstMatch(valueText)!;
    final from = valueStart + word.start;
    List<Completion>? items;
    if (rest.length == 2 && rest[0] == 'splash' && rest[1] == 'loader') {
      items = [
        for (final name in _declaredNames(path, 'loaders'))
          Completion(name, kind: 20, detail: 'loader'),
      ];
    } else if (rest.length == 2 &&
        rest[0] == 'splash' &&
        rest[1] == 'animation') {
      items = [
        for (final name in _declaredNames(path, 'animations'))
          Completion(name, kind: 20, detail: 'animation'),
      ];
    } else if (rest.length == 3 && rest[0] == 'loaders' && rest[2] == 'web') {
      items = [
        for (final file in _webFiles(path))
          Completion(file, kind: 17, detail: 'web page loader'),
      ];
    }
    return items == null || items.isEmpty
        ? null
        : CompletionResult(
            ConfigEditor._range(path, line, from, column),
            items,
          );
  }

  // The `.html` files below `web/` of the app and below `lib/resources/`
  // of its dependencies, as `web:` paths.
  List<String> _webFiles(String path) {
    final result = <String>{};
    void scan(String base) {
      final directory = Directory(base);
      if (!directory.existsSync()) {
        return;
      }
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.html')) {
          final relative = entity.path.substring(base.length + 1);
          if (relative.startsWith('web/') ||
              relative.startsWith(r'web\') ||
              base != workspace.packageRootOf(path)) {
            result.add(relative.replaceAll(r'\', '/'));
          }
        }
      }
    }

    final root = workspace.packageRootOf(path);
    scan(root);
    for (final dependency in workspace.metadataFor(path).packageRoots.values) {
      scan('$dependency/lib/resources');
    }
    return result.where((p) => !p.startsWith('build/')).toList()..sort();
  }

  // The keys a loader takes, once its `kind` is written: the kind's own,
  // `kind`, `phases` and `web`. `null` when the parents are no loader or
  // the kind is not known.
  CompletionResult? _loaderKeyCompletion(
    String path,
    int line,
    int start,
    int column,
    List<String> parents,
    List<_Key> keys,
    bool yaml,
    int indent,
    bool hasColon,
  ) {
    final rel = _themeRelative(parents);
    if (rel == null ||
        rel.rest.length != 2 ||
        canonicalName(rel.rest[0]) != 'loaders') {
      return null;
    }
    final kind = _loaderKinds(
      keys,
    )['${rel.theme}|${canonicalName(rel.rest[1])}'];
    if (kind == null) {
      return null;
    }
    final allowed = _loaderKindKeys(path, kind);
    if (allowed == null) {
      return null;
    }
    final schema = workspace.schemaFor(path);
    final base = [
      ...themePrefix,
      if (rel.theme != null) ...['themes', rel.theme!],
    ];
    return CompletionResult(ConfigEditor._range(path, line, start, column), [
      for (final name in [..._loaderCommonKeys, ...allowed])
        () {
          final node = schema.nodeAt([...base, 'loaders', '*', name]);
          final group =
              node != null &&
              (node.children.isNotEmpty || node.wildcard != null) &&
              node.prop == null;
          return Completion(
            name,
            kind: group ? 9 : 10,
            detail: node?.prop == null ? null : _detail(node!.prop!),
            documentation: node?.prop == null
                ? null
                : propertyHover(name, node!.prop!),
            insertText: !yaml || hasColon
                ? name
                : group
                ? '$name:\n${' ' * (indent + 2)}'
                : '$name: ',
          );
        }(),
    ]);
  }

  // Go to `loaders.<name>` or `animations.<name>` from `splash.loader` /
  // `splash.animation`, and to the file of `web:`.
  List<SourceRange> _loaderDefinition(String path, _Key key) {
    final rel = _themeRelative(key.segments);
    if (rel == null || key.value == null) {
      return const [];
    }
    final rest = rel.rest.map(canonicalName).toList();
    final value = key.value!.trim();
    if (rest.length == 3 && rest[0] == 'loaders' && rest[2] == 'web') {
      final file = _webFile(path, value);
      return file == null ? const [] : [SourceRange(file, 0, 0, 0, 0)];
    }
    final String section;
    if (rest.length == 2 && rest[0] == 'splash' && rest[1] == 'loader') {
      section = 'loaders';
    } else if (rest.length == 2 &&
        rest[0] == 'splash' &&
        rest[1] == 'animation') {
      section = 'animations';
    } else {
      return const [];
    }
    final wanted = canonicalName(value);
    final matches = [
      for (final (entry, theme, rest) in _RefIndex(
        workspace,
        path,
      ).declarations)
        if (rest.length >= 2 &&
            canonicalName(rest[0]) == section &&
            canonicalName(rest[1]) == wanted)
          (entry, theme),
    ];
    // The theme of the key first, then the root, then any.
    List<(PropertyEntry, String?)> pick(bool Function(String?) test) => [
      for (final m in matches)
        if (test(m.$2)) m,
    ];
    var chosen = pick(
      (t) =>
          t != null &&
          rel.theme != null &&
          canonicalName(t) == canonicalName(rel.theme!),
    );
    if (chosen.isEmpty) {
      chosen = pick((t) => t == null);
    }
    if (chosen.isEmpty) {
      chosen = matches;
    }
    // One place per file and theme: the first line of the loader.
    final first = <String, PropertyEntry>{};
    for (final (entry, theme) in chosen) {
      final id = '${entry.path}|$theme';
      final known = first[id];
      if (known == null || entry.line < known.line) {
        first[id] = entry;
      }
    }
    return [
      for (final entry in first.values)
        SourceRange(
          entry.path,
          entry.line,
          entry.keyStart,
          entry.line,
          entry.keyEnd,
        ),
    ];
  }
}
