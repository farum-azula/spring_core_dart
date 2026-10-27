// @Configuration and @Bean methods (chapter 1): beans that are not
// components of their own, with Spring's @Bean options.
import 'package:neon_books_server/src/catalog/cover_store.dart';
import 'package:neon_books_server/src/shop/clock.dart';
import 'package:neon_books_server/src/shop/receipt.dart';
import 'package:neon_books_server/src/shop/shop_properties.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

@Configuration()
class ShopConfig {
  /// Backs off when another `Clock` bean exists (a test's fixed clock).
  @Bean()
  @ConditionalOnMissingBean(Clock)
  Clock clock() => const SystemClock();

  /// Created on first use (`@Lazy`), known by two names, opened by its
  /// `initMethod`; its `close` method is found as the destroy method.
  @Bean(name: 'coverStore', aliases: ['covers'], initMethod: 'open')
  @Lazy()
  CoverStore coverStore(
    @Value(r'${neon.covers.directory:build/covers}') String directory,
    ResourceLoader resources,
  ) => CoverStore(directory, resources);

  /// A prototype: every lookup (`OrderMailer.newReceipt`) gets a new
  /// builder. `clock()` is an inter-bean call: this class is created as a
  /// generated subclass whose @Bean methods return the container's beans,
  /// so it is the `clock` bean (a test's fixed clock too), not a new one.
  @Bean()
  @Scope(ScopeType.prototype)
  ReceiptBuilder receiptBuilder(ShopProperties shop) =>
      ReceiptBuilder(shop.name, clock().now());
}
