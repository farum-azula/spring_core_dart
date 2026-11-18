import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/metadata_locations.dart';

// `@ConfigurationProperties` from spring_core_dart (matched by URL, so the
// generator does not depend on that package).
const _configurationProperties = TypeChecker.fromUrl(
  'package:spring_core_dart/src/context/property_annotations.dart#ConfigurationProperties',
);

// The editor-metadata annotations of spring_core_dart (matched by URL too).
const _range = TypeChecker.fromUrl(
  'package:spring_core_dart/src/context/property_annotations.dart#Range',
);
const _warnValues = TypeChecker.fromUrl(
  'package:spring_core_dart/src/context/property_annotations.dart#WarnValues',
);
const _propertyValues = TypeChecker.fromUrl(
  'package:spring_core_dart/src/context/property_annotations.dart#PropertyValues',
);

const _name = TypeChecker.fromUrl(
  'package:spring_core_dart/src/context/property_annotations.dart#Name',
);

const _autowired = TypeChecker.fromUrl(
  'package:spring_core_dart/src/context/annotations.dart#Autowired',
);

/// Reads the properties the `@ConfigurationProperties` classes of a library
/// bind: `prefix.field-name` for each field, constructor parameter or
/// setter, with nested classes (`prefix.nested.field`), lists
/// (`prefix.items[*].field`) and maps (`prefix.entries.*.field`).
///
/// An enum-typed property also adds a value hint, so an editor can offer
/// the constants (each with its `///` text). `@Range`, `@WarnValues` and
/// `@PropertyValues` on a field or parameter add `range`, `warn` and
/// values to the hint of the property.
///
/// Spring Boot's annotation processor does the same from the Java classes
/// and their Javadoc.
final class PropertyScanner {
  /// Creates a scanner; `astNodeFor` finds the declaration of a field, for
  /// its initial value.
  PropertyScanner(this._astNodeFor);

  final Future<AstNode?> Function(Fragment fragment) _astNodeFor;

  /// The properties found, in scan order.
  final properties = <Map<String, Object?>>[];

  /// The value hints made from the enums of enum-typed properties, by
  /// property name.
  final hints = <String, Map<String, Object?>>{};

  // Past this many levels a nested class is not followed any further.
  static const _maxDepth = 8;

  /// Adds the properties of every `@ConfigurationProperties` class and
  /// `@Bean` method of [library].
  Future<void> scanLibrary(LibraryElement library) async {
    for (final element in library.classes) {
      if (_configurationProperties.firstAnnotationOf(element) case final a?) {
        final prefix = ConstantReader(a).peek('prefix')?.stringValue;
        if (prefix != null) {
          await _bind(element, prefix, {element});
        }
      }
      for (final method in element.methods) {
        final annotation = _configurationProperties.firstAnnotationOf(method);
        final returned = method.returnType.element;
        final prefix = annotation == null
            ? null
            : ConstantReader(annotation).peek('prefix')?.stringValue;
        if (prefix != null && returned is ClassElement) {
          await _bind(returned, prefix, {returned});
        }
      }
    }
  }

  Future<void> _bind(
    ClassElement element,
    String prefix,
    Set<ClassElement> path,
  ) async {
    for (final member in await _members(element)) {
      await _add(member, prefix, path);
    }
  }

  Future<void> _add(
    _Member member,
    String prefix,
    Set<ClassElement> path,
  ) async {
    final name = prefix.isEmpty
        ? _propertyName(member)
        : '$prefix.${_propertyName(member)}';
    final type = member.type;
    final elementType = _elementType(type);
    // A list's items are `name[*]`, a map's values `name.*`.
    final isMap = _isMap(type);
    final isCollection = !isMap && elementType != type;
    final inner = isMap ? _mapValue(type) : elementType;
    final nested = _nestedClass(inner, member.owner);
    if (nested != null) {
      if (path.length < _maxDepth && !path.contains(nested)) {
        final key = isMap
            ? '$name.*'
            : isCollection
            ? '$name[*]'
            : name;
        await _bind(nested, key, {...path, nested});
      }
      return;
    }
    // A map of plain values is described by its entries: `name.*` (the type
    // is the value's); a list of plain values stays `name`, as a comma list
    // binds there too.
    final propertyName = isMap ? '$name.*' : name;
    if (properties.any((p) => p['name'] == propertyName)) {
      return;
    }
    properties.add({
      'name': propertyName,
      'type': (isMap ? inner : type).getDisplayString(),
      'description': documentation(member.documented),
      'default': member.defaultValue,
      'deprecated': deprecation(member.documented),
      'source': sourceOf(member.documented),
      'line': lineOf(member.documented),
      'class': member.owner.name,
    });
    _hint(member, isCollection ? '$name[*]' : propertyName, inner);
  }

