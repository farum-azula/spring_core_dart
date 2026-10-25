// Caching (spring_boot_starter_cache): @Cacheable stores results by key,
// @CacheEvict drops them; async methods cache the value of their Future.
// Works through the generated AOP proxy, like Spring.
//
// Spring (Java): @Cacheable(value = "prices", key = "#isbn").
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';

@Service()
class PriceList {
  /// How often a price was really looked up (cache misses).
  int lookups = 0;

  @Cacheable('prices', key: '#isbn')
  double price(String isbn) {
    lookups++;
    return isbn == '1' ? 12.5 : 9.9;
  }

  @CacheEvict('prices', key: '#isbn')
  void changePrice(String isbn) {}

  /// Not stored when the cover is missing (`unless`).
  @Cacheable('covers', unless: '#result == null')
  Future<String?> cover(String isbn) async {
    lookups++;
    return isbn == '1' ? 'cover-1.png' : null;
  }
}
