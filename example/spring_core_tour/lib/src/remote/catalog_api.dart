// Feign clients (spring_boot_starter_feign): an interface with mapping
// annotations becomes a bean; the generator writes its implementation and
// the ObjectMapper reads and writes the JSON (BookDto is @Introspected).
//
// Spring (Java): Spring Cloud OpenFeign's @FeignClient.
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart'
    show Cacheable;
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_core_dart_example/src/api/book_dto.dart';

@FeignClient(
  'catalog-api',
  url: r'${neon.catalog-api.url:http://localhost:8080}',
)
abstract interface class CatalogApi {
  /// Cached: AOP works on clients like on any bean.
  @GetMapping('/books/{isbn}')
  @Cacheable('remote-books', key: '#isbn')
  Future<BookDto> find(@PathVariable() String isbn);

  @GetMapping('/books')
  Future<List<BookDto>> search(@RequestParam('q') String query);

  @PostMapping('/books')
  Future<ResponseEntity<BookDto>> create(@RequestBody() BookDto book);
}

/// A client with a fallback: any failed call is answered by
/// [OfflineMotd] instead.
@FeignClient(
  'motd-api',
  url: r'${neon.catalog-api.url:http://localhost:8080}',
  fallback: OfflineMotd,
)
abstract interface class MotdApi {
  @GetMapping('/motd')
  Future<String> messageOfTheDay();
}

/// Answers when the motd service fails.
@Component()
class OfflineMotd implements MotdApi {
  @override
  Future<String> messageOfTheDay() async => 'motd offline, try later';
}
