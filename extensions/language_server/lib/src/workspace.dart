import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dart_spring_language_server/src/config_editor.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/data_model.dart';
import 'package:dart_spring_language_server/src/derived_queries.dart';
import 'package:dart_spring_language_server/src/flutter_assets.dart';
import 'package:dart_spring_language_server/src/metadata.dart';
import 'package:dart_spring_language_server/src/pointcuts.dart';
import 'package:dart_spring_language_server/src/properties_index.dart';
import 'package:dart_spring_language_server/src/query_editor.dart';
import 'package:dart_spring_language_server/src/schema.dart';
import 'package:dart_spring_language_server/src/spel_editor.dart';
import 'package:dart_spring_language_server/src/templates.dart';
import 'package:dart_spring_language_server/src/test_properties.dart';
import 'package:spring_core_dart/aop.dart' show ExpressionPointcut;
import 'package:spring_core_dart/expression.dart';
// The SpEL tokenizer is not exported: the highlighting reads its tokens.
// ignore: implementation_imports
import 'package:spring_core_dart/src/expression/tokenizer.dart';

/// Directories the scan never enters: tool and build output, and the
/// platform folders of a Flutter app, which hold no Spring sources.
/// Hidden directories (a leading `.`) are skipped as well.
const _skippedDirectories = {
  '.dart_tool',
  '.git',
  '.idea',
  '.vscode',
  'build',
  'node_modules',
  'ios',
  'android',
  'macos',
  'windows',
  'linux',
};

/// Annotations whose strings are read as templates of `${...}`
/// placeholders and `#{...}` SpEL expressions, for highlighting,
/// navigation and checks.
///
/// In these, an interpolated (non-raw) `'${key}'` is an error, since Dart
/// would replace it before the framework sees it. The strings of other
/// annotations are read as templates too when they contain `${` or `#{`.
const templateAnnotations = {
  'Value',
  'ConditionalOnExpression',
  'Cacheable',
  'CachePut',
  'CacheEvict',
  'Query',
  'Scheduled',
};

/// Annotation arguments whose whole string is one SpEL expression, without
/// `#{}`: the keys and conditions of the cache annotations, by annotation
/// name. Also inside `@Caching(cacheable: [Cacheable(key: ...)])`.
///
/// They are highlighted and parsed, and a `#name` in them must be a
/// parameter of the annotated method, or one of the variables every cache
/// expression has (`#root`, `#result`, `#p0`, ...).
const spelArguments = {
  'Cacheable': {'key', 'condition', 'unless'},
  'CachePut': {'key', 'condition', 'unless'},
  'CacheEvict': {'key', 'condition'},
};

/// The SpEL variables a cache expression may use besides the method's
/// parameters: `#root`, `#this`, `#result`, and `#p0` or `#a0` for a
/// parameter by position.
final _builtinSpelVariable = RegExp(r'^(root|this|result|[pa]\d+)$');

/// Annotations whose string arguments name beans: go to definition on
/// `'cash'` in `@Qualifier('cash')` leads to the beans named or qualified
/// `cash`.
const _beanNameAnnotations = {
  'Qualifier',
  'DependsOn',
  'ConditionalOnBean',
  'ConditionalOnMissingBean',
};

/// Methods whose type argument is a bean type: go to definition on `Clock`
/// in `context.getBean<Clock>()` lists the `Clock` beans.
const _beanLookupMethods = {
  'getBean',
  // spring_boot_starter_flutter: `context.bean<T>()`, `SpringScope.beanOf<T>`.
  'bean',
  'beanOf',
  'getBeansOfType',
  'getBeanProvider',
  'getSortedBeans',
  'findBean',
  'dependency',
  'optionalDependency',
  'provider',
};

/// Methods whose first string argument is a property key: go to
/// definition on `'shop.name'` in `environment.getProperty('shop.name')`
/// lists the files that define it.
const _propertyMethods = {
  'getProperty',
  'getRequiredProperty',
  'containsProperty',
  'getPropertyAs',
};

/// Types the container itself provides to an injection point.
const _frameworkTypes = {
  'ApplicationContext',
  'ConfigurableApplicationContext',
  'BeanFactory',
  'ListableBeanFactory',
  'ConfigurableListableBeanFactory',
  'Environment',
  'ConfigurableEnvironment',
  'ApplicationEventPublisher',
  'ResourceLoader',
  'MessageSource',
  'ApplicationArguments',
};

/// Annotations on a class that do not make it a bean in a dependency.
const _plainAnnotations = {
  'immutable',
  'sealed',
  'deprecated',
  'visibleForTesting',
  'Immutable',
  'JsonSerializable',
};

/// Types that wrap the bean type at an injection point: for
/// `List<Mailer>`, `ObjectProvider<Mailer>` or `Map<String, Mailer>`, the
/// beans of `Mailer` (the last type argument) are meant.
const _containers = {'List', 'Set', 'Iterable', 'ObjectProvider', 'Map'};

/// A span of text in a file, in LSP terms: zero-based lines, and columns
/// counted in UTF-16 code units.
///
/// Definitions and diagnostics are reported as ranges; the server turns
/// them into LSP locations.
final class SourceRange {
  /// The span of [path] from [startLine], [startColumn] to [endLine],
  /// [endColumn].
  const SourceRange(
    this.path,
    this.startLine,
    this.startColumn,
    this.endLine,
    this.endColumn,
  );

  /// The absolute path of the file.
  final String path;

  /// The zero-based line where the span starts.
  final int startLine;

  /// The zero-based column where the span starts.
  final int startColumn;

  /// The zero-based line where the span ends.
  final int endLine;

  /// The zero-based column just after the span's last character.
  final int endColumn;

  @override
  String toString() => '$path:$startLine:$startColumn';
}

/// A diagnostic for the editor to underline: where, what, and whether it
/// is an error or a warning.
///
/// [SpringWorkspace.problems] produces them; the server publishes them
/// with the source `dart_spring`.
final class Problem {
  /// A warning, or with [error] an error, about [range].
  const Problem(
    this.range,
    this.message, {
    this.error = false,
    this.info = false,
  });

  /// Whether it is only a note (LSP severity 3), such as the hint to
  /// generate the Spring metadata.
  final bool info;

  /// The text to underline.
  final SourceRange range;

  /// What is wrong, and where possible how to fix it, as shown to the user.
  final String message;

  /// Whether it is an error (LSP severity 1) rather than a warning
  /// (severity 2). Errors mark what cannot work, such as invalid SpEL;
  /// warnings what may still be fine, such as a key the workspace does not
  /// define but the deployment may.
  final bool error;
}

/// The semantic token types the server reports, in the order of the
/// legend it announces at `initialize`: a token's type is an index into
/// this list.
///
/// The first nine and `comment` are standard LSP types, which every theme
/// colours.
/// `closureParameter` is the server's own, for a closure's parameters where
/// they are declared and used; it needs an editor rule to get a colour.
const semanticTokenTypes = [
  'keyword',
  'operator',
  'number',
  'string',
  'variable',
  'property',
  'method',
  'type',
  'class',
  // A closure's parameter, where it is declared and where the closure's
  // body uses it (an editor rule gives it a colour of its own).
  'closureParameter',
  // A comment in the SQL of a `@Query`.
  'comment',
];

/// One piece of text to colour: a SpEL keyword, a placeholder key, a
/// closure parameter.
///
/// The position is absolute (zero-based line and UTF-16 column) and the
/// token stays on one line; the server sorts the tokens and turns them
/// into LSP's relative encoding.
final class SemanticToken {
  /// A token of [length] UTF-16 units at [line], [column], of [type].
  const SemanticToken(this.line, this.column, this.length, this.type);

  /// The zero-based line.
  final int line;

  /// The zero-based column where the token starts, in UTF-16 units.
  final int column;

  /// The length in UTF-16 units.
  final int length;

  /// The token's type, as an index into [semanticTokenTypes].
  final int type;
}

/// A string literal that is an argument of an annotation or a method
/// call, with the name of that annotation or method: what decides how the
/// string is read (bean name, property key, template, pointcut).
final class _StringRef {
  _StringRef(this.literal, this.annotation, this.method);

  final SimpleStringLiteral literal;
  final String? annotation;
  final String? method;

  int get contentStart => literal.contentsOffset;
  int get contentEnd => literal.contentsEnd;
}

/// What the language server knows about the open project: its Dart files,
/// the beans they declare and its config files, and the answers to the
/// editor's questions ([definition], [hover], [semanticTokens],
/// [problems]).
///
/// It reads syntax only, with no type resolution, so it is fast and works
/// without `pub get` and on code that does not compile. The price: types
/// are matched by their simple name, and supertypes are followed only
/// through classes of the workspace; beans of dependencies (such as the
/// starters' auto-configuration) are not seen. Files are read from disk
/// when their modification time changes, skipping the generated
/// `*.spring.dart` and `*.g.dart`; the unsaved text of an open document
/// ([setOverlay]) wins over the disk. The indexes are rebuilt on the next
/// query after a change.
///
/// ```dart
/// final workspace = SpringWorkspace(['/home/ada/shop'])
///   ..refresh(force: true);
/// // A click at offset 120 of the checkout: where are its beans?
/// final targets = workspace.definition(
///   '/home/ada/shop/lib/checkout.dart',
///   120,
/// );
/// ```
final class SpringWorkspace {
  /// A workspace over the directories [roots]. Nothing is read until
  /// [refresh] or a query.
  SpringWorkspace(this.roots);

  /// The workspace folders the editor opened, scanned recursively.
  final List<String> roots;

