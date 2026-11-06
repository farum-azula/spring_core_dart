// The fields mirror the metadata format (roadmap/spring_metadata.md).
// ignore_for_file: public_member_api_docs
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Where a package keeps its Spring metadata, relative to its root.
const metadataFile = 'lib/spring_gen/spring_metadata.json';

/// A configuration property of the metadata (`properties`).
final class MetaProperty {
  const MetaProperty({
    required this.name,
    required this.type,
    this.description,
    this.defaultValue,
    this.deprecated,
    this.source,
    this.line,
    this.className,
    this.package = '',
  });

  factory MetaProperty.fromJson(Map<String, Object?> json, String package) =>
      MetaProperty(
        name: json['name']! as String,
        type: (json['type'] as String?) ?? 'String',
        description: json['description'] as String?,
        defaultValue: json['default'],
        deprecated: json['deprecated'],
        source: json['source'] as String?,
        line: json['line'] as int?,
        className: json['class'] as String?,
        package: package,
      );

  final String name;
  final String type;
  final String? description;
  final Object? defaultValue;
  final Object? deprecated;
  final String? source;
  final int? line;
  final String? className;
  final String package;
}

/// A hint of the metadata (`hints`): value suggestions, a provider, a
/// range and warnings for one property name (which may end in `.*`).
final class MetaHint {
  const MetaHint({
    required this.name,
    this.values = const [],
    this.provider,
    this.range,
    this.warn = const [],
  });

  factory MetaHint.fromJson(Map<String, Object?> json) => MetaHint(
    name: json['name']! as String,
    values: [
      for (final value in (json['values'] as List?) ?? const [])
        if (value is Map)
          (
            '${value['value']}',
            value['description'] as String?,
          )
        else
          ('$value', null),
    ],
    provider: json['provider'] as String?,
    range: switch (json['range']) {
      [final num low, final num high] => (low, high),
      _ => null,
    },
    warn: [
      for (final warning in (json['warn'] as List?) ?? const [])
        if (warning is Map)
          (
            [for (final v in (warning['values'] as List?) ?? const []) '$v'],
            (warning['message'] as String?) ?? 'not recommended',
          ),
    ],
  );

  final String name;

  /// The suggested values with their descriptions.
  final List<(String, String?)> values;

  /// A provider that computes the values (`profiles`).
  final String? provider;
  final (num, num)? range;

  /// Values that work but deserve a warning, with the message.
  final List<(List<String>, String)> warn;
}

/// A member SpEL can reach on a bean.
final class MetaMember {
  const MetaMember(this.name, this.kind, this.type, this.parameters);

  factory MetaMember.fromJson(Map<String, Object?> json) => MetaMember(
    json['name']! as String,
    (json['kind'] as String?) ?? 'getter',
    (json['type'] as String?) ?? 'dynamic',
    [for (final p in (json['parameters'] as List?) ?? const []) '$p'],
  );

  final String name;
  final String kind;
  final String type;
  final List<String> parameters;

  /// One line for hovers: `double total (getter)`.
  String get summary => kind == 'method'
      ? '$type $name(${parameters.join(', ')}) (method)'
      : '$type $name ($kind)';
}

/// One injection point of a bean in the metadata.
final class MetaInject {
  const MetaInject(this.parameter, this.type, this.qualifier);
  final String parameter;
  final String type;
  final String? qualifier;
}

/// A bean of the metadata (`beans`).
final class MetaBean {
  const MetaBean({
    required this.name,
    required this.type,
    required this.types,
    required this.scope,
    required this.primary,
    required this.qualifiers,
    required this.profiles,
    required this.conditions,
    required this.source,
    required this.line,
    required this.injects,
    required this.members,
    required this.package,
  });

  factory MetaBean.fromJson(Map<String, Object?> json, String package) {
    List<String> strings(Object? value) => [
      for (final v in (value as List?) ?? const []) '$v',
    ];
    final type = (json['type'] as String?) ?? '';
    return MetaBean(
      name: json['name']! as String,
      type: type,
      types: {type, ...strings(json['types'])},
      scope: (json['scope'] as String?) ?? 'singleton',
      primary: json['primary'] == true,
      qualifiers: strings(json['qualifiers']),
      profiles: strings(json['profiles']),
      conditions: strings(json['conditions']),
      source: json['source'] as String?,
      line: json['line'] as int?,
      injects: [
        for (final i in (json['injects'] as List?) ?? const [])
          if (i is Map)
            MetaInject(
              '${i['parameter']}',
              '${i['type']}',
              i['qualifier'] as String?,
            ),
      ],
      members: [
        for (final m in (json['members'] as List?) ?? const [])
          if (m is Map) MetaMember.fromJson(m.cast<String, Object?>()),
      ],
      package: package,
    );
  }

