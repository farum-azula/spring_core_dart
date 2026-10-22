import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/properties_index.dart';
import 'package:dart_spring_language_server/src/templates.dart';
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
};

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
            !name.endsWith('.beans.dart') &&
            !name.endsWith('.g.dart')) {
          dart.add(entity.path);
          _readDart(entity);
        } else if (name.endsWith('.properties')) {
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
      _properties[file.path] = parseProperties(
        file.path,
        file.readAsStringSync(),
      );
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
        result.add(
          BeanInfo(
            name: explicit ?? defaultBeanName(info.name),
            typeName: info.name,
            kind: BeanKind.component,
            path: file.path,
            offset: info.nameOffset,
            length: info.name.length,
            qualifiers: _qualifiers(info.annotations),
            primary: info.annotationNames.contains('Primary'),
            profiles: _profiles(info.annotations),
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
          result.add(
            BeanInfo(
              name:
                  stringValue(namedArgument(bean, 'name')) ??
                  member.name.lexeme,
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

  // ---------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------

  /// Entries for [key] in every properties file (relaxed: `my-key`,
  /// `myKey` and `MY_KEY` match), `application.properties` first.
  List<PropertyEntry> property(String key) {
    final wanted = _canonical(key);
    final result = [
      for (final entries in _properties.values)
        for (final entry in entries)
          if (entry.key == key || _canonical(entry.key) == wanted) entry,
    ];
    result.sort((a, b) => _fileOrder(a).compareTo(_fileOrder(b)));
    return result;
  }

  /// Entries whose key starts with [prefix] + `.`.
  List<PropertyEntry> propertiesWithPrefix(String prefix) {
    final wanted = '${_canonical(prefix)}.';
    return [
      for (final entries in _properties.values)
        for (final entry in entries)
          if (_canonical(entry.key).startsWith(wanted)) entry,
    ]..sort((a, b) => _fileOrder(a).compareTo(_fileOrder(b)));
  }

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
      case _PropertyTarget(:final key, :final entries):
        if (entries.isEmpty) {
          return '**`$key`**: not defined in any properties file';
        }
        return [
          '**`$key`**',
          '',
          for (final entry in entries)
            '- `${entry.fileName}`: `${entry.value}`',
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
    return null;
  }

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
    if (annotation != null && _beanNameAnnotations.contains(annotation)) {
      return _BeanTarget(beansNamed(value), "Bean '$value'");
    }
    if (annotation == 'ConditionalOnProperty') {
      return _PropertyTarget(value, property(value));
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
          return _PropertyTarget(key, property(key));
        }
        return _expressionTarget(source, part, relative);
      }
    }
    if (ref.method != null && _propertyMethods.contains(ref.method)) {
      return _PropertyTarget(value, property(value));
    }
    return null;
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
    tokens.sort(
      (a, b) => a.line != b.line ? a.line - b.line : a.column - b.column,
    );
    return tokens;
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
    final List<Token> tokens;
    try {
      tokens = Tokenizer(expression).process();
    } on Object {
      return;
    }
    final offset = base + part.innerStart;
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
              property(key).isEmpty) {
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
    return problems;
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
  _PropertyTarget(this.key, this.entries);

  final String key;
  final List<PropertyEntry> entries;
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
