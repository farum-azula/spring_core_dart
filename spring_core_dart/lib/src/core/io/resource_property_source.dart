import 'dart:convert';

import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/io/properties_parser.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';

/// A property source with the properties of one `.properties` file.
///
/// It is what `@PropertySource` adds for each file, named after the
/// resource (its description) unless a name is given. Create one directly
/// to add a properties file to an environment by hand, for example from
/// an `EnvironmentPostProcessor`; config files under `lib/resources/` need
/// no code.
///
/// ```dart
/// // Extra settings next to the program, below every other source.
/// final resource = FileSystemResource('config/app.properties');
/// if (resource.exists()) {
///   environment.propertySources.addLast(
///     ResourcePropertySource.fromResource(resource, name: 'app'),
///   );
/// }
///
/// // A Flutter asset can only be read asynchronously.
/// final asset = await ResourcePropertySource.load(assetResource);
/// ```
///
/// Spring (Java):
/// ```java
/// var source = new ResourcePropertySource("app",
///     new FileSystemResource("config/app.properties"));
/// environment.getPropertySources().addLast(source);
/// ```
///
/// Spring always reads synchronously; here use [load] for resources that
/// can only be read asynchronously, such as Flutter assets.
class ResourcePropertySource extends MapPropertySource {
  ResourcePropertySource._(super.name, super.source);

  /// Reads [resource] now, decoded with [encoding] (UTF-8 unless given),
  /// into a source called [name] or after the resource.
  ///
  /// Throws [UnsupportedError] when the resource cannot be read
  /// synchronously, and the read error when it does not exist.
  factory ResourcePropertySource.fromResource(
    Resource resource, {
    String? name,
    Encoding encoding = utf8,
  }) => ResourcePropertySource._(
    name ?? resource.description,
    PropertiesLoaderUtils.loadPropertiesSync(resource, encoding: encoding),
  );

  /// Parses [content], text already read from [resource], into a source.
  ///
  /// [resource] only supplies the default name, used unless [name] is
  /// given.
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

  /// Reads [resource], waiting for it, decoded with [encoding] (UTF-8
  /// unless given), into a source called [name] or after the resource.
  /// Works for every resource, including Flutter assets and URLs.
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