  final String name;
  final String type;
  final Set<String> types;
  final String scope;
  final bool primary;
  final List<String> qualifiers;
  final List<String> profiles;
  final List<String> conditions;
  final String? source;
  final int? line;
  final List<MetaInject> injects;
  final List<MetaMember> members;
  final String package;
}

/// A property of an entity of the metadata (`entities[].properties`).
final class MetaEntityProperty {
  const MetaEntityProperty({
    required this.name,
    required this.type,
    required this.kind,
    this.column,
    this.relationEntity,
    this.relationId,
    this.source,
    this.line,
  });

  factory MetaEntityProperty.fromJson(Map<String, Object?> json) {
    final relation = (json['relation'] as Map?)?.cast<String, Object?>();
    return MetaEntityProperty(
      name: json['name']! as String,
      type: (json['type'] as String?) ?? 'dynamic',
      kind: (json['kind'] as String?) ?? 'column',
      column: json['column'] as String?,
      relationEntity: relation?['entity'] as String?,
      relationId: relation?['id'] as String?,
      source: json['source'] as String?,
      line: json['line'] as int?,
    );
  }

  final String name;
  final String type;

  /// `column`, `transient` or `collection`.
  final String kind;

  /// The column's name; `null` for a property without a column, or when the
  /// application's own naming strategy decides.
  final String? column;

  /// For a reference to another aggregate: its entity and its id type.
  final String? relationEntity;
  final String? relationId;
  final String? source;
  final int? line;
}

/// An entity (`@Table` class) of the metadata (`entities`).
final class MetaEntity {
  const MetaEntity({
    required this.className,
    required this.properties,
    this.table,
    this.id,
    this.source,
    this.line,
    this.package = '',
  });

  factory MetaEntity.fromJson(Map<String, Object?> json, String package) =>
      MetaEntity(
        className: json['class']! as String,
        table: json['table'] as String?,
        id: json['id'] as String?,
        source: json['source'] as String?,
        line: json['line'] as int?,
        package: package,
        properties: [
          for (final p in (json['properties'] as List?) ?? const [])
            if (p is Map)
              MetaEntityProperty.fromJson(p.cast<String, Object?>()),
        ],
      );

  final String className;
  final String? table;
  final String? id;
  final String? source;
  final int? line;
  final String package;
  final List<MetaEntityProperty> properties;
}

/// A method of a repository in the metadata: one the generated class
/// writes (the CRUD methods of the starter are not listed).
final class MetaRepositoryMethod {
  const MetaRepositoryMethod({
    required this.name,
    required this.kind,
    required this.parameters,
    this.query,
    this.countQuery,
    this.line,
  });

  factory MetaRepositoryMethod.fromJson(Map<String, Object?> json) =>
      MetaRepositoryMethod(
        name: json['name']! as String,
        kind: (json['kind'] as String?) ?? 'derived',
        query: json['query'] as String?,
        countQuery: json['countQuery'] as String?,
        line: json['line'] as int?,
        parameters: [
          for (final p in (json['parameters'] as List?) ?? const [])
            if (p is Map) ('${p['name']}', '${p['type']}'),
        ],
      );

  final String name;

  /// `query` (a `@Query`), `derived` or `locked`.
  final String kind;
  final String? query;
  final String? countQuery;
  final int? line;

  /// Each parameter's name and type.
  final List<(String, String)> parameters;
}

/// A repository interface of the metadata (`repositories`).
final class MetaRepository {
  const MetaRepository({
    required this.name,
    required this.entity,
    required this.methods,
    this.id,
    this.source,
    this.line,
  });

  factory MetaRepository.fromJson(Map<String, Object?> json) => MetaRepository(
    name: json['name']! as String,
    entity: json['entity']! as String,
    id: json['id'] as String?,
    source: json['source'] as String?,
    line: json['line'] as int?,
    methods: [
      for (final m in (json['methods'] as List?) ?? const [])
        if (m is Map) MetaRepositoryMethod.fromJson(m.cast<String, Object?>()),
    ],
  );

