// JSON (ObjectMapper): one @Introspected() on the model; AuthorDto (same
// package) is introspected automatically. Immutable classes are created
// through their constructor, default values included.
//
// Spring (Java): Jackson with records / @JsonProperty, configured by
// spring.jackson.* properties.
import 'package:spring_core_dart/spring_core_dart.dart';

enum BookFormat { paperback, ebook }

enum Availability {
  inStock('in_stock'),
  soldOut('sold_out');

  Availability(this.json);

  /// The JSON form: "in_stock" instead of "inStock".
  @JsonValue()
  final String json;
}

class AuthorDto {
  const AuthorDto(this.name, {this.born});
  final String name;
  final int? born;
}

@Introspected()
@JsonIgnoreProperties(ignoreUnknown: true)
class BookDto {
  const BookDto({
    required this.isbn,
    required this.title,
    required this.author,
    this.formats = const [BookFormat.paperback],
    this.availability = Availability.inStock,
    this.publishedAt,
    this.price,
  });

  final String isbn;
  final String title;
  final AuthorDto author;
  final List<BookFormat> formats;
  final Availability availability;
  @JsonProperty('published_at')
  final DateTime? publishedAt;
  final double? price;
}
