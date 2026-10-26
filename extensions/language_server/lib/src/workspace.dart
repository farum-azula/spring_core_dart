import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/flutter_assets.dart';
import 'package:dart_spring_language_server/src/pointcuts.dart';
import 'package:dart_spring_language_server/src/properties_index.dart';
import 'package:dart_spring_language_server/src/test_properties.dart';
import 'package:dart_spring_language_server/src/templates.dart';
import 'package:spring_core_dart/aop.dart' show ExpressionPointcut;
import 'package:spring_core_dart/expression.dart';
// ignore: implementation_imports
import 'package:spring_core_dart/src/expression/tokenizer.dart';

/// Directories never scanned.
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

/// Annotations whose strings may contain placeholders and SpEL.
const templateAnnotations = {
  'Value',
  'ConditionalOnExpression',
  'Cacheable',
  'CachePut',
  'CacheEvict',
  'Query',
  'Scheduled',
};

/// Annotation arguments that are one whole SpEL expression (no `#{}`),
/// like the keys and conditions of the cache annotations. Also inside
/// `@Caching(cacheable: [Cacheable(key: ...)])`.
const spelArguments = {
  'Cacheable': {'key', 'condition', 'unless'},
  'CachePut': {'key', 'condition', 'unless'},
  'CacheEvict': {'key', 'condition'},
};

/// SpEL variables that are always there in cache expressions.
final _builtinSpelVariable = RegExp(r'^(root|this|result|[pa]\d+)$');

/// Annotations whose string arguments are bean names.
const _beanNameAnnotations = {
  'Qualifier',
  'DependsOn',
  'ConditionalOnBean',
  'ConditionalOnMissingBean',
};

/// Methods whose type argument is a bean type.
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

/// Methods whose first string argument is a property key.
const _propertyMethods = {
  'getProperty',
  'getRequiredProperty',
  'containsProperty',
  'getPropertyAs',
};

/// Collections and providers whose element type is the bean type.
const _containers = {'List', 'Set', 'Iterable', 'ObjectProvider', 'Map'};

/// A location in a file (zero-based line and UTF-16 column).
final class SourceRange {
  /// Creates a range.
  const SourceRange(
    this.path,
    this.startLine,
    this.startColumn,
    this.endLine,
    this.endColumn,
  );

  /// File path.
  final String path;

  /// Start line.
  final int startLine;

  /// Start column.
  final int startColumn;

  /// End line.
  final int endLine;

  /// End column.
  final int endColumn;

  @override
  String toString() => '$path:$startLine:$startColumn';
}

/// A problem shown in the editor.
final class Problem {
  /// Creates a problem.
  const Problem(this.range, this.message, {this.error = false});

  /// Where.
  final SourceRange range;

  /// What.
  final String message;

  /// Error (otherwise warning).
  final bool error;
}

/// Semantic token types, in legend order.
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
];

/// One semantic token (absolute position, single line).
final class SemanticToken {
  /// Creates a token.
  const SemanticToken(this.line, this.column, this.length, this.type);

  /// Line.
  final int line;

  /// Column.
  final int column;

  /// Length.
  final int length;

  /// Index into [semanticTokenTypes].
  final int type;
}

/// A string in an annotation or call, with its source position.
final class _StringRef {
  _StringRef(this.literal, this.annotation, this.method);

  final SimpleStringLiteral literal;
  final String? annotation;
  final String? method;

  int get contentStart => literal.contentsOffset;
  int get contentEnd => literal.contentsEnd;
}

/// The project: Dart files, beans and properties files, kept up to date
/// from disk (by modification time) and from documents open in the editor.
final class SpringWorkspace {
  /// A workspace over [roots] (directories).
  SpringWorkspace(this.roots);

  /// Root directories.
  final List<String> roots;