  final String name;
  final String entity;
  final String? id;
  final String? source;
  final int? line;
  final List<MetaRepositoryMethod> methods;
}

/// A loader kind of the app's own (`@ThemeLoaderKind('doors')`), from
/// `loaderKinds` of a metadata file.
final class MetaLoaderKind {
  const MetaLoaderKind({
    required this.name,
    required this.package,
    this.className,
    this.source,
    this.line,
    this.props,
  });

  factory MetaLoaderKind.fromJson(Map<String, Object?> json, String package) =>
      MetaLoaderKind(
        name: json['name']! as String,
        package: package,
        className: json['class'] as String?,
        source: json['source'] as String?,
        line: json['line'] as int?,
        props: (json['props'] as List?)?.map((e) => '$e').toList(),
      );

  /// The value of `kind` in a theme.
  final String name;

  /// The package that declares it.
  final String package;

  /// The painter or widget class.
  final String? className;

  /// `package:` URI of the library of the class.
  final String? source;
  final int? line;

  /// The keys the themes of its package give its loaders, when known.
  final List<String>? props;
}

/// A theme property of the metadata (`theme.properties`), named relative
/// to a theme (`components.app-bar.background-color`).
final class MetaThemeProperty {
  const MetaThemeProperty({
    required this.name,
    required this.type,
    this.states = false,
    this.values = const [],
    this.description,
    this.flutter,
    this.defaultValue,
    this.scope,
    this.open = false,
  });

  factory MetaThemeProperty.fromJson(Map<String, Object?> json) =>
      MetaThemeProperty(
        name: json['name']! as String,
        type: (json['type'] as String?) ?? 'text',
        states: json['states'] == true,
        values: [for (final v in (json['values'] as List?) ?? const []) '$v'],
        description: json['description'] as String?,
        flutter: json['flutter'] as String?,
        defaultValue: json['default'],
        scope: json['scope'] as String?,
        open: json['open'] == true,
      );

  final String name;
  final String type;

  /// `root` (only at the root of the theme), `theme` (only inside
  /// `themes.<name>`) or `null` (both).
  final String? scope;

  /// Anything may follow the key (tokens, styles).
  final bool open;
  final bool states;
  final List<String> values;
  final String? description;
  final String? flutter;
  final Object? defaultValue;
}

/// The metadata file of one package, parsed.
/// A screen of `spring_boot_starter_flutter_navigation` (`routes` of a
/// metadata file): its path pattern, name and class.
final class MetaRoute {
  /// The screen at [path].
  const MetaRoute({
    required this.path,
    this.name,
    this.className,
    this.source,
    this.title,
  });

  /// The route of [json].
  factory MetaRoute.fromJson(Map<String, Object?> json) => MetaRoute(
    path: (json['path'] as String?) ?? '',
    name: json['name'] as String?,
    className: json['class'] as String?,
    source: json['source'] as String?,
    title: json['title'] as String?,
  );

  /// The path pattern (`/catalog/books/{isbn}`).
  final String path;

  /// The route's name.
  final String? name;

  /// The screen's class.
  final String? className;

  /// Where it is declared (`package:app/book_page.dart#BookPage`).
  final String? source;

  /// Its title.
  final String? title;

  /// Whether [address] (a path without query) is this route's: variables
  /// match one segment, `{*rest}` the rest.
  bool matches(String address) {
    final buffer = StringBuffer('^');
    var last = 0;
    for (final match in RegExp(r'\{(\*?)[^}]*\}').allMatches(path)) {
      buffer
        ..write(RegExp.escape(path.substring(last, match.start)))
        ..write(match.group(1)!.isEmpty ? '[^/]+' : '.*');
      last = match.end;
    }
    buffer
      ..write(RegExp.escape(path.substring(last)))
      ..write(r'$');
    return RegExp(buffer.toString()).hasMatch(address);
  }
}

final class SpringMetadata {
  SpringMetadata._({
    required this.package,
    required this.root,
    required this.properties,
    required this.hints,
    required this.beans,
    required this.entities,
    required this.repositories,
    required this.profiles,
    required this.themeTypes,
    required this.themeProperties,
    required this.loaderKinds,
    this.routes = const [],
    this.shellBranches = const [],
  });