  // The last name element: `@Name('import')` or the kebab-case Dart name.
  static String _propertyName(_Member member) {
    for (final element in member.annotated) {
      if (_name.firstAnnotationOf(element) case final a?) {
        if (ConstantReader(a).peek('value')?.stringValue case final v?) {
          return kebabCase(v);
        }
      }
    }
    return kebabCase(member.name);
  }

  // One hint per property: enum constants or `@PropertyValues`, `@Range`
  // and `@WarnValues`.
  void _hint(_Member member, String key, DartType inner) {
    final hint = <String, Object?>{'name': key};
    if (inner is InterfaceType && inner.element is EnumElement) {
      hint['values'] = enumHint(key, inner.element)['values'];
    }
    for (final element in member.annotated) {
      if (_propertyValues.firstAnnotationOf(element) case final a?) {
        final reader = ConstantReader(a);
        final values = reader.read('values').listValue;
        if (values.isNotEmpty) {
          hint['values'] = [
            for (final v in values)
              {'value': v.toStringValue(), 'description': null},
          ];
        }
        if (reader.peek('provider')?.stringValue case final provider?) {
          hint['provider'] = provider;
        }
      }
      if (_range.firstAnnotationOf(element) case final a?) {
        final reader = ConstantReader(a);
        hint['range'] = [
          _number(reader.read('min')),
          _number(reader.read('max')),
        ];
      }
      if (_warnValues.firstAnnotationOf(element) case final a?) {
        final reader = ConstantReader(a);
        ((hint['warn'] ??= <Object?>[]) as List<Object?>).add({
          'values': [
            for (final v in reader.read('values').listValue) _constant(v),
          ],
          'message': reader.read('message').stringValue,
        });
      }
    }
    if (hint.length > 1) {
      hints.putIfAbsent(key, () => hint);
    }
  }

  static Object? _number(ConstantReader reader) =>
      reader.isInt ? reader.intValue : reader.doubleValue;

  // A constant of a `@WarnValues` list as JSON: enum constants in kebab
  // case, like the binder's names.
  static Object? _constant(DartObject value) {
    final type = value.type;
    if (type is InterfaceType && type.element is EnumElement) {
      return kebabCase(value.getField('_name')?.toStringValue() ?? '');
    }
    return value.toBoolValue() ??
        value.toIntValue() ??
        value.toDoubleValue() ??
        value.toStringValue();
  }

  /// The hint with the constants of [enumElement], in the kebab case the
  /// binder accepts.
  static Map<String, Object?> enumHint(String name, Element enumElement) => {
    'name': name,
    'values': [
      for (final constant in (enumElement as EnumElement).constants)
        {
          'value': kebabCase(constant.name!),
          'description': documentation(constant),
        },
    ],
  };

  // The bound members of [element]: the parameters of the one public
  // constructor with parameters (constructor binding), else the writable
  // fields and the setters of the class and its superclasses.
  Future<List<_Member>> _members(ClassElement element) async {
    final constructors = [
      for (final c in element.constructors)
        if (c.isPublic && !c.isFactory) c,
    ];
    if (constructors.length == 1 &&
        constructors.single.formalParameters.isNotEmpty &&
        !_autowired.hasAnnotationOf(constructors.single)) {
      return [
        for (final parameter in constructors.single.formalParameters)
          if (parameter.name case final name?)
            if (!name.startsWith('_'))
              _Member(
                name,
                parameter.type,
                element,
                parameter is FieldFormalParameterElement
                    ? (parameter.field ?? parameter)
                    : parameter,
                parameter.defaultValueCode == null
                    ? null
                    : literalOf(parameter.defaultValueCode!, parameter.type),
                annotated: [
                  parameter,
                  if (parameter is FieldFormalParameterElement)
                    ?parameter.field,
                ],
              ),
      ];
    }
    final result = <_Member>[];
    final seen = <String>{};
    for (final cls in [element, ..._superclasses(element)]) {
      for (final field in cls.fields) {
        final name = field.name;
        if (name == null ||
            name.startsWith('_') ||
            field.isStatic ||
            !field.isOriginDeclaration ||
            (field.isFinal && !field.isLate)) {
          continue;
        }
        if (seen.add(name)) {
          result.add(
            _Member(
              name,
              field.type,
              cls,
              field,
              await _initializer(field),
              annotated: [field],
            ),
          );
        }
      }
      for (final setter in cls.setters) {
        // Only declared setters; the ones a field makes are its fields.
        final name = setter.name?.replaceAll('=', '');
        if (name == null ||
            name.startsWith('_') ||
            setter.isStatic ||
            !setter.isOriginDeclaration) {
          continue;
        }
        if (seen.add(name)) {
          result.add(
            _Member(
              name,
              setter.formalParameters.first.type,
              cls,
              setter,
              null,
              annotated: [setter],
            ),
          );
        }
      }
    }
    return result;
  }