  final _files = <String, DartFile>{};
  final _modified = <String, DateTime>{};
  final _overlays = <String, String>{};
  final _properties = <String, List<PropertyEntry>>{};
  final _propertiesModified = <String, DateTime>{};
  List<BeanInfo>? _beans;
  Map<String, List<ClassInfo>>? _classes;
  DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);

  /// Text of an open document (or `null` to fall back to disk).
  void setOverlay(String path, String? text) {
    if (text == null) {
      _overlays.remove(path);
      _modified.remove(path);
    } else {
      _overlays[path] = text;
      _files[path] = DartFile.parse(path, text);
    }
    _beans = null;
    _classes = null;
  }

  /// Re-reads changed files (at most every [interval] unless [force]).
  void refresh({
    bool force = false,
    Duration interval = const Duration(seconds: 2),
  }) {
    final now = DateTime.now();
    if (!force && now.difference(_lastScan) < interval) {
      return;
    }
    _lastScan = now;
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
    _properties.removeWhere((path, _) => !seenProperties.contains(path));
    if (changed || _beans == null) {
      _beans = null;
      _classes = null;
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
            (_isYaml(name) && _inResources(entity.path))) {
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
    _classes = null;
  }

  void _readProperties(File file) {
    final modified = file.lastModifiedSync();
    if (_propertiesModified[file.path] == modified) {
      return;
    }
    _propertiesModified[file.path] = modified;
    try {
      final text = file.readAsStringSync();
      _properties[file.path] = _isYaml(file.path)
          ? parseYamlProperties(file.path, text)
          : parseProperties(file.path, text);
    } on FileSystemException {
      _properties.remove(file.path);
    }
  }

  /// The parsed file at [path] (open document or disk).
  DartFile? file(String path) {
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

  /// Every type name [name] can be used as (itself and supertypes, by name).
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

  /// Annotation names that make a class a bean (base and custom).
  Set<String> get stereotypes => {
    ...baseStereotypes,
    for (final MapEntry(key: name, value: infos) in _classIndex.entries)
      if (infos.isNotEmpty &&
          supertypesOf(name).skip(1).any(baseStereotypes.contains))
        name,
  };

  /// Every bean found in the sources.
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
          continue;
        }
        final explicit = _unnamed(stereotype)
            ? null
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
              owner: info.name,
              contextGetter: _contextGetter(member.metadata, name),
            ),
          );
        }
      }
    }
    for (final bean in result) {
      bean.providedTypes = supertypesOf(bean.typeName);
    }
    return result;
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

  static List<String> _profiles(List<Annotation> annotations) => [
    for (final annotation in annotations)
      if (annotationName(annotation) == 'Profile')
        ...stringList(positionalArgument(annotation)),
  ];

  /// Beans that can be injected as [type] (with [qualifier]: only those
  /// answering to it), `@Primary` first.
  List<BeanInfo> beansOfType(String type, {String? qualifier}) {
    final candidates = [
      for (final bean in beans)
        if (bean.providedTypes.contains(type))
          if (qualifier == null || bean.matches(qualifier)) bean,
    ];
    candidates.sort((a, b) => (b.primary ? 1 : 0) - (a.primary ? 1 : 0));
    return candidates;
  }

  /// Beans named (or aliased, or qualified) [name].
  List<BeanInfo> beansNamed(String name) => [
    for (final bean in beans)
      if (bean.matches(name)) bean,
  ];

  /// The `@Pointcut` methods of `@Aspect` classes.
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

  /// Entries for [key] in every properties file (relaxed: `my-key`,
  /// `myKey` and `MY_KEY` match), `application.properties` first. In a
  /// test file ([from]), the properties the test sets for its context
  /// come first (see [testProperties]).
  List<PropertyEntry> property(String key, {DartFile? from}) {
    final wanted = _canonical(key);
    final variable = _environmentName(key);
    bool matches(PropertyEntry entry) => entry.environment
        ? _environmentName(entry.key) == variable
        : entry.key == key || _canonical(entry.key) == wanted;
    final bundles = _messageBundles();
    final result = [
      for (final MapEntry(key: path, value: entries) in _properties.entries)
        if (!bundles.contains(path))
          for (final entry in entries)
            if (matches(entry)) entry,
    ];
    result.sort((a, b) => _fileOrder(a).compareTo(_fileOrder(b)));
    return [
      if (from != null)
        for (final entry in testProperties(from))
          if (matches(entry)) entry,
      ...result,
    ];
  }

  // A property name or an environment variable without separators, as the
  // relaxed binding compares them: `shop.max-basket-size`,
  // `SHOP_MAX_BASKET_SIZE` and `SHOP_MAXBASKETSIZE` all give
  // `SHOPMAXBASKETSIZE`.
  static String _environmentName(String key) =>
      key.replaceAll(RegExp('[._-]'), '').toUpperCase();

  /// Entries whose key starts with [prefix] + `.`.
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

  /// The message [code] in every message bundle (`messages.properties`,
  /// `messages_ja.properties`, ... or the bundles of
  /// `spring.messages.basename`), the default bundle first; with [from],
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

  /// Whether the package of [path] has a message bundle.
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
  Map<String, String> _messageBundlePackages() {
    final basenames = <String, Set<String>>{};
    for (final MapEntry(key: path, value: entries) in _properties.entries) {
      for (final entry in entries) {
        if (entry.key == 'spring.messages.basename') {
          final names = basenames.putIfAbsent(_packageRoot(path), () => {});
          for (final name in entry.value.split(',')) {
            final trimmed = name.trim().replaceFirst('classpath:', '');
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
      )) {
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

  static String _canonical(String key) =>
      key.toLowerCase().replaceAll('-', '').replaceAll('_', '.');

  // ---------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------

  /// Go to definition at [offset] in [path].
  List<SourceRange> definition(String path, int offset) {
    final file = this.file(path);
    if (file == null) {
      return const [];
    }
    final target = _targetAt(file, offset);
    return switch (target) {
      _BeanTarget(:final beans) => [for (final bean in beans) _beanRange(bean)],
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
      null => const [],
    };
  }

  /// Markdown for a hover at [offset] in [path].
  String? hover(String path, int offset) {
    final file = this.file(path);
    if (file == null) {
      return null;
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
            '- ${bean.summary} — `${_shortPath(bean.path)}`',
        ].join('\n');
      case _PropertyTarget(:final key, :final entries, :final message):
        if (entries.isEmpty) {
          return message
              ? '**`$key`**: no such message in the message bundles'
              : '**`$key`**: not defined in any properties file';
        }
        return [
          message ? '**`$key`** (message)' : '**`$key`**',
          '',
          for (final entry in entries)
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
      case null:
        return null;
    }
  }

  SourceRange _beanRange(BeanInfo bean) {
    final file = this.file(bean.path);
    if (file == null) {
      return SourceRange(bean.path, 0, 0, 0, 0);
    }
    return rangeOf(file, bean.offset, bean.offset + bean.length);
  }

  /// [start]..[end] of [file] as lines and columns.
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
    return _BeanTarget(beansOfType(type, qualifier: qualifier), description);
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
    r'^(?:optional:)?(classpath\*?|file|asset):(.+)$',
  );

  // `classpath:legacy.properties` (in `@PropertySource`, `@Value`,
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
      return null; // a directory, like `classpath:/config/`
    }
    final package = _packageRoot(path);
    final List<String> searched;
    if (match.group(1) == 'asset') {
      // A Flutter asset key (spring_boot_starter_flutter), relative to the
      // package; other packages' assets (`packages/...`) are not followed.
      final key = location.replaceFirst(RegExp(r'^/+'), '');
      if (key.startsWith('packages/')) {
        return null;
      }
      searched = ['$package/$key'];
    } else if (match.group(1) == 'file') {
      searched = [
        if (File(location).isAbsolute) location else '$package/$location',
      ];
    } else {
      final relative = location.replaceFirst(RegExp(r'^/+'), '');
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
      final beans = beansOfType(beanType);
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
  // `SpringStatelessWidget<(Basket, {Clock utc})>`, `SpringStatefulWidget<...>`,
  // `SpringState<W, (...)>`. The owner type and the field's name (named
  // fields), or `null` for any other type.
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
    final owner = arguments?.parent;
    if (arguments is! TypeArgumentList ||
        owner is! NamedType ||
        !_springWidgetTypes.contains(owner.name.lexeme)) {
      return null;
    }
    return (owner.name.lexeme, fieldName);
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
  // Highlighting and checks
  // ---------------------------------------------------------------------

  Iterable<_StringRef> _templateStrings(DartFile file) sync* {
    final strings = <SimpleStringLiteral>[];
    file.unit.accept(_StringCollector(strings));
    for (final literal in strings) {
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

  /// Semantic tokens for placeholders and SpEL in [path].
  List<SemanticToken> semanticTokens(String path) {
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
      final base = ref.contentStart;
      final source = file.text.substring(ref.contentStart, ref.contentEnd);
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
    for (final ref in _spelArgumentStrings(file)) {
      _spelTokens(
        file.text.substring(ref.contentStart, ref.contentEnd),
        ref.contentStart,
        add,
      );
    }
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
    tokens.sort(
      (a, b) => a.line != b.line ? a.line - b.line : a.column - b.column,
    );
    return tokens;
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
        default:
          add(start, end, 'operator');
      }
    }
  }

  /// Problems in [path]: invalid SpEL, unknown property keys, placeholders
  /// written in interpolated (non-raw) strings.
  List<Problem> problems(String path) {
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
    if (hasMessageBundles(file.path)) {
      final calls = _MessageCallCollector();
      file.unit.accept(calls);
      for (final code in calls.codes) {
        if (messages(code.value, from: file.path).isEmpty) {
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
    _pointcutProblems(file, problems);
    _spelArgumentProblems(file, problems);
    _assetProblems(file, problems);
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
          .replaceFirst(RegExp(r'^/+'), '');
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
        problems.add(
          Problem(
            rangeOf(file, start + token.start - 1, start + token.end),
            "Unknown variable '#$name'"
            '${parameters.isEmpty ? '' : '; parameters: ${parameters.map((p) => '#$p').join(', ')}'}',
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

  static bool _looksLikeEnvironmentVariable(String key) =>
      RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(key);
}

sealed class _Target {}

final class _BeanTarget extends _Target {
  _BeanTarget(this.beans, this.description);

  final List<BeanInfo> beans;
  final String description;
}

final class _PropertyTarget extends _Target {
  _PropertyTarget(this.key, this.entries, {this.message = false});

  final String key;
  final List<PropertyEntry> entries;

  /// A message code (`context.message('key')`), not a property.
  final bool message;
}

/// Methods whose first argument is a message code.
const _messageMethods = {'message', 'getMessage'};

// The first argument of `context.message(...)` / `getMessage(...)`.
bool _isMessageCode(SimpleStringLiteral literal) {
  final parent = literal.parent;
  final invocation = parent is ArgumentList ? parent.parent : null;
  return invocation is MethodInvocation &&
      _messageMethods.contains(invocation.methodName.name) &&
      identical(
        invocation.argumentList.arguments.firstOrNull?.argumentExpression,
        literal,
      );
}

// Calls with a message code and no `defaultMessage:`.
final class _MessageCallCollector extends RecursiveAstVisitor<void> {
  final codes = <SimpleStringLiteral>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final arguments = node.argumentList.arguments;
    final code = arguments.firstOrNull?.argumentExpression;
    if (_messageMethods.contains(node.methodName.name) &&
        code is SimpleStringLiteral &&
        !arguments.any(
          (a) => a is NamedArgument && a.name.lexeme == 'defaultMessage',
        )) {
      codes.add(code);
    }
    super.visitMethodInvocation(node);
  }
}

/// A `@Pointcut` method of an `@Aspect` class.
final class PointcutMethod {
  /// Creates a pointcut method.
  const PointcutMethod(
    this.className,
    this.name,
    this.expression,
    this.path,
    this.offset,
  );

  /// The aspect class.
  final String className;

  /// Method name (the pointcut's name).
  final String name;

  /// The expression of `@Pointcut(...)`.
  final String expression;

  /// File path.
  final String path;

  /// Offset of the method name.
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

final class _InterpolationCollector extends RecursiveAstVisitor<void> {
  _InterpolationCollector(this.nodes);

  final List<StringInterpolation> nodes;

  @override
  void visitStringInterpolation(StringInterpolation node) {
    nodes.add(node);
    super.visitStringInterpolation(node);
  }
}