  /// Parses [json] read from the package at [root]. Throws on a document
  /// that is not an object.
  factory SpringMetadata.parse(String root, Map<String, Object?> json) {
    final package = (json['package'] as String?) ?? '';
    final theme = (json['theme'] as Map?)?.cast<String, Object?>();
    return SpringMetadata._(
      package: package,
      root: root,
      properties: [
        for (final p in (json['properties'] as List?) ?? const [])
          if (p is Map)
            MetaProperty.fromJson(p.cast<String, Object?>(), package),
      ],
      hints: [
        for (final h in (json['hints'] as List?) ?? const [])
          if (h is Map) MetaHint.fromJson(h.cast<String, Object?>()),
      ],
      beans: [
        for (final b in (json['beans'] as List?) ?? const [])
          if (b is Map) MetaBean.fromJson(b.cast<String, Object?>(), package),
      ],
      entities: [
        for (final e in (json['entities'] as List?) ?? const [])
          if (e is Map) MetaEntity.fromJson(e.cast<String, Object?>(), package),
      ],
      repositories: [
        for (final r in (json['repositories'] as List?) ?? const [])
          if (r is Map) MetaRepository.fromJson(r.cast<String, Object?>()),
      ],
      profiles: [
        for (final p in (json['profiles'] as List?) ?? const []) '$p',
      ],
      loaderKinds: [
        for (final k in (json['loaderKinds'] as List?) ?? const [])
          if (k is Map)
            MetaLoaderKind.fromJson(k.cast<String, Object?>(), package),
      ],
      routes: [
        for (final r in (json['routes'] as List?) ?? const [])
          if (r is Map) MetaRoute.fromJson(r.cast<String, Object?>()),
      ],
      shellBranches: [
        for (final shell in (json['shells'] as List?) ?? const [])
          if (shell is Map)
            for (final branch in (shell['branches'] as List?) ?? const [])
              if (branch is String) branch,
      ],
      themeTypes:
          (theme?['types'] as Map?)?.cast<String, Object?>() ?? const {},
      themeProperties: [
        for (final p in (theme?['properties'] as List?) ?? const [])
          if (p is Map) MetaThemeProperty.fromJson(p.cast<String, Object?>()),
      ],
    );
  }

  final String package;

  /// The package's root directory.
  final String root;
  final List<MetaProperty> properties;
  final List<MetaHint> hints;
  final List<MetaBean> beans;

  /// The `@Table` classes of the data layer.
  final List<MetaEntity> entities;

  /// The repository interfaces of the data layer.
  final List<MetaRepository> repositories;
  final List<String> profiles;

  /// `theme.types`, kept as JSON (the schema of the color object and such).
  final Map<String, Object?> themeTypes;
  final List<MetaThemeProperty> themeProperties;

  /// The `@ThemeLoaderKind` classes of the package.
  final List<MetaLoaderKind> loaderKinds;

  /// The screens of the package (`spring_boot_starter_flutter_navigation`).
  final List<MetaRoute> routes;

  /// The branches of the package's `@RouteShell`s (`/catalog`, `/more`).
  final List<String> shellBranches;
}

/// The metadata that applies to one package: its own and that of all its
/// dependencies, with the packages that should have metadata and do not.
final class MetadataView {
  MetadataView({
    required this.packageName,
    required this.packageRoot,
    required this.metadata,
    required this.packageRoots,
    required this.missing,
    required this.version,
  });

  /// A view with nothing in it: no `package_config.json` was found.
  factory MetadataView.empty() => MetadataView(
    packageName: null,
    packageRoot: null,
    metadata: const [],
    packageRoots: const {},
    missing: const [],
    version: 0,
  );

  final String? packageName;
  final String? packageRoot;

  /// The metadata of the package and its dependencies that have a file.
  final List<SpringMetadata> metadata;

  /// Package name to root directory, for the whole closure.
  final Map<String, String> packageRoots;

  /// Spring packages of the closure without a metadata file: the app's own
  /// (run build_runner) or a dependency published before metadata existed.
  final List<String> missing;

  /// Changes whenever any metadata file changed, so caches built from the
  /// view can be dropped.
  final int version;

  bool get isEmpty => metadata.isEmpty;

  /// Whether the metadata of every Spring package of the closure is there.
  bool get complete => missing.isEmpty;