  static Iterable<ClassElement> _superclasses(ClassElement element) sync* {
    var type = element.supertype;
    while (type != null && !type.isDartCoreObject) {
      if (type.element case final ClassElement cls when !cls.library.isInSdk) {
        yield cls;
      }
      type = type.superclass;
    }
  }

  Future<Object?> _initializer(FieldElement field) async {
    final node = await _astNodeFor(field.firstFragment);
    if (node is VariableDeclaration && node.initializer != null) {
      return literalOf(node.initializer!.toSource(), field.type);
    }
    return null;
  }

  // `List<X>` and `Set<X>` give X, any other type itself.
  static DartType _elementType(DartType type) {
    if (type is InterfaceType &&
        (type.isDartCoreList ||
            type.isDartCoreSet ||
            type.isDartCoreIterable)) {
      return type.typeArguments.firstOrNull ?? type;
    }
    return type;
  }

  static bool _isMap(DartType type) =>
      type is InterfaceType && type.isDartCoreMap;

  static DartType _mapValue(DartType type) =>
      (type as InterfaceType).typeArguments.length == 2
      ? type.typeArguments[1]
      : type;

  // A class of the same package that is not an enum is a nested group of
  // properties; SDK and other packages' types (Duration, DataSize) are
  // values.
  static ClassElement? _nestedClass(DartType type, ClassElement owner) {
    if (type is! InterfaceType) {
      return null;
    }
    final element = type.element;
    if (element is! ClassElement ||
        element.library.isInSdk ||
        element.isAbstract ||
        _package(element) != _package(owner)) {
      return null;
    }
    return element;
  }

  static String? _package(Element element) {
    final uri = element.library?.uri;
    return uri != null && uri.pathSegments.isNotEmpty
        ? uri.pathSegments.first
        : null;
  }

  /// The value of the literal [source] of a field or parameter default, or
  /// `null` when it is not a plain literal (`null` is not told from "no
  /// default": the format has a single `default`). Enum constants give the
  /// kebab case name.
  static Object? literalOf(String source, DartType type) {
    var text = source.trim();
    if (text.startsWith('const ')) {
      text = text.substring(6).trim();
    }
    switch (text) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return null;
      case '[]':
        return <Object?>[];
      case '{}':
        return <Object?, Object?>{};
    }
    if (int.tryParse(text) case final number?) {
      return number;
    }
    if (double.tryParse(text) case final number?) {
      return number;
    }
    final string = RegExp(
      r'''^r?(?:'([^'\\$]*)'|"([^"\\$]*)")$''',
    ).firstMatch(text);
    if (string != null) {
      return string[1] ?? string[2];
    }
    if (_quantity(text) case final quantity?) {
      return quantity;
    }
    if (type is InterfaceType && type.element is EnumElement) {
      final enumName = type.element.name;
      final match = RegExp('^$enumName\\.(\\w+)\$').firstMatch(text);
      if (match != null) {
        return kebabCase(match[1]!);
      }
    }
    if (text.startsWith('[') && text.endsWith(']')) {
      final items = <Object?>[];
      final elementType = _elementType(type);
      for (final part in text.substring(1, text.length - 1).split(',')) {
        if (part.trim().isEmpty) {
          continue;
        }
        final value = literalOf(part, elementType);
        if (value == null) {
          return null;
        }
        items.add(value);
      }
      return items;
    }
    return null;
  }
}

// `Duration(seconds: 30)` is `30s` and `DataSize.ofMegabytes(10)` is `10MB`,
// the way a property value is written.
String? _quantity(String text) {
  var source = text;
  if (source.startsWith('const ')) {
    source = source.substring(6).trim();
  }
  final duration = RegExp(
    r'^Duration\(\s*(milliseconds|seconds|minutes|hours|days):\s*(\d+)\s*,?\s*\)$',
  ).firstMatch(source);
  if (duration != null) {
    const units = {
      'milliseconds': 'ms',
      'seconds': 's',
      'minutes': 'm',
      'hours': 'h',
      'days': 'd',
    };
    return '${duration[2]}${units[duration[1]]}';
  }
  final size = RegExp(
    r'^DataSize\.of(Bytes|Kilobytes|Megabytes|Gigabytes|Terabytes)\((\d+)\)$',
  ).firstMatch(source);
  if (size != null) {
    const units = {
      'Bytes': 'B',
      'Kilobytes': 'KB',
      'Megabytes': 'MB',
      'Gigabytes': 'GB',
      'Terabytes': 'TB',
    };
    return '${size[2]}${units[size[1]]}';
  }
  return null;
}

class _Member {
  _Member(
    this.name,
    this.type,
    this.owner,
    this.documented,
    this.defaultValue, {
    required this.annotated,
  });

  /// The elements whose annotations count (a parameter and its field).
  final List<Element> annotated;

  final String name;
  final DartType type;
  final ClassElement owner;

  /// The element whose doc comment, annotations and location describe the
  /// property.
  final Element documented;

  final Object? defaultValue;
}
