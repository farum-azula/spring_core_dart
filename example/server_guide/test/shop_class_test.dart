// Chapter 12: a test written the way Spring writes tests — annotations on
// a class, beans in fields, one method per test. The generator turns it
// into spring/shop_class.test.spring.dart (runSpringTests).
@TestOn('vm')
library;

import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/orders/order_service.dart';
import 'package:neon_books_server/src/shop/clock.dart';
import 'package:neon_books_server/src/shop/shop_properties.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

import 'spring/shop_class.test.spring.dart';

class FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 10, 27, 12);
}

@SpringBootTest(properties: {'neon.shop.delivery-time': '3d'})
@ActiveProfiles(['dev', 'test'])
@TestEnvironment({'NEON_SHOP_NAME': 'Night Books'})
@AutoConfigureMockMvc()
class ShopTest {
  /// Replaces the `clock` bean (@TestBean, like Spring's).
  @TestBean(type: Clock, name: 'clock')
  final clock = FixedClock();

  @Autowired()
  late MockMvc mvc;

  @Autowired()
  late Catalog catalog;

  @Autowired()
  late OrderService orders;

  @Autowired()
  late ShopProperties shop;

  @Value(r'${neon.shop.name}')
  late String shopName;

  @CapturedOutput()
  late CapturedLogs logs;

  @Test('properties from the annotation and the environment')
  void configuration() {
    expect(shopName, 'Night Books'); // @TestEnvironment
    expect(shop.deliveryTime, const Duration(days: 3)); // @SpringBootTest
  }

  @Test()
  @DisplayName('orders are placed at the time of the fixed clock')
  Future<void> fixedClock() async {
    final order = await withMockUser(
      () => orders.place('ada', {'9780441013593': 1}),
      username: 'ada',
    );
    expect(order.placedAt, DateTime.utc(2026, 10, 27, 12));
  }

  @Test('MockMvc, injected')
  Future<void> mockMvc() => mvc
      .perform(
        MockRequestBuilder(HttpMethod.post, '/api/orders')
          ..with_(user('ada'))
          ..with_(csrf()),
      )
      .andExpect(status: 409); // the basket of this new session is empty

  @Test()
  @Tag('logs')
  void logsOfTheTest() {
    catalog.search('poetry', 0);
    expect(logs.ofLogger('neon.timing'), hasLength(1));
  }

  @Nested('the catalog')
  final theCatalog = TheCatalog();
}

class TheCatalog {
  @Autowired()
  late Catalog catalog;

  @Test()
  void hasTheSampleBooks() => expect(catalog.search('', 0).total, 8);
}

void main() => runSpringTests();
