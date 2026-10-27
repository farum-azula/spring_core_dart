/// JSON: `ObjectMapper` converts objects to JSON and back on generated
/// metadata (no reflection), with Jackson-style annotations
/// (`@JsonProperty`, `@JsonAlias`, `@JsonIgnore`, `@JsonInclude`,
/// `@JsonPropertyOrder`, `@JsonCreator`, `@JsonValue`, `@JsonFormat`,
/// `@JsonNaming`, `@JsonView`, `@JsonUnwrapped`, `@JsonAnyGetter` /
/// `@JsonAnySetter`, `@JsonTypeInfo` / `@JsonSubTypes`), naming
/// strategies, a tree model (`JsonNode`), `JsonMapper.builder()` and custom
/// (de)serializers.
///
/// ```dart
/// @Introspected()
/// class Book {
///   const Book({required this.isbn, required this.title});
///   final String isbn;
///   final String title;
/// }
///
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