  /// The path of `package:name/path` in the closure, or `null`.
  String? resolve(String? uri) {
    if (uri == null || !uri.startsWith('package:')) {
      return null;
    }
    final slash = uri.indexOf('/');
    if (slash < 0) {
      return null;
    }
    final root = packageRoots[uri.substring('package:'.length, slash)];
    return root == null ? null : '$root/lib/${uri.substring(slash + 1)}';
  }

  Iterable<MetaBean> get beans => metadata.expand((m) => m.beans);
  Iterable<MetaEntity> get entities => metadata.expand((m) => m.entities);
  Iterable<MetaRepository> get repositories =>
      metadata.expand((m) => m.repositories);
  Iterable<MetaProperty> get properties => metadata.expand((m) => m.properties);
  Iterable<MetaHint> get hints => metadata.expand((m) => m.hints);

  /// The loader kinds of the app's own that the package and its
  /// dependencies declare.
  List<MetaLoaderKind> get loaderKinds => [
    for (final m in metadata) ...m.loaderKinds,
  ];

  /// The profile names the metadata lists.
  Set<String> get profiles => {for (final m in metadata) ...m.profiles};

  /// The screens of the package and its dependencies.
  List<MetaRoute> get routes => [for (final m in metadata) ...m.routes];

  /// The branches of the shells of the package and its dependencies.
  Set<String> get shellBranches => {
    for (final m in metadata) ...m.shellBranches,
  };

  List<MetaThemeProperty> get themeProperties => [
    for (final m in metadata) ...m.themeProperties,
  ];

  /// `theme.types` of the first package that has them.
  Map<String, Object?> get themeTypes {
    for (final m in metadata) {
      if (m.themeTypes.isNotEmpty) {
        return m.themeTypes;
      }
    }
    return const {};
  }
}

/// Finds and loads the Spring metadata of the packages of a workspace.
///
/// For a file, the package is the nearest directory with a `pubspec.yaml`;
/// `.dart_tool/package_config.json` (searched upwards, as the pub workspace
/// keeps it at the top) says where each package lives; the pubspecs give
/// the dependencies, followed to the end. Every package's
/// `lib/spring_gen/spring_metadata.json` is read when its modification time
/// changes, so a new build shows without restarting the server.
final class MetadataStore {
  final _configs = <String, _Config>{};
  final _loaded = <String, (DateTime, SpringMetadata?)>{};
  final _pubspecs = <String, (DateTime, _Pubspec)>{};
  final _views = <String, (int, MetadataView)>{};
  var _version = 1;

  /// Stats the files again; throttled by the caller.
  void refresh() {
    var changed = false;
    for (final config in [..._configs.values]) {
      final file = File(config.path);
      if (!file.existsSync() || file.lastModifiedSync() != config.modified) {
        _configs.remove(config.path);
        changed = true;
      }
    }
    for (final MapEntry<String, (DateTime, SpringMetadata?)>(
          key: root,
          value: loaded,
        )
        in [..._loaded.entries]) {
      final file = File('$root/$metadataFile');
      final now = file.existsSync() ? file.lastModifiedSync() : null;
      if (now == null ? loaded.$2 != null : now != loaded.$1) {
        _loaded.remove(root);
        changed = true;
      }
    }
    if (changed) {
      _version++;
      _views.clear();
    }
  }

  /// The metadata that applies to the package at [packageRoot].
  MetadataView viewFor(String packageRoot) {
    final cached = _views[packageRoot];
    if (cached != null && cached.$1 == _version) {
      return cached.$2;
    }
    final view = _build(packageRoot);
    _views[packageRoot] = (_version, view);
    return view;
  }

  /// Every metadata file loaded so far (for queries without a package).
  Iterable<SpringMetadata> get allLoaded => [
    for (final (_, metadata) in _loaded.values) ?metadata,
  ];

  /// Whether the package at [root] has a metadata file.
  bool hasMetadata(String root) => _read(root) != null;

  _Config? _configFor(String packageRoot) {
    var directory = Directory(packageRoot);
    while (true) {
      final path = '${directory.path}/.dart_tool/package_config.json';
      final cached = _configs[path];
      if (cached != null) {
        return cached;
      }
      final file = File(path);
      if (file.existsSync()) {
        final config = _Config.read(file);
        if (config != null) {
          return _configs[path] = config;
        }
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        return null;
      }
      directory = parent;
    }
  }

