import 'dart:convert';

import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/io/properties_parser.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';

/// Properties read from a `.properties` resource, like Spring's
/// `ResourcePropertySource`. Named after the resource unless [name] is
/// given.
///
/// ```dart
/// final resource = FileSystemResource('config/app.properties');
/// final sync = ResourcePropertySource.fromResource(resource);
/// final async = await ResourcePropertySource.load(resource, name: 'app');
/// environment.propertySources.addLast(async);
/// ```
///
/// Spring (Java):
/// ```java
/// var source = new ResourcePropertySource("app",
///     new FileSystemResource("config/app.properties"));
/// environment.getPropertySources().addLast(source);
/// ```
///
/// Spring always reads synchronously; here use [load] for async-only
/// resources such as Flutter assets.
class ResourcePropertySource extends MapPropertySource {
  ResourcePropertySource._(super.name, super.source);

  /// Reads [resource] synchronously, decoding it with [encoding].
  ///
  /// Throws [UnsupportedError] if the resource does not support
  /// synchronous reading.
  factory ResourcePropertySource.fromResource(
    Resource resource, {
    String? name,
    Encoding encoding = utf8,
  }) => ResourcePropertySource._(
    name ?? resource.description,
    PropertiesLoaderUtils.loadPropertiesSync(resource, encoding: encoding),
  );

  /// Parses already loaded [content] of [resource].
  ///
  /// [resource] only supplies the default name.
  ///
  /// ```dart
  /// ResourcePropertySource.fromContent(resource, 'a=1\nb=2');
  /// ```
  factory ResourcePropertySource.fromContent(
    Resource resource,
    String content, {
    String? name,
  }) => ResourcePropertySource._(
    name ?? resource.description,
    PropertiesParser.parse(content),
  );

  /// Reads [resource] asynchronously, decoding it with [encoding].
  ///
  /// ```dart
  /// final source = await ResourcePropertySource.load(resource);
  /// ```
  static Future<ResourcePropertySource> load(
    Resource resource, {
    String? name,
    Encoding encoding = utf8,
  }) async => ResourcePropertySource.fromContent(
    resource,
    await resource.readAsString(encoding: encoding),
    name: name,
  );
}