  final _files = <String, DartFile>{};
  final _modified = <String, DateTime>{};
  final _overlays = <String, String>{};
  final _configOverlays = <String, String>{};
  final _properties = <String, List<PropertyEntry>>{};
  final _propertiesModified = <String, DateTime>{};
  List<BeanInfo>? _beans;
  Map<String, List<ClassInfo>>? _classes;
  DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);

  /// The Spring metadata of the packages, read from
  /// `lib/spring_gen/spring_metadata.json` and found through
  /// `.dart_tool/package_config.json`; re-read when a file changes.
  final metadata = MetadataStore();
  final _schemas = <String, (int, int, Schema)>{};
  Map<String, Set<String>>? _codeKeys;
  var _generation = 0;
  late final _spel = SpelEditor(this);

  /// The entities and repositories of the data layer.
  late final data = DataModel(this);
  late final _query = QueryEditor(this);
  late final _derived = DerivedQueryEditor(this);
  late final _config = ConfigEditor(this);

  /// Sets the unsaved [text] of the document open at [path]; with `null`
  /// (the document was closed), the file on disk counts again.
  ///
  /// A Dart document is parsed at once, so the next query sees it. A config
  /// file ([isConfigFile]) is read as properties, so its unsaved keys count
  /// for navigation and for the unknown-key check. Other files are ignored.
  void setOverlay(String path, String? text) {
    if (!path.endsWith('.dart')) {
      _setConfigOverlay(path, text);
      return;
    }
    if (text == null) {
      _overlays.remove(path);
      _modified.remove(path);
    } else {
      _overlays[path] = text;
      _files[path] = DartFile.parse(path, text);
    }
    _beans = null;
    _codeKeys = null;
    _generation++;
    _classes = null;
    _addedMessages = null;
  }

  void _setConfigOverlay(String path, String? text) {
    if (!isConfigFile(path)) {
      return;
    }
    if (text == null) {
      _configOverlays.remove(path);
      _propertiesModified.remove(path); // read from disk again
    } else {
      _configOverlays[path] = text;
      // Unsaved keys count for navigation and checks right away.
      _properties[path] = _isYaml(path)
          ? parseYamlProperties(path, text)
          : parseProperties(path, text);
    }
    _bundles = null;
  }

  /// Whether [path] is a config file of the application, whose keys are
  /// indexed and whose values are highlighted: any `.properties` file, and
  /// YAML named `application*` or under a `resources/` directory. Not every
  /// YAML: `${{ }}` in a CI workflow is no placeholder.
  static bool isConfigFile(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    return name.endsWith('.properties') ||
        (_isYaml(name) &&
            (_inResources(path) || name.startsWith('application')));
  }

  /// Scans [roots] again: re-reads the files changed on disk and forgets
  /// those that are gone.
  ///
  /// Queries call it, so to stay cheap it scans at most once per [interval]
  /// (2 seconds by default) unless [force] is set. The server forces it on
  /// `initialized`, on save and when watched files change.
  void refresh({
    bool force = false,
    Duration interval = const Duration(seconds: 2),
  }) {
    final now = DateTime.now();
    if (!force && now.difference(_lastScan) < interval) {
      return;
    }
    _lastScan = now;
    metadata.refresh();
    final seenDart = <String>{};
    final seenProperties = <String>{};
    for (final root in roots) {
      final directory = Directory(root);
      if (!directory.existsSync()) {
        continue;
      }
      _walk(directory, seenDart, seenProperties);
    }
    var changed = false;
    for (final path in [..._files.keys]) {
      if (!seenDart.contains(path) && !_overlays.containsKey(path)) {
        _files.remove(path);
        _modified.remove(path);
        changed = true;
      }
    }
    final before = _properties.length;
    _properties.removeWhere((path, _) => !seenProperties.contains(path));
    if (_properties.length != before) {
      _bundles = null;
    }
    // A pubspec.yaml may have appeared or gone: package roots are looked
    // up again.
    _packageRoots.clear();
    if (changed || _beans == null) {
      _beans = null;
      _codeKeys = null;
      _generation++;
      _classes = null;
      _addedMessages = null;
    }
  }

  void _walk(Directory directory, Set<String> dart, Set<String> properties) {
    List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entity in entries) {
      final name = entity.uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
      if (entity is Directory) {
        if (!name.startsWith('.') && !_skippedDirectories.contains(name)) {
          _walk(entity, dart, properties);
        }
      } else if (entity is File) {
        if (name.endsWith('.dart') &&
            !name.endsWith('.spring.dart') &&
            !name.endsWith('.g.dart')) {
          dart.add(entity.path);
          _readDart(entity);
        } else if (name.endsWith('.properties') ||
            (_isYaml(name) &&
                (_inResources(entity.path) ||
                    name.startsWith('application')))) {
          properties.add(entity.path);
          _readProperties(entity);
        }
      }
    }
  }

  void _readDart(File file) {
    if (_overlays.containsKey(file.path)) {
      return;
    }
    final modified = file.lastModifiedSync();
    if (_modified[file.path] == modified) {
      return;
    }
    _modified[file.path] = modified;
    try {
      _files[file.path] = DartFile.parse(file.path, file.readAsStringSync());
    } on FileSystemException {
      _files.remove(file.path);
    }
    _beans = null;
    _codeKeys = null;
    _generation++;
    _classes = null;
    _addedMessages = null;
  }

  void _readProperties(File file) {
    if (_configOverlays.containsKey(file.path)) {
      return; // the open document wins
    }
    final modified = file.lastModifiedSync();
    if (_propertiesModified[file.path] == modified) {
      return;
    }
    _propertiesModified[file.path] = modified;
    _bundles = null;
    try {
      final text = file.readAsStringSync();
      _properties[file.path] = _isYaml(file.path)
          ? parseYamlProperties(file.path, text)
          : parseProperties(file.path, text);
    } on FileSystemException {
      _properties.remove(file.path);
    }
  }

  /// The parsed Dart file at [path]: the open document's text if there is
  /// one, else the file on disk, read on first use. `null` when [path] is
  /// not a Dart file or does not exist.
  DartFile? file(String path) {
    if (!path.endsWith('.dart')) {
      return null;
    }
    final existing = _files[path];
    if (existing != null) {
      return existing;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    _readDart(file);
    return _files[path];
  }

  // ---------------------------------------------------------------------
  // Beans
  // ---------------------------------------------------------------------

  Map<String, List<ClassInfo>> get _classIndex {
    final cached = _classes;
    if (cached != null) {
      return cached;
    }
    final index = <String, List<ClassInfo>>{};
    for (final file in _files.values) {
      for (final info in file.classes) {
        (index[info.name] ??= []).add(info);
      }
    }
    return _classes = index;
  }

  /// The classes of the workspace called [name] (top-level, by simple name).
  List<ClassInfo> classesNamed(String name) =>
      _classIndex[name] ?? const <ClassInfo>[];

  /// Every top-level class of the workspace.
  Iterable<ClassInfo> get allClasses => _classIndex.values.expand((c) => c);

  /// Every type name that a class called [name] can be used as: itself and
  /// its supertypes (`extends`, `implements`, `with`), followed through the
  /// classes of the workspace by simple name. A type from a dependency ends
  /// its branch.
  Set<String> supertypesOf(String name) {
    final result = <String>{};
    final pending = [name];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!result.add(current)) {
        continue;
      }
      for (final info in _classIndex[current] ?? const <ClassInfo>[]) {
        pending.addAll(info.supertypes);
      }
    }
    return result;
  }

  /// The names of the annotations that make a class a bean: the
  /// [baseStereotypes], plus the classes of the workspace that extend one of
  /// them (a custom `UseCase` annotation that extends `Component`).
  Set<String> get stereotypes => {
    ...baseStereotypes,
    for (final MapEntry(key: name, value: infos) in _classIndex.entries)
      if (infos.isNotEmpty &&
          supertypesOf(name).skip(1).any(baseStereotypes.contains))
        name,
  };

  /// Every bean declared in the workspace: the classes with a stereotype
  /// annotation, and the `@Bean` methods inside them. Built on first use
  /// after a change.
  List<BeanInfo> get beans => _beans ??= _collectBeans();

  List<BeanInfo> _collectBeans() {
    final stereotypes = this.stereotypes;
    final result = <BeanInfo>[];
    for (final file in _files.values) {
      for (final info in file.classes) {
        final stereotype = info.annotations
            .where((a) => stereotypes.contains(annotationName(a)))
            .firstOrNull;
        if (stereotype == null) {
          // A Spring Data repository (`implements DataRepository<Book, int>`)
          // is a bean the data starter makes; it carries no annotation.
          if (data.entityOf(info.declaration, file.path) != null) {
            result.add(
              BeanInfo(
                name: defaultBeanName(info.name),
                typeName: info.name,
                kind: BeanKind.component,
                path: file.path,
                offset: info.nameOffset,
                length: info.name.length,
                qualifiers: _qualifiers(info.annotations),
                primary: info.annotationNames.contains('Primary'),
                profiles: _profiles(info.annotations),
                backsOff: _backsOff(info.annotations),
              ),
            );
          }
          continue;
        }
        final explicit = _unnamed(stereotype)
            ? stringValue(namedArgument(stereotype, 'name'))
            : stringValue(positionalArgument(stereotype));
        final name = explicit ?? defaultBeanName(info.name);
        result.add(
          BeanInfo(
            name: name,
            typeName: info.name,
            kind: BeanKind.component,
            path: file.path,
            offset: info.nameOffset,
            length: info.name.length,
            qualifiers: _qualifiers(info.annotations),
            primary: info.annotationNames.contains('Primary'),
            profiles: _profiles(info.annotations),
            contextGetter: _contextGetter(info.annotations, name),
            backsOff: _backsOff(info.annotations),
          ),
        );
        for (final member in info.declaration.body.members) {
          if (member is! MethodDeclaration) {
            continue;
          }
          final bean = member.metadata
              .where((a) => annotationName(a) == 'Bean')
              .firstOrNull;
          final returned = typeName(member.returnType);
          if (bean == null || returned == null) {
            continue;
          }
          final name =
              stringValue(namedArgument(bean, 'name')) ?? member.name.lexeme;
          result.add(
            BeanInfo(
              name: name,
              typeName: returned,
              kind: BeanKind.beanMethod,
              path: file.path,
              offset: member.name.offset,
              length: member.name.length,
              aliases: stringList(namedArgument(bean, 'aliases')).toSet(),
              qualifiers: _qualifiers(member.metadata),
              primary: member.metadata.any(
                (a) => annotationName(a) == 'Primary',
              ),
              profiles: _profiles(member.metadata),
              backsOff: _backsOff(member.metadata),
              owner: info.name,
              contextGetter: _contextGetter(member.metadata, name),
            ),
          );
        }
      }
    }
    _mergeMetadataBeans(result);
    return result;
  }

  // The beans of the metadata (dependencies' auto-configuration, the
  // package's own at the last build) join the beans found in the source. A
  // bean declared in a file of the workspace is taken from the source, the
  // live truth; the metadata then only adds the supertypes and the members
  // SpEL can reach.
  void _mergeMetadataBeans(List<BeanInfo> result) {
    final seen = <SpringMetadata>{};
    final roots = {for (final path in _files.keys) _packageRoot(path)};
    final fromMetadata = <BeanInfo>[];
    for (final root in roots) {
      final view = metadata.viewFor(root);
      for (final meta in view.metadata) {
        if (!seen.add(meta)) {
          continue;
        }
        for (final bean in meta.beans) {
          final path = view.resolve(bean.source);
          final local = result.where((b) => b.name == bean.name).firstOrNull;
          if (local != null) {
            local
              ..members = bean.members
              ..extraTypes = bean.types;
            continue;
          }
          final declared = path == null ? null : _files[path];
          final klass = declared?.classes
              .where((c) => c.name == bean.type)
              .firstOrNull;
          // Removed from the source since the last build: the class is gone
          // from the whole workspace. A bean declared elsewhere than its
          // class (a `BeanDefinition` or `@Bean` in a configuration file)
          // is kept.
          if (declared != null &&
              klass == null &&
              !_classIndex.containsKey(bean.type)) {
            continue;
          }
          fromMetadata.add(
            BeanInfo(
              name: bean.name,
              typeName: bean.type,
              kind: BeanKind.component,
              path: path ?? '',
              offset: klass?.nameOffset ?? 0,
              length: klass?.name.length ?? 0,
              qualifiers: bean.qualifiers.toSet(),
              primary: bean.primary,
              profiles: bean.profiles,
              // A class of the workspace is found in the live source.
              line: klass != null || bean.line == null ? null : bean.line! - 1,
              members: bean.members,
              fromMetadata: true,
              scope: bean.scope,
              origin: bean.source,
              backsOff: bean.conditions.any(
                (c) =>
                    c.startsWith('@ConditionalOnMissingBean') ||
                    c.startsWith('@Fallback'),
              ),
            )..extraTypes = bean.types,
          );
        }
      }
    }
    result.addAll(fromMetadata);
    for (final bean in result) {
      bean.providedTypes = {
        ...supertypesOf(bean.typeName),
        ...bean.extraTypes,
      };
    }
  }

  // The `BuildContext` getter `@BuildContextAccess` generates: its `name:`,
  // else the bean name.
  static String? _contextGetter(List<Annotation> annotations, String bean) {
    for (final annotation in annotations) {
      if (annotationName(annotation) == 'BuildContextAccess') {
        return stringValue(namedArgument(annotation, 'name')) ?? bean;
      }
    }
    return null;
  }

  bool _unnamed(Annotation annotation) =>
      unnamedStereotypes.contains(annotationName(annotation));

  static Set<String> _qualifiers(List<Annotation> annotations) => {
    for (final annotation in annotations)
      if (annotationName(annotation) == 'Qualifier')
        ?stringValue(positionalArgument(annotation)),
  };

  static bool _backsOff(List<Annotation> annotations) => annotations.any(
    (a) => const {
      'Fallback',
      'ConditionalOnMissingBean',
    }.contains(annotationName(a)),
  );

  static List<String> _profiles(List<Annotation> annotations) => [
    for (final annotation in annotations)
      if (annotationName(annotation) == 'Profile')
        ...stringList(positionalArgument(annotation)),
  ];

  /// The beans that can be injected where [type] is asked for, `@Primary`
  /// ones first: what go to definition on an injection point lists. With
  /// [qualifier], only the beans whose name, alias or `@Qualifier` it is.
  ///
  /// With [from] (a file), only the beans that package can see: its own and
  /// those of its dependencies. A workspace holds many packages, and their
  /// tests and examples often declare beans of the same type.
  List<BeanInfo> beansOfType(String type, {String? qualifier, String? from}) {
    final visible = from == null ? null : _visibleRoots(from);
    final candidates = [
      for (final bean in beans)
        if (bean.providedTypes.contains(type))
          if (qualifier == null || bean.matches(qualifier))
            if (visible == null || _isVisible(bean, visible)) bean,
    ]..sort((a, b) => (b.primary ? 1 : 0) - (a.primary ? 1 : 0));
    return candidates;
  }

  // The package roots a file sees: its package and its dependencies.
  ({Set<String> roots, Set<String> packages}) _visibleRoots(String path) {
    final root = _packageRoot(path);
    final view = metadata.viewFor(root);
    return (
      roots: {root, ...view.packageRoots.values},
      packages: view.packageRoots.keys.toSet(),
    );
  }

  bool _isVisible(
    BeanInfo bean,
    ({Set<String> roots, Set<String> packages}) visible,
  ) {
    if (bean.path.isNotEmpty) {
      // The bean's own package, not just a folder above it: a package
      // nested in another (an example inside a starter) has its own root.
      final own = _ownPackage(bean.path);
      return own == null || visible.roots.any((root) => _realPath(root) == own);
    }
    final origin = bean.origin;
    if (origin == null || !origin.startsWith('package:')) {
      return true;
    }
    final name = origin.substring('package:'.length).split('/').first;
    return visible.packages.contains(name);
  }

  // The folder of the nearest pubspec.yaml above [path], symlinks resolved;
  // `null` when there is none.
  String? _ownPackage(String path) =>
      _ownPackages[File(path).parent.path] ??= () {
        var current = Directory(File(path).parent.path);
        while (true) {
          if (File('${current.path}/pubspec.yaml').existsSync()) {
            return _realPath(current.path);
          }
          if (current.parent.path == current.path) {
            return null;
          }
          current = current.parent;
        }
      }();
  final _ownPackages = <String, String?>{};

  static String _realPath(String path) {
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    try {
      return Directory(trimmed).resolveSymbolicLinksSync();
    } on FileSystemException {
      return trimmed;
    }
  }

  // The file whose package decides which beans are visible, while a hover,
  // a definition or a check of that file runs.
  String? _scope;

  /// The beans that answer to [name], by bean name, by
  /// `@Bean(aliases: ...)` or by `@Qualifier`.
  List<BeanInfo> beansNamed(String name) => [
    for (final bean in beans)
      if (bean.matches(name)) bean,
  ];

  /// The `@Pointcut` methods of the workspace's `@Aspect` classes. Other
  /// pointcuts refer to them by name (`pricing()`, `AuditAspect.pricing()`),
  /// so the pointcut check and navigation need them.
  List<PointcutMethod> get pointcutMethods => [
    for (final file in _files.values)
      for (final info in file.classes)
        if (info.annotationNames.contains('Aspect'))
          for (final member in info.declaration.body.members)
            if (member is MethodDeclaration)
              for (final annotation in member.metadata)
                if (annotationName(annotation) == 'Pointcut')
                  if (stringValue(positionalArgument(annotation))
                      case final expression?)
                    PointcutMethod(
                      info.name,
                      member.name.lexeme,
                      expression,
                      info.path,
                      member.name.offset,
                    ),
  ];

  // ---------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------

  /// The definitions of the property [key] in every properties and YAML file
  /// of the workspace (message bundles excluded): `application.*` first,
  /// then by file name and line.
  ///
  /// Keys match the relaxed way the framework binds them: `my-key`, `myKey`,
  /// `my_key` and `MY_KEY` are one key. In a test file ([from]), the
  /// properties the test sets for its own context come first (see
  /// [testProperties]); its environment variables match the way the
  /// framework maps them (`SHOP_MAX_BASKET_SIZE` for
  /// `shop.max-basket-size`).
  List<PropertyEntry> property(String key, {DartFile? from}) {
    final wanted = _canonical(key);
    final variables = _environmentNames(key);
    bool matches(PropertyEntry entry) => entry.environment
        ? variables.contains(entry.key)
        : entry.key == key || _canonical(entry.key) == wanted;
    final bundles = _messageBundles();
    final result = [
      for (final MapEntry(key: path, value: entries) in _properties.entries)
        if (!bundles.contains(path))
          for (final entry in entries)
            if (matches(entry)) entry,
    ]..sort((a, b) => _fileOrder(a).compareTo(_fileOrder(b)));
    return [
      if (from != null)
        for (final entry in testProperties(from))
          if (matches(entry)) entry,
      ...result,
    ];
  }

  // The environment variables that give the property [key], as the
  // framework's SystemEnvironmentPropertySource looks them up:
  // `shop.max-basket-size` → `SHOP_MAX_BASKET_SIZE`, `SHOP_MAXBASKETSIZE`,
  // `shop_max_basket_size`, ...
  static Set<String> _environmentNames(String key) {
    final variants = [
      key,
      key.replaceAll('.', '_'),
      key.replaceAll('-', '_'),
      key.replaceAll('.', '_').replaceAll('-', '_'),
    ];
    return {
      ...variants,
      ...variants.map((v) => v.toUpperCase()),
      key.replaceAll('-', '').replaceAll('.', '_').toUpperCase(),
    };
  }

  /// The definitions whose key starts with [prefix] and a dot, with relaxed
  /// names as in [property]: the keys a `@ConfigurationProperties('shop')`
  /// class binds.
  List<PropertyEntry> propertiesWithPrefix(String prefix) {
    final wanted = '${_canonical(prefix)}.';
    final bundles = _messageBundles();
    return [
      for (final MapEntry(key: path, value: entries) in _properties.entries)
        if (!bundles.contains(path))
          for (final entry in entries)
            if (_canonical(entry.key).startsWith(wanted)) entry,
    ]..sort((a, b) => _fileOrder(a).compareTo(_fileOrder(b)));
  }

  /// The definitions of the message [code] in every message bundle
  /// (`messages.properties`, `messages_ja.properties`, ..., or the bundles of
  /// `spring.messages.basename`), the default bundle first. With [from],
  /// only the bundles of that file's package.
  List<PropertyEntry> messages(String code, {String? from}) {
    final package = from == null ? null : _packageRoot(from);
    return [
      for (final MapEntry(key: path, value: bundlePackage)
          in _messageBundlePackages().entries)
        if (package == null || bundlePackage == package)
          for (final entry in _properties[path] ?? const <PropertyEntry>[])
            if (entry.key == code) entry,
    ]..sort((a, b) => a.fileName.compareTo(b.fileName));
  }

  // Codes registered in code in the package of [path]
  // (`StaticMessageSource().addMessage('code', ...)`, `addMessages`).
  Set<String> _messagesAddedInCode(String path) {
    final package = _packageRoot(path);
    final byPackage = _addedMessages ??= {};
    return byPackage[package] ??= {
      for (final file in _files.values)
        if (_packageRoot(file.path) == package)
          ..._AddedMessageCollector.of(file.unit),
    };
  }

  Map<String, Set<String>>? _addedMessages;

  /// Whether the package of [path] has a message bundle; only then are the
  /// message codes of its files checked.
  bool hasMessageBundles(String path) {
    final package = _packageRoot(path);
    return _messageBundlePackages().values.contains(package);
  }

  Set<String> _messageBundles() => _messageBundlePackages().keys.toSet();

  // The message bundles by path, with their package: `.properties` files
  // under a `resources/` directory whose name (without the locale suffix)
  // is a basename of their package's `spring.messages.basename`
  // (`messages` by default; dots or slashes separate folders:
  // `i18n/messages`). Each package has its own setting.
  Map<String, String> _messageBundlePackages() =>
      _bundles ??= _findMessageBundles();

  Map<String, String>? _bundles;

  // Packages with `spring.messages.use-code-as-default-message=true`: an
  // unknown code is not an error there.
  final Set<String> _codeAsDefault = {};

  Map<String, String> _findMessageBundles() {
    final basenames = <String, Set<String>>{};
    final common = <String, Set<String>>{};
    _codeAsDefault.clear();
    for (final MapEntry(key: path, value: entries) in _properties.entries) {
      for (final entry in entries) {
        if (entry.key == 'spring.messages.use-code-as-default-message' &&
            entry.value.trim().toLowerCase() == 'true') {
          _codeAsDefault.add(_packageRoot(path));
        }
        if (entry.key == 'spring.messages.common-messages') {
          for (final name in entry.value.split(',')) {
            final trimmed = name.trim().replaceFirst(
              RegExp('^resources:'),
              '',
            );
            if (trimmed.isNotEmpty) {
              common
                  .putIfAbsent(_packageRoot(path), () => {})
                  .add(
                    trimmed.substring(
                      0,
                      trimmed.lastIndexOf('.') < 0
                          ? trimmed.length
                          : trimmed.lastIndexOf('.'),
                    ),
                  );
            }
          }
        }
        if (entry.key == 'spring.messages.basename') {
          final names = basenames.putIfAbsent(_packageRoot(path), () => {});
          for (final name in entry.value.split(',')) {
            final trimmed = name.trim().replaceFirst(
              RegExp('^resources:'),
              '',
            );
            if (trimmed.isNotEmpty) {
              names.add(trimmed.replaceAll('.', '/'));
            }
          }
        }
      }
    }
    final result = <String, String>{};
    for (final path in _properties.keys) {
      if (!path.endsWith('.properties')) {
        continue;
      }
      final relative = _resourcePath(path);
      if (relative == null) {
        continue;
      }
      final package = _packageRoot(path);
      final names = basenames[package] ?? const {'messages'};
      if (names.any(
            (basename) =>
                relative == basename || relative.startsWith('${basename}_'),
          ) ||
          (common[package]?.contains(relative) ?? false)) {
        result[path] = package;
      }
    }
    return result;
  }

  // `i18n/messages_ja` for `.../lib/resources/i18n/messages_ja.properties`.
  static String? _resourcePath(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/resources/');
    if (index < 0) {
      return null;
    }
    final relative = normalized.substring(index + '/resources/'.length);
    return relative.substring(0, relative.lastIndexOf('.'));
  }

  static bool _isYaml(String name) =>
      name.endsWith('.yml') || name.endsWith('.yaml');

  static bool _inResources(String path) =>
      path.replaceAll(r'\', '/').contains('/resources/');

  static String _fileOrder(PropertyEntry entry) =>
      '${entry.fileName == 'application' ? 0 : 1}${entry.fileName}'
      '${entry.line.toString().padLeft(6, '0')}';

  // Relaxed binding: `my-key`, `my_key` and `myKey` are the same name.
  static String _canonical(String key) =>
      key.toLowerCase().replaceAll('-', '').replaceAll('_', '');

  // ---------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------

  /// The targets of go to definition at [offset] (in UTF-16 units) of the
  /// Dart file [path].
  ///
  /// Depending on what is there: the beans of an injection point or a bean
  /// name, the definitions of a property key or a message code, the file of
  /// a `resources:` location, the class or method a pointcut names. Empty
  /// when there is nothing Spring-specific at [offset]; the Dart analysis
  /// server answers for the rest.
  List<SourceRange> definition(String path, int offset) {
    if (isConfigFile(path)) {
      final text = textOf(path);
      return text == null ? const [] : _config.definition(path, text, offset);
    }
    final file = this.file(path);
    if (file == null) {
      return const [];
    }
    // `@Query` texts and derived query names of repositories.
    if (_query.definition(file, path, offset) case final found?) {
      return found;
    }
    if (_derived.definition(file, path, offset) case final found?
        when found.isNotEmpty) {
      return found;
    }
    final target = _targetAt(file, offset);
    return switch (target) {
      _BeanTarget(:final beans) => [
        for (final bean in beans)
          if (bean.path.isNotEmpty) _beanRange(bean),
      ],
      _PropertyTarget(:final entries) => [
        for (final entry in entries)
          SourceRange(
            entry.path,
            entry.line,
            entry.keyStart,
            entry.line,
            entry.keyEnd,
          ),
      ],
      _ResourceTarget(:final files) => [
        for (final file in files) SourceRange(file, 0, 0, 0, 0),
      ],
      _DeclarationTarget(:final declarations) => [
        for (final declaration in declarations)
          if (this.file(declaration.path) case final file?)
            rangeOf(
              file,
              declaration.offset,
              declaration.offset + declaration.length,
            ),
      ],
      _TextTarget() => const [],
      null => const [],
    };
  }

  // The default of the `${key:default}` around [offset] in [text], or
  // `null` when the placeholder has none.
  static String? _placeholderDefault(String? text, int offset) {
    if (text == null) {
      return null;
    }
    final start = text.lastIndexOf(r'${', offset);
    final end = start < 0 ? -1 : text.indexOf('}', offset);
    if (start < 0 || end < 0) {
      return null;
    }
    final inner = text.substring(start + 2, end);
    final colon = inner.indexOf(':');
    return colon < 0 ? null : inner.substring(colon + 1);
  }

  /// Markdown for a hover at [offset] of the Dart file [path], about the same
  /// target as [definition]: the candidate beans with their files, the
  /// value of a property in each file, the files a location resolves to.
  ///
  /// When nothing is found it says so (and, for a location, where it looked).
  /// `null` when [offset] is not on such a target.
  String? hover(String path, int offset) {
    if (isConfigFile(path)) {
      final text = textOf(path);
      return text == null ? null : _config.hover(path, text, offset);
    }
    final file = this.file(path);
    if (file == null) {
      return null;
    }
    if (_query.hover(file, path, offset) case final text?) {
      return text;
    }
    if (_derived.hover(file, path, offset) case final text?) {
      return text;
    }
    final target = _targetAt(file, offset);
    switch (target) {
      case _BeanTarget(:final beans, :final description):
        if (beans.isEmpty) {
          return '**$description**: no bean found in this project';
        }
        return [
          '**$description**',
          '',
          for (final bean in beans)
            '- ${bean.summary} — `${bean.origin ?? _shortPath(bean.path)}`',
        ].join('\n');
      case _PropertyTarget(:final key, :final entries, :final message):
        if (entries.isEmpty) {
          if (message) {
            return '**`$key`**: no such message in the message bundles';
          }
          final fallback = _placeholderDefault(textOf(path), offset);
          return fallback == null
              ? '**`$key`**: not defined in any properties file'
              : '**`$key`**: not defined in any properties file; '
                    'the default after the colon is used: `$fallback`';
        }
        return [
          if (message) '**`$key`** (message)' else '**`$key`**',
          '',
          for (final entry in entries)
            if (entry.provider case final provider?)
              '- provided by `$provider` (`@ServiceConnection`)'
            else
              '- `${entry.fileName}`: `${entry.value}`',
        ].join('\n');
      case _DeclarationTarget(:final description, :final declarations):
        if (declarations.isEmpty) {
          return '**$description**: nothing found in this project';
        }
        return [
          '**$description**',
          '',
          for (final declaration in declarations)
            '- ${declaration.summary} — `${_shortPath(declaration.path)}`',
        ].join('\n');
      case _ResourceTarget(:final location, :final files, :final searched):
        if (files.isEmpty) {
          return '**`$location`**: not found (looked in '
              '${searched.map((path) => '`${_shortPath(path)}`').join(', ')})';
        }
        return [
          '**`$location`**',
          '',
          for (final file in files) '- `${_shortPath(file)}`',
        ].join('\n');
      case _TextTarget(:final text):
        return text;
      case null:
        return null;
    }
  }

  SourceRange _beanRange(BeanInfo bean) {
    if (bean.line case final line?) {
      return SourceRange(bean.path, line, 0, line, 0);
    }
    final file = this.file(bean.path);
    if (file == null) {
      return SourceRange(bean.path, 0, 0, 0, 0);
    }
    return rangeOf(file, bean.offset, bean.offset + bean.length);
  }

  /// The span from offset [start] to offset [end] of [file], as zero-based
  /// lines and columns.
  SourceRange rangeOf(DartFile file, int start, int end) {
    final from = file.lineInfo.getLocation(start);
    final to = file.lineInfo.getLocation(end);
    return SourceRange(
      file.path,
      from.lineNumber - 1,
      from.columnNumber - 1,
      to.lineNumber - 1,
      to.columnNumber - 1,
    );
  }

  String _shortPath(String path) {
    for (final root in roots) {
      if (path.startsWith(root)) {
        return path.substring(root.length).replaceFirst(RegExp(r'^[/\\]'), '');
      }
    }
    return path;
  }

  _Target? _targetAt(DartFile file, int offset) {
    _scope = file.path;
    final node = file.nodeAt(offset);
    if (node == null) {
      return null;
    }
    // A string: bean name, property key or a template.
    if (node is SimpleStringLiteral) {
      return _stringTarget(file, _stringRef(node), offset);
    }
    // `this.repository` in a constructor: the field's type.
    if (node is FieldFormalParameter &&
        offset >= node.name.offset &&
        offset <= node.name.end) {
      final field = _fieldType(node);
      if (field != null) {
        final type = _beanType(field);
        if (type != null && !_hasAnnotation(node.metadata, 'Value')) {
          return _beanTargetFor(type, _qualifierOf(node.metadata));
        }
      }
      return null;
    }
    final namedType = node is NamedType
        ? node
        : node.thisOrAncestorOfType<NamedType>();
    if (namedType != null) {
      return _typeTarget(namedType);
    }
    // `context.basket`: a getter generated for a `@BuildContextAccess` bean.
    if (node is SimpleIdentifier && _isMemberName(node)) {
      final beans = [
        for (final bean in this.beans)
          if (bean.contextGetter == node.name) bean,
      ];
      if (beans.isNotEmpty) {
        return _BeanTarget(
          beans,
          '`context.${node.name}` (@BuildContextAccess)',
        );
      }
    }
    return null;
  }

  // `x.name` or `x?.name`: [node] is the member, not the target.
  static bool _isMemberName(SimpleIdentifier node) => switch (node.parent) {
    PrefixedIdentifier(:final identifier) => identical(identifier, node),
    PropertyAccess(:final propertyName) => identical(propertyName, node),
    _ => false,
  };

  _Target? _beanTargetFor(String type, String? qualifier) {
    final description = qualifier == null
        ? 'Beans of type $type'
        : "Beans of type $type qualified '$qualifier'";
    return _BeanTarget(
      beansOfType(type, qualifier: qualifier, from: _scope),
      description,
    );
  }

  _StringRef _stringRef(SimpleStringLiteral literal) {
    final annotation = literal.thisOrAncestorOfType<Annotation>();
    final invocation = literal.thisOrAncestorOfType<MethodInvocation>();
    return _StringRef(
      literal,
      annotation == null ? null : annotationName(annotation),
      invocation?.methodName.name,
    );
  }

  _Target? _stringTarget(DartFile file, _StringRef ref, int offset) {
    final value = ref.literal.value;
    final annotation = ref.annotation;
    if (_resourceTarget(file.path, value) case final target?) {
      return target;
    }
    if (annotation != null && pointcutAnnotations.contains(annotation)) {
      return _pointcutTarget(file, ref, offset);
    }
    if (_isSpelArgument(ref.literal)) {
      return _spelArgumentTarget(file, ref, offset);
    }
    if (annotation != null && _beanNameAnnotations.contains(annotation)) {
      return _BeanTarget(beansNamed(value), "Bean '$value'");
    }
    if (annotation == 'ConditionalOnProperty' ||
        annotation == 'ConditionalOnBooleanProperty') {
      return _PropertyTarget(value, property(value, from: file));
    }
    if (annotation == 'ConfigurationProperties') {
      return _PropertyTarget('$value.*', propertiesWithPrefix(value));
    }
    if (annotation != null && templateAnnotations.contains(annotation) ||
        value.contains(r'${') ||
        value.contains('#{')) {
      final source = file.text.substring(ref.contentStart, ref.contentEnd);
      final relative = offset - ref.contentStart;
      for (final part in scanTemplate(source).reversed) {
        if (relative < part.start || relative > part.end) {
          continue;
        }
        if (part.kind == TemplatePartKind.placeholder) {
          final key = part.inner(source);
          return _PropertyTarget(key, property(key, from: file));
        }
        return _expressionTarget(source, part, relative);
      }
    }
    if (_isMessageCode(ref.literal)) {
      return _PropertyTarget(
        value,
        messages(value, from: file.path),
        message: true,
      );
    }
    if (ref.method != null && _propertyMethods.contains(ref.method)) {
      return _PropertyTarget(value, property(value, from: file));
    }
    return null;
  }

  // In a pointcut: types and annotations go to their classes, `bean(...)`
  // to the beans, `pricing()` to the `@Pointcut` method, the method of
  // `execution(* Type.name(..))` to the matching methods.
  _Target? _pointcutTarget(DartFile file, _StringRef ref, int offset) {
    final source = file.text.substring(ref.contentStart, ref.contentEnd);
    final relative = offset - ref.contentStart;
    final parts = scanPointcut(source);
    final index = parts.indexWhere(
      (part) => relative >= part.start && relative <= part.end,
    );
    if (index < 0) {
      return null;
    }
    final part = parts[index];
    // The part right before, joined by a dot: `Aspect.name`, `Type.method`.
    final qualifier =
        index > 0 &&
            parts[index - 1].end == part.start - 1 &&
            source[part.start - 1] == '.'
        ? parts[index - 1].text
        : null;
    switch (part.kind) {
      case PointcutPartKind.type ||
          PointcutPartKind.declaringType ||
          PointcutPartKind.aspect:
        return _classesTarget(
          file.path,
          part.text,
          'Classes matching `${part.text}`',
        );
      case PointcutPartKind.annotation:
        return _classesTarget(
          file.path,
          part.text,
          'Annotation `${part.text}`',
        );
      case PointcutPartKind.bean:
        return _BeanTarget([
          for (final bean in beans)
            if (wildcardMatches(part.text, bean.name) ||
                bean.aliases.any((alias) => wildcardMatches(part.text, alias)))
              bean,
        ], "Beans matching '${part.text}'");
      case PointcutPartKind.reference:
        final owner = ref.literal
            .thisOrAncestorOfType<ClassDeclaration>()
            ?.namePart
            .typeName
            .lexeme;
        final named = [
          for (final method in pointcutMethods)
            if (method.name == part.text &&
                (qualifier == null || method.className == qualifier))
              method,
        ];
        final own = [
          for (final method in named)
            if (method.className == owner) method,
        ];
        return _DeclarationTarget('Pointcut `${part.text}()`', [
          for (final method
              in qualifier == null && own.isNotEmpty ? own : named)
            _Declaration(
              method.path,
              method.offset,
              method.name.length,
              '`${method.className}.${method.name}()`: `${method.expression}`',
            ),
        ]);
      case PointcutPartKind.member:
        final classes = qualifier == null
            ? _samePackageFirst(file.path, [
                for (final bean in beans)
                  if (bean.kind == BeanKind.component)
                    ...?_classIndex[bean.typeName],
              ])
            : _classesMatching(file.path, qualifier);
        return _DeclarationTarget('Methods matching `${part.text}`', [
          for (final info in classes)
            for (final member in info.declaration.body.members)
              if (member is MethodDeclaration &&
                  wildcardMatches(part.text, member.name.lexeme))
                _Declaration(
                  info.path,
                  member.name.offset,
                  member.name.length,
                  '`${info.name}.${member.name.lexeme}`',
                ),
        ]);
      case PointcutPartKind.designator ||
          PointcutPartKind.operator ||
          PointcutPartKind.wildcard:
        return null;
    }
  }

  // Classes whose name matches [pattern]; those of the package of [from]
  // when it has any (a test class elsewhere may have the same name).
  List<ClassInfo> _classesMatching(String from, String pattern) =>
      _samePackageFirst(from, [
        for (final MapEntry(:key, :value) in _classIndex.entries)
          if (wildcardMatches(pattern, key)) ...value,
      ]);

  List<ClassInfo> _samePackageFirst(String from, List<ClassInfo> classes) {
    final package = _packageRoot(from);
    final local = [
      for (final info in classes)
        if (_packageRoot(info.path) == package) info,
    ];
    return local.isNotEmpty ? local : classes;
  }

  _Target _classesTarget(String from, String pattern, String description) =>
      _DeclarationTarget(description, [
        for (final info in _classesMatching(from, pattern))
          _Declaration(
            info.path,
            info.nameOffset,
            info.name.length,
            'class `${info.name}`',
          ),
      ]);

  // `key: '#isbn'` of a cache annotation: `#isbn` goes to the parameter.
  _Target? _spelArgumentTarget(DartFile file, _StringRef ref, int offset) {
    final expression = file.text.substring(ref.contentStart, ref.contentEnd);
    final at = offset - ref.contentStart;
    final List<Token> tokens;
    try {
      tokens = Tokenizer(expression).process();
    } on Object {
      return null;
    }
    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.kind != TokenKind.identifier ||
          tokens[i - 1].kind != TokenKind.hash ||
          at < token.start - 1 ||
          at > token.end) {
        continue;
      }
      final name = expression.substring(token.start, token.end);
      return _DeclarationTarget('Parameter `$name`', [
        for (final parameter in _parametersOf(ref.literal))
          if (parameter.name?.lexeme == name)
            _Declaration(
              file.path,
              parameter.name!.offset,
              name.length,
              '`${parameter.toSource()}`',
            ),
      ]);
    }
    return null;
  }

  // Whether [literal] is the value of a SpEL argument ([spelArguments]) of
  // an annotation or of a `Cacheable(...)` inside `@Caching`.
  static bool _isSpelArgument(SimpleStringLiteral literal) {
    final named = literal.parent;
    if (named is! NamedArgument) {
      return false;
    }
    final owner = named.parent?.parent;
    final callee = switch (owner) {
      final Annotation annotation => annotationName(annotation),
      final InstanceCreationExpression creation =>
        creation.constructorName.type.name.lexeme,
      // `Cacheable(...)`, or `Cacheable.of(...)` (unresolved syntax).
      final MethodInvocation invocation => switch (invocation.target) {
        final SimpleIdentifier type => type.name,
        _ => invocation.methodName.name,
      },
      _ => null,
    };
    return spelArguments[callee]?.contains(named.name.lexeme) ?? false;
  }

  // The parameters of the method [node] annotates.
  static List<FormalParameter> _parametersOf(AstNode node) =>
      node
          .thisOrAncestorOfType<MethodDeclaration>()
          ?.parameters
          ?.parameters
          .toList() ??
      const [];

  static final _resourceLocation = RegExp(
    r'^(?:optional:)?(resources\*?|file|asset):(.+)$',
  );

  // `resources:legacy.properties` (in `@PropertySource`, `@Value`,
  // `getResource(...)`, ...): the file in `lib/resources/` of the package,
  // `test/resources/` first for test files, like the test classpath.
  // `file:` paths are relative to the package directory (where the app is
  // run).
  _Target? _resourceTarget(String path, String value) {
    final match = _resourceLocation.firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    final location = match.group(2)!;
    if (location.endsWith('/')) {
      return null; // a directory, like `resources:/config/`
    }
    final package = _packageRoot(path);
    final List<String> searched;
    if (match.group(1) == 'asset') {
      // A Flutter asset key (spring_boot_starter_flutter), relative to the
      // package; other packages' assets (`packages/...`) are not followed.
      final key = location.replaceFirst(RegExp('^/+'), '');
      if (key.startsWith('packages/')) {
        return null;
      }
      searched = ['$package/$key'];
    } else if (match.group(1) == 'file') {
      searched = [
        if (File(location).isAbsolute) location else '$package/$location',
      ];
    } else {
      final relative = location.replaceFirst(RegExp('^/+'), '');
      searched = [
        if (path
            .substring(package.length)
            .replaceAll(r'\', '/')
            .startsWith('/test/'))
          '$package/test/resources/$relative',
        '$package/lib/resources/$relative',
      ];
    }
    return _ResourceTarget(value.trim(), [
      for (final candidate in searched)
        if (File(candidate).existsSync()) candidate,
    ], searched);
  }

  final _packageRoots = <String, String>{};

  /// The root directory of the package of the file [path].
  String packageRootOf(String path) => _packageRoot(path);

  // The nearest directory with a pubspec.yaml (else the workspace root).
  String _packageRoot(String path) {
    final directory = File(path).parent.path;
    return _packageRoots[directory] ??= () {
      var current = Directory(directory);
      while (true) {
        if (File('${current.path}/pubspec.yaml').existsSync()) {
          return current.path;
        }
        final parent = current.parent;
        if (parent.path == current.path ||
            !roots.any((root) => parent.path.startsWith(root))) {
          break;
        }
        current = parent;
      }
      return roots.firstWhere(path.startsWith, orElse: () => directory);
    }();
  }

  // In `#{...}`: `@name` and a leading `name` refer to beans.
  _Target? _expressionTarget(String source, TemplatePart part, int relative) {
    final expression = source.substring(part.innerStart, part.innerEnd);
    final at = relative - part.innerStart;
    if (_spel.hover(expression, at, beanPart: false) case final member?) {
      return _TextTarget(member);
    }
    final List<Token> tokens;
    try {
      tokens = Tokenizer(expression).process();
    } on Object {
      return null;
    }
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.kind != TokenKind.identifier ||
          at < token.start ||
          at > token.end) {
        continue;
      }
      final previous = i > 0 ? tokens[i - 1].kind : null;
      final name = token.data ?? expression.substring(token.start, token.end);
      final isBean =
          previous == TokenKind.beanRef ||
          (previous == null || _startsPath(previous)) &&
              (i + 1 >= tokens.length ||
                  tokens[i + 1].kind != TokenKind.lparen);
      if (isBean && beansNamed(name).isNotEmpty) {
        return _BeanTarget(beansNamed(name), "Bean '$name'");
      }
      if (previous == TokenKind.beanRef) {
        return _BeanTarget(const [], "Bean '$name'");
      }
    }
    return null;
  }

  static bool _startsPath(TokenKind previous) =>
      previous != TokenKind.dot &&
      previous != TokenKind.safeNavi &&
      previous != TokenKind.hash;

  // A type at an injection point: constructor or `@Bean` parameter, field or
  // setter of a bean, or a `getBean<T>()` type argument.
  _Target? _typeTarget(NamedType type) {
    final beanType = _beanType(type);
    if (beanType == null) {
      return null;
    }
    final typeArguments = type.parent;
    if (typeArguments is TypeArgumentList &&
        typeArguments.parent is MethodInvocation &&
        _beanLookupMethods.contains(
          (typeArguments.parent! as MethodInvocation).methodName.name,
        )) {
      return _beanTargetFor(beanType, null);
    }
    if (_widgetRecordField(type) case (final owner, final fieldName)) {
      final beans = beansOfType(beanType, from: _scope);
      // A named field picks among several beans by its name.
      final named = [
        if (fieldName != null && beans.length > 1)
          for (final bean in beans)
            if (bean.matches(fieldName)) bean,
      ];
      return _BeanTarget(
        named.isNotEmpty ? named : beans,
        'Beans of type $beanType (record of $owner)',
      );
    }
    final parameter = type.thisOrAncestorOfType<FormalParameter>();
    if (parameter != null) {
      if (_hasAnnotation(parameter.metadata, 'Value') ||
          !_isInjectedParameter(parameter)) {
        return null;
      }
      return _beanTargetFor(beanType, _qualifierOf(parameter.metadata));
    }
    final field = type.thisOrAncestorOfType<FieldDeclaration>();
    if (field != null && !field.isStatic) {
      if (_hasAnnotation(field.metadata, 'Value') ||
          !_isBeanClass(field.thisOrAncestorOfType<ClassDeclaration>())) {
        return null;
      }
      return _beanTargetFor(beanType, _qualifierOf(field.metadata));
    }
    return null;
  }

  // A field of the bean record of a spring_boot_starter_flutter widget:
  // `SpringStatelessWidget<(Basket, {Clock utc})>`,
  // `SpringStatefulWidget<...>`, `SpringState<W, (...)>`. The owner type and
  // the field's name (named fields), or `null` for any other type.
  static (String, String?)? _widgetRecordField(NamedType type) {
    final field = type.parent;
    final String? fieldName;
    if (field is RecordTypeAnnotationPositionalField) {
      fieldName = null;
    } else if (field is RecordTypeAnnotationNamedField) {
      fieldName = field.name.lexeme;
    } else {
      return null;
    }
    final record = type.thisOrAncestorOfType<RecordTypeAnnotation>();
    final arguments = record?.parent;
    // `typedef BasketPageBeans = (Basket, Clock);` used as
    // `SpringStatefulWidget<BasketPageBeans>` in the same file.
    if (arguments is GenericTypeAlias) {
      final widget = _widgetUsing(arguments.name.lexeme, arguments.root);
      return widget == null ? null : (widget, fieldName);
    }
    final owner = arguments?.parent;
    if (arguments is! TypeArgumentList ||
        owner is! NamedType ||
        !_springWidgetTypes.contains(owner.name.lexeme)) {
      return null;
    }
    return (owner.name.lexeme, fieldName);
  }

  // The Spring widget type that takes the record type [alias] as its beans
  // somewhere in [unit], or null.
  static String? _widgetUsing(String alias, AstNode unit) {
    final finder = _AliasUse(alias);
    unit.accept(finder);
    return finder.widget;
  }

  static const _springWidgetTypes = {
    'SpringStatelessWidget',
    'SpringStatefulWidget',
    'SpringState',
  };

  // The bean type for an injection point type: `T` for `T`, `List<T>`,
  // `Set<T>`, `ObjectProvider<T>`, `Map<String, T>`.
  String? _beanType(NamedType type) {
    final name = type.name.lexeme;
    final arguments = type.typeArguments?.arguments ?? const [];
    if (_containers.contains(name) && arguments.isNotEmpty) {
      final inner = arguments.last;
      return inner is NamedType ? inner.name.lexeme : null;
    }
    // Clicked on `T` inside `List<T>`: still T.
    return name;
  }

  bool _isInjectedParameter(FormalParameter parameter) {
    final list = parameter.thisOrAncestorOfType<FormalParameterList>();
    final owner = list?.parent;
    final classNode = parameter.thisOrAncestorOfType<ClassDeclaration>();
    if (owner is ConstructorDeclaration) {
      return _isBeanClass(classNode);
    }
    if (owner is PrimaryConstructorDeclaration) {
      return _isBeanClass(classNode);
    }
    if (owner is MethodDeclaration) {
      // `@Bean` method parameters, `@Autowired` methods and setters.
      return _hasAnnotation(owner.metadata, 'Bean') ||
          _hasAnnotation(owner.metadata, 'Autowired');
    }
    return false;
  }

  bool _isBeanClass(ClassDeclaration? node) {
    if (node == null) {
      return false;
    }
    final names = {for (final a in node.metadata) annotationName(a)};
    return names.any(stereotypes.contains) || names.contains('Configurable');
  }

  NamedType? _fieldType(FieldFormalParameter parameter) {
    final explicit = parameter.type;
    if (explicit is NamedType) {
      return explicit;
    }
    final classNode = parameter.thisOrAncestorOfType<ClassDeclaration>();
    for (final member in classNode?.body.members ?? <ClassMember>[]) {
      if (member is FieldDeclaration) {
        for (final variable in member.fields.variables) {
          if (variable.name.lexeme == parameter.name.lexeme) {
            final type = member.fields.type;
            return type is NamedType ? type : null;
          }
        }
      }
    }
    return null;
  }

  static bool _hasAnnotation(List<Annotation> annotations, String name) =>
      annotations.any((a) => annotationName(a) == name);

  static String? _qualifierOf(List<Annotation> annotations) {
    for (final annotation in annotations) {
      if (annotationName(annotation) == 'Qualifier') {
        return stringValue(positionalArgument(annotation));
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Metadata, config files and completion
  // ---------------------------------------------------------------------

  /// The Spring metadata that applies to the file [path]: its package's and
  /// those of all the dependencies.
  MetadataView metadataFor(String path) => metadata.viewFor(_packageRoot(path));

  /// The known keys for the package of [path]: the properties, hints and
  /// theme of the metadata, plus keys some code of the package reads.
  Schema schemaFor(String path) {
    final root = _packageRoot(path);
    final view = metadata.viewFor(root);
    final cached = _schemas[root];
    if (cached != null &&
        cached.$1 == view.version &&
        cached.$2 == _generation) {
      return cached.$3;
    }
    final schema = Schema.build(
      view,
      codeKeys: (_codeKeys ??= _collectCodeKeys())[root] ?? const {},
    );
    _schemas[root] = (view.version, _generation, schema);
    return schema;
  }

  // The keys the code of each package reads: `${key}` in annotation
  // strings, `@ConditionalOnProperty('key')`, `getProperty('key')`. They
  // are known to the editor for completion and hovers, but never make a
  // key "unknown" or "known" for the checks: only the metadata does.
  Map<String, Set<String>> _collectCodeKeys() {
    final result = <String, Set<String>>{};
    for (final file in _files.values) {
      final root = _packageRoot(file.path);
      final strings = <SimpleStringLiteral>[];
      file.unit.accept(_StringCollector(strings));
      void add(String key) {
        if (RegExp(r'^[A-Za-z][\w.\-]*$').hasMatch(key)) {
          (result[root] ??= {}).add(key);
        }
      }

      for (final literal in strings) {
        final ref = _stringRef(literal);
        final value = literal.value;
        if (ref.annotation == 'ConditionalOnProperty' ||
            ref.annotation == 'ConditionalOnBooleanProperty' ||
            ref.method != null && _propertyMethods.contains(ref.method)) {
          add(value);
        } else if (ref.annotation != null && value.contains(r'${')) {
          for (final part in scanTemplate(value)) {
            if (part.kind == TemplatePartKind.placeholder && !part.unclosed) {
              add(part.inner(value));
            }
          }
        }
      }
    }
    return result;
  }

  /// The entries of the config files that apply to [path]: those of its own
  /// package, and those of the dependencies' `lib/resources` (their themes
  /// are what `$` references may point into).
  List<PropertyEntry> configEntries(String path) {
    final package = _packageRoot(path);
    final view = metadata.viewFor(package);
    final seen = <String>{};
    final result = <PropertyEntry>[];
    for (final MapEntry(key: file, value: entries) in _properties.entries) {
      if (_packageRoot(file) == package) {
        seen.add(file);
        result.addAll(entries);
      }
    }
    for (final root in view.packageRoots.values) {
      if (root == package) {
        continue;
      }
      for (final entry in _dependencyConfig(root)) {
        if (!seen.contains(entry.path) || _properties[entry.path] == null) {
          result.add(entry);
        }
      }
    }
    return result;
  }

  final _dependencyFiles = <String, (DateTime, List<PropertyEntry>)>{};

  // The config files under `lib/resources` of a dependency, re-listed at
  // most every few seconds.
  List<PropertyEntry> _dependencyConfig(String root) {
    final cached = _dependencyFiles[root];
    final now = DateTime.now();
    if (cached != null && now.difference(cached.$1).inSeconds < 5) {
      return cached.$2;
    }
    final entries = <PropertyEntry>[];
    final directory = Directory('$root/lib/resources');
    if (directory.existsSync()) {
      try {
        for (final entity in directory.listSync(recursive: true)) {
          if (entity is! File || !isConfigFile(entity.path)) {
            continue;
          }
          if (_properties[entity.path] case final known?) {
            entries.addAll(known);
            continue;
          }
          final text = entity.readAsStringSync();
          entries.addAll(
            _isYaml(entity.path)
                ? parseYamlProperties(entity.path, text)
                : parseProperties(entity.path, text),
          );
        }
      } on FileSystemException {
        // A directory being rewritten: next time.
      }
    }
    _dependencyFiles[root] = (now, entries);
    return entries;
  }

  /// Every key a config file of [path]'s package may set, for `${}`
  /// completion: the properties of the metadata and the keys in use.
  List<String> knownKeys(String path) {
    final keys = <String>{};
    void walk(SchemaNode node, List<String> prefix) {
      for (final child in node.named) {
        final next = [...prefix, child.name];
        if (child.prop != null && !child.prop!.theme) {
          keys.add(next.join('.'));
        }
        walk(child, next);
      }
    }

    walk(schemaFor(path).root, const []);
    for (final entry in configEntries(path)) {
      if (!entry.key.startsWith('spring.flutter.theme')) {
        keys.add(entry.key);
      }
    }
    return keys.toList()..sort();
  }

  /// The profile names known to the package of [path]: those the metadata
  /// lists, the `application-<name>` files and the profiles the config
  /// activates.
  Set<String> knownProfiles(String path) {
    final package = _packageRoot(path);
    final result = {...metadataFor(path).profiles};
    for (final file in _properties.keys) {
      if (_packageRoot(file) != package) {
        continue;
      }
      final match = RegExp(
        r'^application-(.+)\.(?:properties|ya?ml)$',
      ).firstMatch(file.split(RegExp(r'[\\/]')).last);
      if (match != null) {
        result.add(match.group(1)!);
      }
    }
    for (final entry in configEntries(path)) {
      if (const {
        'spring.profiles.active',
        'spring.profiles.include',
        'spring.config.activate.on-profile',
      }.contains(entry.key)) {
        if (entry.value.contains(r'${')) {
          continue;
        }
        // `a, b` or an expression such as `!web & (mobile | spa)`.
        for (final match in RegExp(
          r'[A-Za-z0-9_][\w\-.]*',
        ).allMatches(entry.value)) {
          result.add(match.group(0)!);
        }
      }
    }
    return result;
  }

  /// SpEL problems of the beans and members in [expression] (offsets inside
  /// it); [path] says which package's metadata counts.
  List<SpelIssue> spelIssues(String path, String expression) {
    try {
      SpelExpressionParser().parseExpression(expression);
    } on SpelParseException catch (error) {
      final at = error.position < 0 ? 0 : error.position;
      return [
        SpelIssue(
          at.clamp(0, expression.length),
          (at + 1).clamp(0, expression.length),
          'SpEL: ${error.message}',
        ),
      ];
    } on Object {
      return const []; // tokenizer errors: the parser reports them
    }
    return _spel.issues(expression, complete: metadataFor(path).complete);
  }

  /// The hover of the bean or member at [at] of [expression].
  String? spelHover(String path, String expression, int at) =>
      _spel.hover(expression, at);

  /// Where the bean at [at] of [expression] is declared.
  List<SourceRange> spelDefinition(String path, String expression, int at) => [
    for (final bean in _spel.definition(expression, at))
      if (bean.path.isNotEmpty) _beanRange(bean),
  ];

  /// SpEL completion for the text [prefix] of an expression before the
  /// cursor: the offset in it where the replaced word starts, and the items.
  (int, List<Completion>)? spelComplete(String path, String prefix) =>
      _spel.complete(prefix);

  /// The text of the file at [path]: the open document's, else the file on
  /// disk; `null` when it cannot be read.
  String? textOf(String path) {
    if (path.endsWith('.dart')) {
      return file(path)?.text;
    }
    if (_configOverlays[path] case final open?) {
      return open;
    }
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Completion proposals at [offset] of the file [path] (a Dart file or a
  /// config file); `null` when there is nothing to propose.
  CompletionResult? completion(String path, int offset) {
    if (isConfigFile(path)) {
      final text = textOf(path);
      return text == null ? null : _config.completion(path, text, offset);
    }
    return _dartCompletion(path, offset);
  }

  // Inside an annotation string: `${key}`, `#{@bean.member}`, profile names,
  // bean names and property keys.
  CompletionResult? _dartCompletion(String path, int offset) {
    final file = this.file(path);
    if (file != null) {
      if (_query.completion(file, path, offset) case final result?) {
        return result;
      }
    }
    final node = file?.nodeAt(offset);
    if (file == null ||
        node is! SimpleStringLiteral ||
        offset < node.contentsOffset ||
        offset > node.contentsEnd) {
      return null;
    }
    final ref = _stringRef(node);
    final before = file.text.substring(ref.contentStart, offset);
    if (before.contains('\n')) {
      return null;
    }
    SourceRange rangeFrom(int start) {
      final from = file.lineInfo.getLocation(start);
      final to = file.lineInfo.getLocation(offset);
      return SourceRange(
        path,
        from.lineNumber - 1,
        from.columnNumber - 1,
        to.lineNumber - 1,
        to.columnNumber - 1,
      );
    }

    final placeholder = RegExp(r'\$\{([^}:]*)$').firstMatch(before);
    if (placeholder != null && ref.annotation != null) {
      return CompletionResult(
        rangeFrom(offset - placeholder.group(1)!.length),
        [
          for (final key in knownKeys(path))
            Completion(key, detail: 'property'),
        ],
      );
    }
    final spel = RegExp(r'#\{([^}]*)$').firstMatch(before);
    if (spel != null && ref.annotation != null) {
      final result = spelComplete(path, spel.group(1)!);
      return result == null
          ? null
          : CompletionResult(
              rangeFrom(ref.contentStart + spel.start + 2 + result.$1),
              result.$2,
            );
    }
    final word = RegExp(r'[\w.\-]*$').firstMatch(before)!;
    final from = rangeFrom(offset - word.group(0)!.length);
    switch (ref.annotation) {
      case 'Profile':
        return CompletionResult(from, [
          for (final name in knownProfiles(path).toList()..sort())
            Completion(name, kind: 20, detail: 'profile'),
        ]);
      case 'Qualifier' || 'DependsOn' || 'ConditionalOnBean':
        return CompletionResult(from, [
          for (final bean in beans)
            Completion(bean.name, kind: 6, detail: bean.typeName),
        ]);
      case 'ConditionalOnProperty' || 'ConditionalOnBooleanProperty':
        return CompletionResult(from, [
          for (final key in knownKeys(path))
            Completion(key, detail: 'property'),
        ]);
    }
    return null;
  }

  /// Notes about Spring metadata that is missing for the package of [path]
  /// (its own, or a dependency's): one information line at the top of the
  /// file telling to run `build_runner`. Empty when nothing is missing or
  /// the file is not part of a Spring package.
  List<Problem> metadataNotes(String path) {
    if (!path.endsWith('.dart') && !isConfigFile(path)) {
      return const [];
    }
    final view = metadataFor(path);
    final name = view.packageName;
    if (name == null || view.packageRoot == null) {
      return const [];
    }
    final range = SourceRange(path, 0, 0, 0, 1);
    if (view.missing.contains(name)) {
      return [
        Problem(
          range,
          'No Spring metadata for $name: run build_runner '
          '(`dart run build_runner build`) to get completion, hovers and '
          'checks for keys, beans and the theme',
          info: true,
        ),
      ];
    }
    if (view.missing.isNotEmpty) {
      return [
        Problem(
          range,
          'No Spring metadata in ${view.missing.join(', ')}: their keys and '
          'beans are not known here (they need a version with '
          '`lib/spring_gen/spring_metadata.json`)',
          info: true,
        ),
      ];
    }
    return const [];
  }

  List<Problem> _configProblems(String path) {
    final text = textOf(path);
    return text == null ? const [] : _config.problems(path, text);
  }

  // `@Profile('x')`: a name that no metadata, profile file or setting knows.
  // Only checked when the package has metadata of its own, else the name
  // may be declared where the editor cannot see.
  void _profileProblems(DartFile file, List<Problem> problems) {
    if (!metadata.hasMetadata(_packageRoot(file.path))) {
      return;
    }
    final strings = <SimpleStringLiteral>[];
    file.unit.accept(_StringCollector(strings));
    Set<String>? known;
    for (final literal in strings) {
      final ref = _stringRef(literal);
      if (ref.annotation != 'Profile') {
        continue;
      }
      known ??= {...knownProfiles(file.path), 'default'};
      final source = file.text.substring(ref.contentStart, ref.contentEnd);
      for (final match in RegExp(r'[A-Za-z0-9_][\w\-.]*').allMatches(source)) {
        final name = match.group(0)!;
        if (known.contains(name)) {
          continue;
        }
        final guess = didYouMean(name, known.toList());
        problems.add(
          Problem(
            rangeOf(
              file,
              ref.contentStart + match.start,
              ref.contentStart + match.end,
            ),
            "Unknown profile '$name': no application-$name file and the "
            'metadata does not list it (known: '
            "${(known.toList()..sort()).join(', ')})"
            "${guess == null ? '' : ". Did you mean '$guess'?"}",
          ),
        );
      }
    }
  }

  // The candidates that compete: those that back off when another bean of
  // the type exists do not (unless all of them do), nor do beans of one
  // name (the later one replaces the earlier), nor beans whose profiles can
  // never be active together.
  static String _withProfiles(BeanInfo b) => b.profiles.isEmpty
      ? b.name
      : '${b.name} (profile ${b.profiles.join(', ')})';

  static List<BeanInfo> _ambiguous(List<BeanInfo> candidates) {
    final firm = [
      for (final bean in candidates)
        if (!bean.backsOff) bean,
    ];
    final pool = firm.isEmpty ? candidates : firm;
    if ({for (final bean in pool) bean.name}.length < 2) {
      return const [];
    }
    // Each limited to its own profile (`dev`, `prod`): alternatives, as
    // profiles are used in practice.
    final plain = RegExp(r'^[A-Za-z0-9_][\w\-.]*$');
    final alternatives = [
      for (final bean in pool)
        if (bean.profiles.length == 1 && plain.hasMatch(bean.profiles.single))
          bean.profiles.single,
    ];
    if (alternatives.length == pool.length &&
        alternatives.toSet().length == pool.length) {
      return const [];
    }
    final names = <String>{
      for (final bean in pool)
        for (final expression in bean.profiles)
          ...RegExp(r'[A-Za-z0-9_][\w\-.]*')
              .allMatches(expression)
              .map((m) => m.group(0)!),
    }.toList();
    if (names.length > 12) {
      return pool;
    }
    for (var mask = 0; mask < 1 << names.length; mask++) {
      final active = {
        for (var i = 0; i < names.length; i++)
          if (mask & (1 << i) != 0) names[i],
      };
      final together = [
        for (final bean in pool)
          if (profilesActive(bean.profiles, active)) bean,
      ];
      if ({for (final bean in together) bean.name}.length > 1) {
        return together;
      }
    }
    return const [];
  }

  // Constructor, `@Bean` and `@Autowired` parameters of beans: no bean of
  // the type is an error, several without `@Primary` or `@Qualifier` a
  // warning. All profiles are considered, since the active ones are only
  // known at run time; the message says so and shows each bean's profile.
  void _injectionProblems(DartFile file, List<Problem> problems) {
    final collector = _ParameterCollector();
    file.unit.accept(collector);
    final view = metadataFor(file.path);
    for (final parameter in collector.parameters) {
      if (parameter.defaultClause != null) {
        continue;
      }
      if (!_isInjectedParameter(parameter) ||
          _hasAnnotation(parameter.metadata, 'Value')) {
        continue;
      }
      final type = switch (parameter) {
        FieldFormalParameter() => _fieldType(parameter),
        _ => parameter.type is NamedType ? parameter.type! as NamedType : null,
      };
      if (type == null || type.question != null) {
        continue;
      }
      final name = type.name.lexeme;
      if (_containers.contains(name) ||
          _frameworkTypes.contains(name) ||
          !_classIndex.containsKey(name) ||
          _classIndex[name]!.any(
            (info) => info.annotationNames.any(
              (annotation) => !_plainAnnotations.contains(annotation),
            ),
          )) {
        // Not a plain type of the project: the framework provides it, or an
        // annotation of a dependency (a repository, a client) makes it a
        // bean the editor cannot see in the source.
        continue;
      }
      final qualifier = _qualifierOf(parameter.metadata);
      final candidates = beansOfType(
        name,
        qualifier: qualifier,
        from: file.path,
      );
      final token = parameter.name;
      final range = token != null
          ? rangeOf(file, token.offset, token.end)
          : rangeOf(file, type.offset, type.end);
      String considered() {
        final profiles = knownProfiles(file.path).toList()..sort();
        return profiles.isEmpty
            ? 'all profiles considered'
            : 'all profiles considered: ${profiles.join(', ')}';
      }

      if (candidates.isEmpty) {
        problems.add(
          Problem(
            range,
            'No bean of type $name'
            "${qualifier == null ? '' : " with qualifier '$qualifier'"} "
            '(${considered()})'
            "${view.complete ? '' : '; dependencies without Spring metadata '
                      'may provide it'}",
            error: view.complete,
          ),
        );
      } else if (_ambiguous(candidates).length > 1 &&
          qualifier == null &&
          !candidates.any((bean) => bean.primary) &&
          !candidates.any(
            (bean) => bean.matches(
              parameter.name?.lexeme.replaceFirst(RegExp('^_+'), '') ?? '',
            ),
          )) {
        problems.add(
          Problem(
            range,
            'Several beans of type $name and none is @Primary: '
            '${_ambiguous(candidates).map(_withProfiles).join(', ')}. '
            'Mark one @Primary or add @Qualifier (${considered()})',
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Highlighting and checks
  // ---------------------------------------------------------------------

  Iterable<_StringRef> _templateStrings(DartFile file) sync* {
    final strings = <SimpleStringLiteral>[];
    file.unit.accept(_StringCollector(strings));
    for (final literal in strings) {
      // The SQL of a repository's `@Query` is read by the query editor.
      if (_query.covers(file, literal.contentsOffset)) {
        continue;
      }
      final ref = _stringRef(literal);
      final value = literal.value;
      if (ref.annotation != null &&
              templateAnnotations.contains(ref.annotation) ||
          ref.annotation != null &&
              (value.contains(r'${') || value.contains('#{'))) {
        yield ref;
      }
    }
  }

  /// The semantic tokens of [path], sorted by position.
  ///
  /// In a Dart file: the placeholders and SpEL of annotation strings, the
  /// SpEL arguments of the cache annotations, pointcut expressions, and the
  /// parameters of closures where they are declared and used. In a config
  /// file ([isConfigFile]): the placeholders and SpEL of its values. Empty
  /// for other files. A token that would span lines is left out.
  List<SemanticToken> semanticTokens(String path) {
    if (!path.endsWith('.dart')) {
      return _configTokens(path);
    }
    final file = this.file(path);
    if (file == null) {
      return const [];
    }
    final tokens = <SemanticToken>[];
    void add(int start, int end, String type) {
      if (end <= start) {
        return;
      }
      final from = file.lineInfo.getLocation(start);
      final to = file.lineInfo.getLocation(end);
      if (from.lineNumber != to.lineNumber) {
        return; // tokens must not span lines
      }
      tokens.add(
        SemanticToken(
          from.lineNumber - 1,
          from.columnNumber - 1,
          end - start,
          semanticTokenTypes.indexOf(type),
        ),
      );
    }

    for (final ref in _templateStrings(file)) {
      _templateTokens(
        file.text.substring(ref.contentStart, ref.contentEnd),
        ref.contentStart,
        add,
      );
    }
    for (final ref in _spelArgumentStrings(file)) {
      _spelTokens(
        file.text.substring(ref.contentStart, ref.contentEnd),
        ref.contentStart,
        add,
      );
    }
    _query.tokens(file, add);
    for (final ref in _pointcutStrings(file)) {
      final base = ref.contentStart;
      final source = file.text.substring(ref.contentStart, ref.contentEnd);
      for (final part in scanPointcut(source)) {
        add(base + part.start, base + part.end, switch (part.kind) {
          PointcutPartKind.designator => 'keyword',
          PointcutPartKind.operator || PointcutPartKind.wildcard => 'operator',
          PointcutPartKind.type ||
          PointcutPartKind.declaringType ||
          PointcutPartKind.aspect => 'type',
          PointcutPartKind.annotation => 'class',
          PointcutPartKind.bean => 'variable',
          PointcutPartKind.member || PointcutPartKind.reference => 'method',
        });
      }
    }
    file.unit.accept(
      _ClosureParameters((start, end) => add(start, end, 'closureParameter')),
    );
    tokens.sort(
      (a, b) => a.line != b.line ? a.line - b.line : a.column - b.column,
    );
    return tokens;
  }

  // Tokens of the placeholders and expressions in [source], which starts at
  // [base] in the file.
  void _templateTokens(
    String source,
    int base,
    void Function(int start, int end, String type) add,
  ) {
    for (final part in scanTemplate(source)) {
      final s = base + part.start;
      if (part.kind == TemplatePartKind.placeholder) {
        add(s, base + part.innerStart, 'operator');
        add(base + part.innerStart, base + part.keyEnd!, 'property');
        if (!part.unclosed) {
          add(base + part.innerEnd, base + part.end, 'operator');
        }
        continue;
      }
      add(s, base + part.innerStart, 'keyword');
      _expressionTokens(source, part, base, add);
      if (!part.unclosed) {
        add(base + part.innerEnd, base + part.end, 'keyword');
      }
    }
  }

  // Placeholders and SpEL in the values of a config file, line by line;
  // comments left out (`#` / `!` lines of `.properties`, `#` after a space
  // in YAML).
  List<SemanticToken> _configTokens(String path) {
    if (!isConfigFile(path)) {
      return const [];
    }
    final String text;
    if (_configOverlays[path] case final open?) {
      text = open;
    } else {
      try {
        text = File(path).readAsStringSync();
      } on FileSystemException {
        return const [];
      }
    }
    final yaml = _isYaml(path);
    final tokens = <SemanticToken>[];
    final lines = text.split('\n');
    for (var row = 0; row < lines.length; row++) {
      final line = lines[row];
      final content = yaml ? _yamlContent(line) : _propertiesContent(line);
      if (!content.contains(r'${') && !content.contains('#{')) {
        continue;
      }
      _templateTokens(content, 0, (start, end, type) {
        if (end > start) {
          tokens.add(
            SemanticToken(
              row,
              start,
              end - start,
              semanticTokenTypes.indexOf(type),
            ),
          );
        }
      });
    }
    return tokens;
  }

  // A `.properties` line without a comment: comments are whole lines.
  static String _propertiesContent(String line) {
    final trimmed = line.trimLeft();
    return trimmed.startsWith('#') || trimmed.startsWith('!') ? '' : line;
  }

  // A YAML line up to its comment: `#` at the start or after a space,
  // outside quoted scalars. Unquoted, `key: #{...}` is a comment for YAML
  // too, so SpEL is only found in quotes.
  static String _yamlContent(String line) {
    String? quote;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (quote != null) {
        if (c == quote) {
          quote = null;
        }
      } else if ((c == '"' || c == "'") &&
          (i == 0 || ' \t:[{,-'.contains(line[i - 1]))) {
        quote = c; // a quoted scalar starts here, not an apostrophe
      } else if (c == '#' &&
          (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
        return line.substring(0, i);
      }
    }
    return line;
  }

  Iterable<_StringRef> _spelArgumentStrings(DartFile file) sync* {
    final strings = <SimpleStringLiteral>[];
    file.unit.accept(_StringCollector(strings));
    for (final literal in strings) {
      if (_isSpelArgument(literal)) {
        yield _stringRef(literal);
      }
    }
  }

  Iterable<_StringRef> _pointcutStrings(DartFile file) sync* {
    final strings = <SimpleStringLiteral>[];
    file.unit.accept(_StringCollector(strings));
    for (final literal in strings) {
      final ref = _stringRef(literal);
      if (ref.annotation != null &&
          pointcutAnnotations.contains(ref.annotation)) {
        yield ref;
      }
    }
  }

  void _expressionTokens(
    String source,
    TemplatePart part,
    int base,
    void Function(int start, int end, String type) add,
  ) {
    final expression = source.substring(part.innerStart, part.innerEnd);
    if (expression.contains(r'${')) {
      return; // placeholders are resolved first; tokens would be wrong
    }
    _spelTokens(expression, base + part.innerStart, add);
  }

  /// Calls [add] with the span (offsets from [offset]) and the token type of
  /// each piece of the SpEL [expression].
  void spelTokens(
    String expression,
    int offset,
    void Function(int start, int end, String type) add,
  ) => _spelTokens(expression, offset, add);

  // Tokens of the SpEL [expression] that starts at [offset] in the file.
  void _spelTokens(
    String expression,
    int offset,
    void Function(int start, int end, String type) add,
  ) {
    final List<Token> tokens;
    try {
      tokens = Tokenizer(expression).process();
    } on Object {
      return;
    }
    const keywords = {
      'true',
      'false',
      'null',
      'new',
      'and',
      'or',
      'not',
      'instanceof',
      'matches',
      'between',
      'eq',
      'ne',
      'lt',
      'le',
      'gt',
      'ge',
      'div',
      'mod',
    };
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final start = offset + token.start;
      final end = offset + token.end;
      final previous = i > 0 ? tokens[i - 1].kind : null;
      final next = i + 1 < tokens.length ? tokens[i + 1].kind : null;
      switch (token.kind) {
        case TokenKind.literalInt ||
            TokenKind.literalLong ||
            TokenKind.literalHexInt ||
            TokenKind.literalHexLong ||
            TokenKind.literalReal ||
            TokenKind.literalRealFloat:
          add(start, end, 'number');
        case TokenKind.literalString:
          add(start, end, 'string');
        case TokenKind.identifier:
          final name = expression.substring(token.start, token.end);
          if (name == 'T' && next == TokenKind.lparen) {
            add(start, end, 'keyword');
          } else if (keywords.contains(name.toLowerCase())) {
            add(start, end, 'keyword');
          } else if (previous == TokenKind.hash) {
            add(start - 1, end, 'variable');
          } else if (previous == TokenKind.beanRef ||
              previous == TokenKind.factoryBeanRef) {
            add(start - 1, end, 'class');
          } else if (i >= 2 &&
              tokens[i - 2].kind == TokenKind.identifier &&
              expression.substring(tokens[i - 2].start, tokens[i - 2].end) ==
                  'T' &&
              previous == TokenKind.lparen) {
            add(start, end, 'type');
          } else if (next == TokenKind.lparen) {
            add(start, end, 'method');
          } else {
            add(start, end, 'property');
          }
        case TokenKind.hash || TokenKind.beanRef || TokenKind.factoryBeanRef:
          break; // coloured with the following name
        case TokenKind.lparen ||
            TokenKind.rparen ||
            TokenKind.lsquare ||
            TokenKind.rsquare ||
            TokenKind.lcurly ||
            TokenKind.rcurly ||
            TokenKind.comma ||
            TokenKind.colon ||
            TokenKind.dot:
          break;
        case TokenKind.plus ||
            TokenKind.minus ||
            TokenKind.star ||
            TokenKind.div ||
            TokenKind.mod ||
            TokenKind.power ||
            TokenKind.not ||
            TokenKind.assign ||
            TokenKind.eq ||
            TokenKind.ne ||
            TokenKind.lt ||
            TokenKind.le ||
            TokenKind.gt ||
            TokenKind.ge ||
            TokenKind.and ||
            TokenKind.or ||
            TokenKind.qmark ||
            TokenKind.elvis ||
            TokenKind.safeNavi ||
            TokenKind.select ||
            TokenKind.selectFirst ||
            TokenKind.selectLast ||
            TokenKind.project ||
            TokenKind.inc ||
            TokenKind.dec ||
            TokenKind.instanceOf ||
            TokenKind.matches ||
            TokenKind.between:
          add(start, end, 'operator');
      }
    }
  }

  /// The problems of the Dart file [path], for the editor to underline;
  /// empty for other files.
  ///
  /// - an interpolated `'${key}'` in a [templateAnnotations] string (error:
  ///   write `r'${key}'`);
  /// - an unclosed placeholder or SpEL expression, or invalid SpEL (errors);
  /// - a `${key}` without a default that no config file and no property of
  ///   the test itself defines (warning). Not reported for a key that looks
  ///   like an environment variable (`PORT`) or for a nullable target;
  /// - an invalid pointcut, checked by the runtime's own parser with the
  ///   workspace's `@Pointcut` methods (error);
  /// - in a cache key or condition: invalid SpEL (error), or a `#name` that
  ///   is not a parameter of the method (warning, listing the parameters);
  /// - a message code that no bundle of the package defines, when the
  ///   package has bundles and does not use codes as default messages
  ///   (warning);
  /// - an `asset:` location whose file is missing or not declared under
  ///   `flutter: assets:` in `pubspec.yaml` (warning).
  List<Problem> problems(String path) {
    if (isConfigFile(path)) {
      return _configProblems(path);
    }
    final file = this.file(path);
    if (file == null) {
      return const [];
    }
    final problems = <Problem>[];
    final interpolations = <StringInterpolation>[];
    file.unit.accept(_InterpolationCollector(interpolations));
    for (final node in interpolations) {
      final annotation = node.thisOrAncestorOfType<Annotation>();
      if (annotation != null &&
          templateAnnotations.contains(annotationName(annotation))) {
        problems.add(
          Problem(
            rangeOf(file, node.offset, node.end),
            r'In Dart ${...} in a normal string is interpolation, not a '
            r"placeholder: use a raw string, r'${key}' (or escape: '\${key}')",
            error: true,
          ),
        );
      }
    }
    if (hasMessageBundles(file.path) &&
        !_codeAsDefault.contains(_packageRoot(file.path))) {
      final calls = _MessageCallCollector();
      file.unit.accept(calls);
      final added = _messagesAddedInCode(file.path);
      for (final code in calls.codes) {
        if (!added.contains(code.value) &&
            messages(code.value, from: file.path).isEmpty) {
          problems.add(
            Problem(
              rangeOf(file, code.contentsOffset, code.contentsEnd),
              "No message '${code.value}' in the message bundles "
              '(messages*.properties)',
            ),
          );
        }
      }
    }
    for (final ref in _templateStrings(file)) {
      final base = ref.contentStart;
      final source = file.text.substring(ref.contentStart, ref.contentEnd);
      for (final part in scanTemplate(source)) {
        final start = base + part.start;
        final end = base + part.end;
        if (part.unclosed) {
          problems.add(
            Problem(
              rangeOf(file, start, end),
              part.kind == TemplatePartKind.placeholder
                  ? "Unclosed placeholder: missing '}'"
                  : "Unclosed SpEL expression: missing '}'",
              error: true,
            ),
          );
          continue;
        }
        if (part.kind == TemplatePartKind.placeholder) {
          final key = part.inner(source);
          final hasDefault = part.keyEnd! < part.innerEnd;
          if (!hasDefault &&
              key.isNotEmpty &&
              !_looksLikeEnvironmentVariable(key) &&
              !_targetIsNullable(ref.literal) &&
              !declaredByMetadata(file.path, key) &&
              property(key, from: file).isEmpty) {
            problems.add(
              Problem(
                rangeOf(file, base + part.innerStart, base + part.keyEnd!),
                "Cannot resolve property '$key' in any properties file",
              ),
            );
          }
          continue;
        }
        final expression = source.substring(part.innerStart, part.innerEnd);
        if (expression.contains(r'${')) {
          continue;
        }
        try {
          SpelExpressionParser().parseExpression(expression);
          for (final issue in spelIssues(file.path, expression)) {
            problems.add(
              Problem(
                rangeOf(
                  file,
                  base + part.innerStart + issue.start,
                  base + part.innerStart + issue.end,
                ),
                issue.message,
                error: issue.error,
              ),
            );
          }
        } on SpelParseException catch (error) {
          final position = error.position < 0 ? 0 : error.position;
          final at = base + part.innerStart + position;
          problems.add(
            Problem(
              rangeOf(
                file,
                at.clamp(start, end),
                (at + 1).clamp(start, base + part.innerEnd),
              ),
              'SpEL: ${error.message}',
              error: true,
            ),
          );
        } on Object {
          // Other tokenizer errors are reported by the parser above.
        }
      }
    }
    problems
      ..addAll(_query.problems(file, path))
      ..addAll(_derived.problems(file, path));
    _pointcutProblems(file, problems);
    _spelArgumentProblems(file, problems);
    _assetProblems(file, problems);
    _profileProblems(file, problems);
    _injectionProblems(file, problems);
    for (final problem in containerProblems(file)) {
      problems.add(
        Problem(
          rangeOf(file, problem.start, problem.end),
          problem.message,
          error: true,
        ),
      );
    }
    return problems;
  }

  // `@Value('asset:...')` (spring_boot_starter_flutter), as the generator
  // checks it: the file must exist and be declared under `flutter: assets:`
  // in pubspec.yaml. Keys with placeholders or SpEL and other packages'
  // assets are not checked.
  void _assetProblems(DartFile file, List<Problem> problems) {
    final strings = <SimpleStringLiteral>[];
    file.unit.accept(_StringCollector(strings));
    for (final literal in strings) {
      final value = literal.value.trim();
      final annotation = literal.thisOrAncestorOfType<Annotation>();
      if (!value.startsWith('asset:') ||
          annotation == null ||
          annotationName(annotation) != 'Value' ||
          value.contains(r'${') ||
          value.contains('#{')) {
        continue;
      }
      final key = value
          .substring('asset:'.length)
          .replaceFirst(RegExp('^/+'), '');
      if (key.isEmpty || key.startsWith('packages/')) {
        continue;
      }
      final package = _packageRoot(file.path);
      final ref = _stringRef(literal);
      final range = rangeOf(file, ref.contentStart, ref.contentEnd);
      if (!File('$package/$key').existsSync()) {
        problems.add(Problem(range, 'No file $key in this package'));
        continue;
      }
      if (!declaredAsset(_pubspecAssets(package), key)) {
        final directory = key.contains('/')
            ? '${key.substring(0, key.lastIndexOf('/'))}/'
            : key;
        problems.add(
          Problem(
            range,
            '$key is not declared in pubspec.yaml, so the app would not '
            'contain it: add `- $directory` under `flutter: assets:`',
          ),
        );
      }
    }
  }

  final _pubspecs = <String, (DateTime, List<String>)>{};

  // The `flutter: assets:` entries of [package]'s pubspec.yaml (re-read
  // when it changes).
  List<String> _pubspecAssets(String package) {
    final file = File('$package/pubspec.yaml');
    if (!file.existsSync()) {
      return const [];
    }
    final modified = file.lastModifiedSync();
    final cached = _pubspecs[package];
    if (cached != null && cached.$1 == modified) {
      return cached.$2;
    }
    final assets = flutterAssets(file.readAsStringSync());
    _pubspecs[package] = (modified, assets);
    return assets;
  }

  // Cache keys and conditions: SpEL syntax, and `#name` must be a
  // parameter of the method (or `#root`, `#result`, `#p0`, `#a0`, ...).
  void _spelArgumentProblems(DartFile file, List<Problem> problems) {
    for (final ref in _spelArgumentStrings(file)) {
      final expression = file.text.substring(ref.contentStart, ref.contentEnd);
      final start = ref.contentStart;
      try {
        SpelExpressionParser().parseExpression(expression);
      } on SpelParseException catch (error) {
        final at = start + (error.position < 0 ? 0 : error.position);
        problems.add(
          Problem(
            rangeOf(
              file,
              at.clamp(start, ref.contentEnd),
              (at + 1).clamp(start, ref.contentEnd),
            ),
            'SpEL: ${error.message}',
            error: true,
          ),
        );
        continue;
      } on Object {
        continue;
      }
      final parameters = {
        for (final parameter in _parametersOf(ref.literal))
          ?parameter.name?.lexeme,
      };
      final tokens = Tokenizer(expression).process();
      for (var i = 1; i < tokens.length; i++) {
        final token = tokens[i];
        if (token.kind != TokenKind.identifier ||
            tokens[i - 1].kind != TokenKind.hash) {
          continue;
        }
        final name = expression.substring(token.start, token.end);
        if (parameters.contains(name) || _builtinSpelVariable.hasMatch(name)) {
          continue;
        }
        final known = parameters.isEmpty
            ? ''
            : '; parameters: ${parameters.map((p) => '#$p').join(', ')}';
        problems.add(
          Problem(
            rangeOf(file, start + token.start - 1, start + token.end),
            "Unknown variable '#$name'$known",
          ),
        );
      }
    }
  }

  // Pointcuts are parsed by the runtime's ExpressionPointcut, with the
  // `@Pointcut` methods of the project as named pointcuts, so the editor
  // rejects exactly what the application would.
  void _pointcutProblems(DartFile file, List<Problem> problems) {
    final strings = _pointcutStrings(file).toList();
    if (strings.isEmpty) {
      return;
    }
    final named = <String, String>{};
    for (final method in pointcutMethods) {
      named[method.name] = method.expression;
      named['${method.className}.${method.name}'] = method.expression;
    }
    for (final ref in strings) {
      try {
        ExpressionPointcut(ref.literal.value, namedPointcuts: named);
      } on FormatException catch (error) {
        // Point at the quoted name of the message when it is in this
        // string (`unknown pointcut 'audit'`), else at the whole string.
        final source = file.text.substring(ref.contentStart, ref.contentEnd);
        final quoted = RegExp("'([^']+)'").firstMatch(error.message)?[1];
        var start = ref.contentStart;
        var end = ref.contentEnd;
        for (final part in scanPointcut(source)) {
          if (part.text == quoted) {
            start = ref.contentStart + part.start;
            end = ref.contentStart + part.end;
            break;
          }
        }
        problems.add(
          Problem(rangeOf(file, start, end), error.message, error: true),
        );
      }
    }
  }

  // `@Value(...) String? motto`: a missing key gives `null`, not an error.
  static bool _targetIsNullable(SimpleStringLiteral literal) {
    final annotation = literal.thisOrAncestorOfType<Annotation>();
    final owner = annotation?.parent;
    TypeAnnotation? type;
    if (owner is FieldDeclaration) {
      type = owner.fields.type;
    } else if (owner is FieldFormalParameter) {
      type = owner.type;
      if (type == null) {
        final classNode = owner.thisOrAncestorOfType<ClassDeclaration>();
        for (final member in classNode?.body.members ?? <ClassMember>[]) {
          if (member is FieldDeclaration &&
              member.fields.variables.any(
                (v) => v.name.lexeme == owner.name.lexeme,
              )) {
            type = member.fields.type;
          }
        }
      }
    } else if (owner is FormalParameter) {
      type = owner.type;
    } else if (owner is MethodDeclaration && owner.isSetter) {
      type = owner.parameters?.parameters.firstOrNull?.type;
    }
    return type?.question != null;
  }

  // Whether the metadata declares the property [key] (so it is no typo,
  // and it has a value from the class's initial value).
  /// Whether the metadata of [path]'s package declares the property [key].
  bool declaredByMetadata(String path, String key) {
    final prop = schemaFor(path).nodeAt(splitKey(key))?.prop;
    return prop != null && !prop.fromCode;
  }

  static bool _looksLikeEnvironmentVariable(String key) =>
      RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(key);
}

sealed class _Target {}

final class _BeanTarget extends _Target {
  _BeanTarget(this.beans, this.description);

  final List<BeanInfo> beans;
  final String description;
}

/// A hover text with nothing to go to (a member of a bean in SpEL).
final class _TextTarget extends _Target {
  _TextTarget(this.text);

  final String text;
}

final class _PropertyTarget extends _Target {
  _PropertyTarget(this.key, this.entries, {this.message = false});

  final String key;
  final List<PropertyEntry> entries;

  /// Whether [key] is a message code (`context.message('key')`) rather than
  /// a property.
  final bool message;
}

/// Methods whose first positional argument is a message code:
/// `context.message('cart.empty')`, `messageSource.getMessage(...)`.
/// `Intl.message(...)` is not one.
const _messageMethods = {'message', 'getMessage'};

// The first argument of `context.message(...)` / `getMessage(...)`.
bool _isMessageCode(SimpleStringLiteral literal) {
  final invocation = literal.thisOrAncestorOfType<MethodInvocation>();
  return invocation != null &&
      _isMessageCall(invocation) &&
      identical(
        invocation.argumentList.arguments.first.argumentExpression,
        literal,
      );
}

// `context.message('code')`, `getMessage('code')`: a message method whose
// first argument is positional; not `Intl.message('text', name: ...)`.
bool _isMessageCall(MethodInvocation invocation) {
  final first = invocation.argumentList.arguments.firstOrNull;
  final target = invocation.target;
  return _messageMethods.contains(invocation.methodName.name) &&
      first != null &&
      first is! NamedArgument &&
      !(target is SimpleIdentifier && target.name == 'Intl');
}

// The first string of `addMessage('code', ...)` calls.
final class _AddedMessageCollector extends RecursiveAstVisitor<void> {
  final codes = <String>{};

  static Set<String> of(CompilationUnit unit) =>
      (_AddedMessageCollector()..visitCompilationUnit(unit)).codes;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final code = node.argumentList.arguments.firstOrNull?.argumentExpression;
    if (node.methodName.name == 'addMessage' && code is SimpleStringLiteral) {
      codes.add(code.value);
    }
    super.visitMethodInvocation(node);
  }
}

// Calls with a message code and no `defaultMessage:`.
final class _MessageCallCollector extends RecursiveAstVisitor<void> {
  final codes = <SimpleStringLiteral>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final arguments = node.argumentList.arguments;
    final code = arguments.firstOrNull?.argumentExpression;
    if (_isMessageCall(node) &&
        code is SimpleStringLiteral &&
        !arguments.any(
          (a) => a is NamedArgument && a.name.lexeme == 'defaultMessage',
        )) {
      codes.add(code);
    }
    super.visitMethodInvocation(node);
  }
}

/// A `@Pointcut` method of an `@Aspect` class: a named pointcut that other
/// pointcuts use as `name()` or `Aspect.name()`.
///
/// [SpringWorkspace.pointcutMethods] finds them. The pointcut check hands
/// them to the runtime's parser, so a reference to an unknown name is
/// reported, and go to definition on a reference jumps to the method.
final class PointcutMethod {
  /// The pointcut [name] of [className], defined by [expression], whose
  /// method name is at [offset] of [path].
  const PointcutMethod(
    this.className,
    this.name,
    this.expression,
    this.path,
    this.offset,
  );

  /// The aspect class that declares it: `AuditAspect` in
  /// `AuditAspect.pricing()`.
  final String className;

  /// The method's name, which is the pointcut's name.
  final String name;

  /// The pointcut expression written in `@Pointcut(...)`.
  final String expression;

  /// The file that declares it.
  final String path;

  /// The offset of the method name in [path], where navigation goes.
  final int offset;
}

final class _Declaration {
  _Declaration(this.path, this.offset, this.length, this.summary);

  final String path;
  final int offset;
  final int length;
  final String summary;
}

final class _DeclarationTarget extends _Target {
  _DeclarationTarget(this.description, this.declarations);

  final String description;
  final List<_Declaration> declarations;
}

final class _ResourceTarget extends _Target {
  _ResourceTarget(this.location, this.files, this.searched);

  final String location;
  final List<String> files;
  final List<String> searched;
}

final class _StringCollector extends RecursiveAstVisitor<void> {
  _StringCollector(this.strings);

  final List<SimpleStringLiteral> strings;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => strings.add(node);
}

final class _ParameterCollector extends RecursiveAstVisitor<void> {
  final parameters = <FormalParameter>[];

  @override
  void visitFormalParameterList(FormalParameterList node) {
    parameters.addAll(node.parameters);
    super.visitFormalParameterList(node);
  }
}

final class _InterpolationCollector extends RecursiveAstVisitor<void> {
  _InterpolationCollector(this.nodes);

  final List<StringInterpolation> nodes;

  @override
  void visitStringInterpolation(StringInterpolation node) {
    nodes.add(node);
    super.visitStringInterpolation(node);
  }
}

// Finds a Spring widget type with a given record type alias among its type
// arguments (`SpringState<W, BasketPageBeans>`).
final class _AliasUse extends RecursiveAstVisitor<void> {
  _AliasUse(this.alias);

  final String alias;
  String? widget;

  @override
  void visitNamedType(NamedType node) {
    final arguments = node.typeArguments?.arguments ?? const <TypeAnnotation>[];
    if (widget == null &&
        SpringWorkspace._springWidgetTypes.contains(node.name.lexeme) &&
        arguments.any((a) => a is NamedType && a.name.lexeme == alias)) {
      widget = node.name.lexeme;
    }
    super.visitNamedType(node);
  }
}

/// Reports the parameters of closures (`(alert) => ...`) where they are
/// declared and wherever the closure's body uses them: the
/// `closureParameter` tokens of [SpringWorkspace.semanticTokens].
///
/// Parameters of methods and of local or top-level functions are not
/// reported. A name declared again inside the closure (a local variable,
/// a loop or catch variable, a pattern variable, a parameter of a local
/// function) hides the parameter there. A member or label with the same
/// name (`x.alert`, `alert:`) is not a use of it.
final class _ClosureParameters extends RecursiveAstVisitor<void> {
  _ClosureParameters(this._add);

  final void Function(int start, int end) _add;

  // Innermost last: name -> whether it is a closure parameter.
  final _scopes = <Map<String, bool>>[];

  bool _isClosureParameter(String name) {
    for (final scope in _scopes.reversed) {
      if (scope[name] case final closure?) {
        return closure;
      }
    }
    return false;
  }

  void _declare(String name) {
    if (_scopes.isNotEmpty) {
      _scopes.last[name] = false;
    }
  }

  void _inScope(Map<String, bool> scope, void Function() body) {
    _scopes.add(scope);
    try {
      body();
    } finally {
      _scopes.removeLast();
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A local or top-level function is a FunctionExpression too; only
    // the others are closures.
    final closure = node.parent is! FunctionDeclaration;
    final scope = <String, bool>{};
    for (final parameter
        in node.parameters?.parameters ?? const <FormalParameter>[]) {
      final name = parameter.name;
      if (name == null) {
        continue;
      }
      scope[name.lexeme] = closure;
      if (closure) {
        _add(name.offset, name.end);
      }
    }
    node.typeParameters?.accept(this);
    node.parameters?.accept(this);
    _inScope(scope, () => node.body.accept(this));
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) => _inScope({
    for (final parameter
        in node.parameters?.parameters ?? const <FormalParameter>[])
      if (parameter.name case final name?) name.lexeme: false,
  }, () => super.visitMethodDeclaration(node));

  @override
  void visitBlock(Block node) => _inScope({}, () => super.visitBlock(node));

  // Loop, catch and pattern variables live only in their statement.
  @override
  void visitForStatement(ForStatement node) =>
      _inScope({}, () => super.visitForStatement(node));

  @override
  void visitForElement(ForElement node) =>
      _inScope({}, () => super.visitForElement(node));

  @override
  void visitCatchClause(CatchClause node) =>
      _inScope({}, () => super.visitCatchClause(node));

  @override
  void visitIfStatement(IfStatement node) =>
      _inScope({}, () => super.visitIfStatement(node));

  @override
  void visitIfElement(IfElement node) =>
      _inScope({}, () => super.visitIfElement(node));

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) =>
      _inScope({}, () => super.visitSwitchPatternCase(node));

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) =>
      _inScope({}, () => super.visitSwitchExpressionCase(node));

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _declare(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    _declare(node.name.lexeme);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitCatchClauseParameter(CatchClauseParameter node) {
    _declare(node.name.lexeme);
    super.visitCatchClauseParameter(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    _declare(node.name.lexeme);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_isClosureParameter(node.name) && _isReference(node)) {
      _add(node.offset, node.end);
    }
  }

  // Not a use of a variable: `x.alert`, `x?.alert`, `x.alert()`, `alert:`.
  static bool _isReference(SimpleIdentifier node) => switch (node.parent) {
    PropertyAccess(:final propertyName) => propertyName != node,
    PrefixedIdentifier(:final identifier) => identifier != node,
    MethodInvocation(:final methodName, :final realTarget) =>
      methodName != node || realTarget == null,
    Label() => false,
    _ => true,
  };
}

/// Whether a bean limited by the profile expressions [expressions] (any one
/// of them) is active when exactly the profiles [active] are: `dev`,
/// `!web`, `a & b`, `a | (b & !c)`. No expressions: always.
bool profilesActive(List<String> expressions, Set<String> active) {
  if (expressions.isEmpty) {
    return true;
  }
  return expressions.any((expression) => _evaluateProfile(expression, active));
}

bool _evaluateProfile(String expression, Set<String> active) {
  final tokens = RegExp(
    r'[A-Za-z0-9_][\w\-.]*|[!&|()]',
  ).allMatches(expression).map((m) => m.group(0)!).toList();
  var position = 0;
  late bool Function() or;

  bool atom() {
    if (position >= tokens.length) {
      return false;
    }
    final token = tokens[position++];
    if (token == '!') {
      return !atom();
    }
    if (token == '(') {
      final value = or();
      if (position < tokens.length && tokens[position] == ')') {
        position++;
      }
      return value;
    }
    return active.contains(token);
  }

  bool and() {
    var value = atom();
    while (position < tokens.length && tokens[position] == '&') {
      position++;
      final right = atom();
      value = value && right;
    }
    return value;
  }

  or = () {
    var value = and();
    while (position < tokens.length && tokens[position] == '|') {
      position++;
      final right = and();
      value = value || right;
    }
    return value;
  };
  return or();
}
