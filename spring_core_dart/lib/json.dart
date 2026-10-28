/// JSON for Dart objects: `ObjectMapper` turns objects into JSON and back,
/// without hand-written `fromJson` / `toJson` methods.
///
/// Import it to read and write JSON in your own code, to shape the JSON of
/// a model with Jackson-style annotations (`@JsonProperty`, `@JsonIgnore`,
/// `@JsonInclude`, `@JsonFormat`, `@JsonTypeInfo`, ...), or to add a
/// serializer for a type the mapper does not know. It is also exported by
/// `package:spring_core_dart/spring_core_dart.dart`. The web and Feign
/// starters use the same mapper for request and response bodies, so these
/// annotations shape the HTTP JSON too. The mapper reads metadata that
/// `spring_core_dart_generator` writes for classes marked
/// `@Introspected()`; there is no reflection. It also offers a tree model
/// (`JsonNode`), naming strategies and `JsonMapper.builder()`.
///
/// ```dart
/// @Introspected()
/// class Book {
///   const Book({required this.isbn, required this.title});
///   final String isbn;
///   final String title;
/// }
///
/// // In Spring Boot the mapper is a bean: inject ObjectMapper.
/// final json = mapper.writeValueAsString(
///   const Book(isbn: '1', title: 'Dune'),
/// );
/// final book = mapper.readValue<Book>(json);
/// ```
///
/// Spring (Java): Jackson's `com.fasterxml.jackson.databind`, configured by
/// Spring Boot's `JacksonAutoConfiguration`.
library;

export 'package:spring_core_dart/src/beans/type_info.dart';
export 'package:spring_core_dart/src/json/annotations.dart';
export 'package:spring_core_dart/src/json/json_exception.dart';
export 'package:spring_core_dart/src/json/json_mapper.dart';
export 'package:spring_core_dart/src/json/json_node.dart';
export 'package:spring_core_dart/src/json/json_serializer.dart';
export 'package:spring_core_dart/src/json/naming.dart';
export 'package:spring_core_dart/src/json/object_mapper.dart';
