import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:yaml/yaml.dart';

/// Property names an application can read, for the `dartDefines` of the
/// generated `springApplication`: `String.fromEnvironment` works on the web
/// and in AOT builds only as a `const` with a literal key, so every key a
/// `--dart-define` could set has to be known at build time.
///
/// Collected from the scanned libraries (every `${...}` placeholder in
/// annotation arguments, `@ConditionalOnProperty` names, the fields of
/// `@ConfigurationProperties` classes), the `application*` config files
/// of `lib/resources/` (their keys and placeholders) and a few properties
/// read before or around config data ([alwaysIncluded]). Each key also
/// gets its environment-variable form ([environmentForm]).
final class DartDefineKeys {
  final Set<String> _names = {};

  /// Keys always offered: profiles, banner, debug flags, logging, and the
  /// Flutter switch for the OS environment.
  static const alwaysIncluded = [
    'spring.profiles.active',
    'spring.profiles.include',
    'spring.main.banner-mode',
    'spring.flutter.scan-os-environment',
    'debug',
    'trace',
    'logging.level.root',
  ];

  /// The sorted keys: each property name and its environment form.
  List<String> get keys {
    final result = <String>{};
    for (final name in {...alwaysIncluded, ..._names}) {
      if (!_valid.hasMatch(name)) {
        continue;
      }
      result
        ..add(name)
        ..add(environmentForm(name));
    }
    return result.where((key) => key.isNotEmpty).toList()..sort();
  }

  // Characters a property name may have here (a define with anything else
  // is skipped rather than escaped into the generated code).
  static final _valid = RegExp(r'^[A-Za-z0-9_.\-\[\]]+$');