  SpringMetadata? _read(String root) {
    final file = File('$root/$metadataFile');
    final cached = _loaded[root];
    if (cached != null) {
      return cached.$2;
    }
    SpringMetadata? metadata;
    var modified = DateTime.fromMillisecondsSinceEpoch(0);
    if (file.existsSync()) {
      modified = file.lastModifiedSync();
      try {
        final json = jsonDecode(file.readAsStringSync());
        if (json is Map) {
          metadata = SpringMetadata.parse(root, json.cast<String, Object?>());
        }
      } on Object catch (error) {
        stderr.writeln('dart_spring_lsp: bad $root/$metadataFile: $error');
      }
    }
    _loaded[root] = (modified, metadata);
    return metadata;
  }

  _Pubspec _pubspec(String root) {
    final file = File('$root/pubspec.yaml');
    if (!file.existsSync()) {
      return const _Pubspec(null, {}, {});
    }
    final modified = file.lastModifiedSync();
    final cached = _pubspecs[root];
    if (cached != null && cached.$1 == modified) {
      return cached.$2;
    }
    var pubspec = const _Pubspec(null, {}, {});
    try {
      final yaml = loadYaml(file.readAsStringSync());
      if (yaml is YamlMap) {
        Set<String> names(Object? map) =>
            map is YamlMap ? {for (final key in map.keys) '$key'} : <String>{};
        pubspec = _Pubspec(
          yaml['name'] as String?,
          names(yaml['dependencies']),
          names(yaml['dev_dependencies']),
        );
      }
    } on Object {
      // A pubspec being typed: no dependencies for now.
    }
    _pubspecs[root] = (modified, pubspec);
    return pubspec;
  }

  MetadataView _build(String packageRoot) {
    final config = _configFor(packageRoot);
    if (config == null) {
      // No pub get: only the package's own metadata can exist.
      final own = _read(packageRoot);
      return MetadataView(
        packageName: _pubspec(packageRoot).name,
        packageRoot: packageRoot,
        metadata: [?own],
        packageRoots: {
          ?_pubspec(packageRoot).name: packageRoot,
        },
        missing: const [],
        version: _version,
      );
    }
    final own = _pubspec(packageRoot);
    final roots = <String, String>{};
    final pending = <String>[
      ...own.dependencies,
      ...own.devDependencies,
      ?own.name,
    ];
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      final root = config.packages[name];
      if (root == null || roots.containsKey(name)) {
        continue;
      }
      roots[name] = root;
      pending.addAll(_pubspec(root).dependencies);
    }
    if (own.name != null) {
      roots[own.name!] = packageRoot;
    }
    final metadata = <SpringMetadata>[];
    final missing = <String>[];
    for (final MapEntry(key: name, value: root) in roots.entries) {
      final loaded = _read(root);
      if (loaded != null) {
        metadata.add(loaded);
      } else if (_isSpring(name, root)) {
        missing.add(name);
      }
    }
    return MetadataView(
      packageName: own.name,
      packageRoot: packageRoot,
      metadata: metadata,
      packageRoots: roots,
      missing: missing,
      version: _version,
    );
  }

  // A package that should have metadata: it depends on spring_core_dart (or
  // is it) but is not the generator or the editor tooling.
  bool _isSpring(String name, String root) {
    if (name == 'spring_core_dart_generator' ||
        name == 'dart_spring_language_server') {
      return false;
    }
    return name == 'spring_core_dart' ||
        _pubspec(root).dependencies.contains('spring_core_dart');
  }
}

final class _Pubspec {
  const _Pubspec(this.name, this.dependencies, this.devDependencies);
  final String? name;
  final Set<String> dependencies;
  final Set<String> devDependencies;
}

final class _Config {
  _Config(this.path, this.modified, this.packages);

  static _Config? read(File file) {
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map;
      final base = Uri.file(file.path);
      final packages = <String, String>{};
      for (final package in (json['packages'] as List?) ?? const []) {
        if (package is! Map) {
          continue;
        }
        var root = '${package['rootUri']}';
        if (!root.endsWith('/')) {
          root = '$root/';
        }
        packages['${package['name']}'] = base
            .resolve(root)
            .toFilePath()
            .replaceFirst(RegExp(r'[/\\]$'), '');
      }
      return _Config(file.path, file.lastModifiedSync(), packages);
    } on Object {
      return null;
    }
  }

  final String path;
  final DateTime modified;

  /// Package name to root directory.
  final Map<String, String> packages;
}
