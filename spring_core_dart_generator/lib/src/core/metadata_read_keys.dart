import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spring_core_dart_generator/src/metadata_locations.dart';

/// Reads the property keys that annotations name outside of
/// `@ConfigurationProperties`: the `${key}` / `${key:default}` placeholders
/// in any annotation argument (`@Value('${app.title}')` and so on) and the
/// names of `@ConditionalOnProperty` and `@ConditionalOnBooleanProperty`.
///
/// Each key becomes a property of type `String` (`bool` for the boolean
/// condition), only so the editor knows the key: it has no description.
/// A `@ConfigurationProperties` class that binds the same key wins over
/// these entries.
final class ReadKeyScanner {
  /// The properties found, in scan order, one per key.
  final properties = <Map<String, Object?>>[];

  final _seen = <String>{};

  static const _conditions = {
    'ConditionalOnProperty': 'String',
    'ConditionalOnBooleanProperty': 'bool',
  };

  static final _placeholder = RegExp(r'\$\{([^}:]+)(?::([^}]*))?\}');
  static final _key = RegExp(r'^[A-Za-z][A-Za-z0-9_.\-]*(\[\*?\d*\])?$');

  /// Adds the keys read by the declarations of [library].
  void scanLibrary(LibraryElement library) {
    for (final element in [
      ...library.classes,
      ...library.mixins,
      ...library.enums,
      ...library.extensionTypes,
    ]) {
      _instance(element);
      element.constructors.forEach(_executable);
    }
    library.extensions.forEach(_instance);
    library.topLevelFunctions.forEach(_executable);
    [
      ...library.topLevelVariables,
      ...library.getters,
      ...library.setters,
    ].forEach(_annotations);
  }

  void _instance(InstanceElement element) {
    _annotations(element);
    [
      ...element.fields,
      ...element.getters,
      ...element.setters,
    ].forEach(_annotations);
    element.methods.forEach(_executable);
  }

  void _executable(ExecutableElement element) {
    _annotations(element);
    element.formalParameters.forEach(_annotations);
  }

  void _annotations(Element element) {
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      if (value == null) {
        continue;
      }
      final type = value.type;
      final condition = type is InterfaceType
          ? _conditions[type.element.name]
          : null;
      if (condition != null &&
          type is InterfaceType &&
          type.element.library.uri.toString().startsWith(
            'package:spring_boot_dart/',
          )) {
        _condition(value, condition, element);
      } else {
        _placeholders(value, element, 0);
      }
    }
  }

  // `prefix` + `name` / `names`, joined like ConditionalOnProperty does.
  void _condition(DartObject condition, String type, Element element) {
    final prefix = condition.getField('prefix')?.toStringValue() ?? '';
    final names = <String>[
      ?condition.getField('name')?.toStringValue(),
      for (final name
          in condition.getField('names')?.toListValue() ?? const <DartObject>[])
        ?name.toStringValue(),
    ];
    for (final name in names) {
      _add(
        prefix.isEmpty
            ? name
            : '${prefix.endsWith('.') ? prefix : '$prefix.'}$name',
        type,
        null,
        element,
      );
    }
  }

  // Strings with placeholders anywhere in a constant.
  void _placeholders(DartObject value, Element element, int depth) {
    if (depth > 6 || value.isNull) {
      return;
    }
    final string = value.toStringValue();
    if (string != null) {
      for (final match in _placeholder.allMatches(string)) {
        _add(match[1]!.trim(), 'String', match[2], element);
      }
      return;
    }
    for (final item
        in value.toListValue() ??
            value.toSetValue()?.toList() ??
            const <DartObject>[]) {
      _placeholders(item, element, depth + 1);
    }
    for (final MapEntry(:key, :value)
        in (value.toMapValue() ?? const {}).entries) {
      if (key != null) {
        _placeholders(key, element, depth + 1);
      }
      if (value != null) {
        _placeholders(value, element, depth + 1);
      }
    }
    for (final field
        in value.type is InterfaceType
            ? (value.type! as InterfaceType).element.fields
            : const <FieldElement>[]) {
      if (!field.isStatic && field.name != null) {
        if (value.getField(field.name!) case final inner?) {
          _placeholders(inner, element, depth + 1);
        }
      }
    }
  }

  void _add(String key, String type, String? fallback, Element element) {
    if (!_key.hasMatch(key) || !_seen.add(key)) {
      return;
    }
    final owner = element;
    properties.add({
      'name': key,
      'type': type,
      'description': null,
      'default': fallback,
      'deprecated': null,
      'source': sourceOf(owner),
      'line': lineOf(owner),
      'class': (owner.enclosingElement ?? owner).name,
    });
  }
}