  /// The environment-variable form of a property name, like Spring Boot
  /// expects it: upper case, `.` → `_`, `-` removed, `[0]` → `_0_`
  /// (`shop.max-basket-size` → `SHOP_MAXBASKETSIZE`,
  /// `app.servers[0].host` → `APP_SERVERS_0_HOST`).
  static String environmentForm(String name) {
    final indexed = name.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\.?'),
      (match) => '_${match[1]}_',
    );
    var form = indexed.replaceAll('.', '_').replaceAll('-', '').toUpperCase();
    while (form.endsWith('_')) {
      form = form.substring(0, form.length - 1);
    }
    return form;
  }

  /// Adds the keys of every placeholder in [text]: `${a}`, `${a:default}`,
  /// nested ones (`${a:${b}}`) and placeholders in keys (`${${a}.b}` adds
  /// `a`).
  void addPlaceholders(String text) {
    var index = text.indexOf(r'${');
    while (index != -1) {
      final end = _closing(text, index + 2);
      if (end == -1) {
        return;
      }
      final inner = text.substring(index + 2, end);
      final separator = _separator(inner);
      final key = separator == -1 ? inner : inner.substring(0, separator);
      if (key.contains(r'${')) {
        addPlaceholders(key);
      } else {
        addName(key);
      }
      if (separator != -1) {
        addPlaceholders(inner.substring(separator + 1));
      }
      index = text.indexOf(r'${', end + 1);
    }
  }

  // The `}` closing the placeholder whose content starts at [start].
  static int _closing(String text, int start) {
    var depth = 1;
    for (var i = start; i < text.length; i++) {
      if (text.startsWith(r'${', i)) {
        depth++;
        i++;
      } else if (text[i] == '}') {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    return -1;
  }

  // The `:` between key and default, outside nested placeholders.
  static int _separator(String inner) {
    var depth = 0;
    for (var i = 0; i < inner.length; i++) {
      if (inner.startsWith(r'${', i)) {
        depth++;
        i++;
      } else if (inner[i] == '}') {
        depth--;
      } else if (inner[i] == ':' && depth == 0) {
        return i;
      }
    }
    return -1;
  }

  /// Adds a property name as it is.
  void addName(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      _names.add(trimmed);
    }
  }

  /// Adds the keys and placeholders of a config file of `lib/resources/`
  /// ([path] relative to it); only `application*.properties`, `.yml` and
  /// `.yaml` files are read.
  void addConfigFile(String path, String text) {
    final file = path.split('/').last;
    if (!file.startsWith('application')) {
      return;
    }
    if (file.endsWith('.properties')) {
      _addProperties(text);
    } else if (file.endsWith('.yml') || file.endsWith('.yaml')) {
      _addYaml(text);
    }
  }

  void _addProperties(String text) {
    var continued = false;
    for (final raw in text.split(RegExp(r'\r\n|\r|\n'))) {
      final line = raw.trimLeft();
      final wasContinued = continued;
      continued = _continues(raw);
      if (wasContinued) {
        addPlaceholders(line);
        continue;
      }
      if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
        continued = false;
        continue;
      }
      final separator = RegExp(r'(?<!\\)[=:\s]').firstMatch(line);
      final key = separator == null ? line : line.substring(0, separator.start);
      addName(key.replaceAll(r'\', ''));
      if (separator != null) {
        addPlaceholders(line.substring(separator.end));
      }
    }
  }

  // A line ending in an odd number of backslashes continues on the next.
  static bool _continues(String line) {
    var count = 0;
    for (var i = line.length - 1; i >= 0 && line[i] == r'\'; i--) {
      count++;
    }
    return count.isOdd;
  }

  void _addYaml(String text) {
    try {
      for (final document in loadYamlStream(text)) {
        _addYamlNode(document, '');
      }
    } on YamlException {
      // A broken file is reported when the application reads it.
    }
  }

  void _addYamlNode(Object? node, String prefix) {
    if (node is YamlNode) {
      node = node is YamlScalar ? node.value : node;
    }
    if (node is Map) {
      for (final MapEntry(:key, :value) in node.entries) {
        final name = prefix.isEmpty ? '$key' : '$prefix.$key';
        _addYamlNode(value, name);
      }
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        _addYamlNode(node[i], '$prefix[$i]');
      }
    } else {
      if (prefix.isNotEmpty) {
        addName(prefix);
      }
      if (node is String) {
        addPlaceholders(node);
      }
    }
  }

  /// Adds what [library] can read: placeholders in its annotations,
  /// `@ConditionalOnProperty` names and `@ConfigurationProperties` fields.
  void addLibrary(LibraryElement library) {
    for (final InterfaceElement element in [
      ...library.classes,
      ...library.mixins,
      ...library.enums,
      ...library.extensionTypes,
    ]) {
      _addInstance(element);
      for (final constructor in element.constructors) {
        _addExecutable(constructor);
      }
    }
    for (final extension in library.extensions) {
      _addInstance(extension);
    }
    for (final function in library.topLevelFunctions) {
      _addExecutable(function);
    }
    for (final Element variable in [
      ...library.topLevelVariables,
      ...library.getters,
      ...library.setters,
    ]) {
      _addAnnotations(variable);
    }
  }

  void _addInstance(InstanceElement element) {
    _addAnnotations(element);
    for (final Element member in [
      ...element.fields,
      ...element.getters,
      ...element.setters,
    ]) {
      _addAnnotations(member);
    }
    for (final method in element.methods) {
      _addExecutable(method);
    }
    if (element is ClassElement) {
      final annotation = _configurationProperties.firstAnnotationOf(element);
      if (annotation != null) {
        final prefix = annotation.getField('prefix')?.toStringValue() ?? '';
        _addBoundFields(element, prefix, {});
      }
    }
  }

  void _addExecutable(ExecutableElement element) {
    _addAnnotations(element);
    for (final parameter in element.formalParameters) {
      _addAnnotations(parameter);
    }
  }

  void _addAnnotations(Element element) {
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      if (value == null) {
        continue;
      }
      _addValue(value, 0);
      final type = value.type;
      if (type is InterfaceType &&
          _propertyConditions.contains(type.element.name) &&
          type.element.library.uri.toString().startsWith(
            'package:spring_boot_dart/',
          )) {
        _addConditionNames(value);
      }
    }
  }

  static const _propertyConditions = {
    'ConditionalOnProperty',
    'ConditionalOnBooleanProperty',
  };

  // `prefix` + `name` / `names`, joined like ConditionalOnProperty does.
  void _addConditionNames(DartObject condition) {
    final prefix = condition.getField('prefix')?.toStringValue() ?? '';
    final names = <String>[
      ?condition.getField('name')?.toStringValue(),
      for (final name
          in condition.getField('names')?.toListValue() ?? const <DartObject>[])
        ?name.toStringValue(),
    ];
    for (final name in names) {
      addName(
        prefix.isEmpty
            ? name
            : '${prefix.endsWith('.') ? prefix : '$prefix.'}$name',
      );
    }
  }

  // Strings with placeholders anywhere in a constant (fields, lists, maps,
  // records, nested objects).
  void _addValue(DartObject value, int depth) {
    if (depth > 8 || value.isNull) {
      return;
    }
    final string = value.toStringValue();
    if (string != null) {
      if (string.contains(r'${')) {
        addPlaceholders(string);
      }
      return;
    }
    final list = value.toListValue() ?? value.toSetValue()?.toList();
    if (list != null) {
      for (final element in list) {
        _addValue(element, depth + 1);
      }
      return;
    }
    final map = value.toMapValue();
    if (map != null) {
      for (final MapEntry(:key, :value) in map.entries) {
        if (key != null) _addValue(key, depth + 1);
        if (value != null) _addValue(value, depth + 1);
      }
      return;
    }
    final record = value.toRecordValue();
    if (record != null) {
      for (final field in [...record.positional, ...record.named.values]) {
        _addValue(field, depth + 1);
      }
      return;
    }
    final type = value.type;
    if (type is InterfaceType) {
      for (final element in [
        type.element,
        for (final supertype in type.element.allSupertypes) supertype.element,
      ]) {
        for (final field in element.fields) {
          final name = field.name;
          if (field.isStatic || name == null) {
            continue;
          }
          final fieldValue = value.getField(name);
          if (fieldValue != null) {
            _addValue(fieldValue, depth + 1);
          }
        }
      }
    }
  }

  // The bound names of a `@ConfigurationProperties` class: constructor
  // parameters (constructor binding) or public fields, in kebab case,
  // through nested classes of the same library.
  void _addBoundFields(
    InterfaceElement element,
    String prefix,
    Set<InterfaceElement> seen,
  ) {
    if (!seen.add(element) || seen.length > 8) {
      return;
    }
    final names = <String, DartType>{};
    for (final constructor in element.constructors) {
      if (constructor.isPublic && !constructor.isFactory) {
        for (final parameter in constructor.formalParameters) {
          final name = parameter.name;
          if (name != null) names[name] = parameter.type;
        }
      }
    }
    for (final field in element.fields) {
      final name = field.name;
      if (name != null && field.isPublic && !field.isStatic) {
        names.putIfAbsent(name, () => field.type);
      }
    }
    for (final MapEntry(key: name, value: type) in names.entries) {
      final property = '${prefix.isEmpty ? '' : '$prefix.'}${_kebab(name)}';
      addName(property);
      if (type is InterfaceType &&
          type.element.library.uri == element.library.uri) {
        _addBoundFields(type.element, property, seen);
      }
    }
  }

  static String _kebab(String name) => name.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => '-${match[0]!.toLowerCase()}',
  );
}

const _configurationProperties = TypeChecker.fromUrl(
  'package:spring_boot_dart/src/annotations.dart#ConfigurationProperties',
);
