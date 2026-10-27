// Collection injection (chapter 1): every PriceRule bean, as a List
// sorted by @Order and as a Map by bean name; a @Primary composite that
// is itself a PriceRule wins where one rule is injected.
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class PriceRule {
  /// The discount in percent for [quantity] copies of [book].
  int discountPercent(Book book, int quantity);
}

/// 10 % off from the third copy of a title on.
@Component()
@Order(1)
class BulkDiscount implements PriceRule {
  @override
  int discountPercent(Book book, int quantity) => quantity >= 3 ? 10 : 0;
}

/// 20 % off poetry.
@Component()
@Order(2)
class PoetryDiscount implements PriceRule {
  @override
  int discountPercent(Book book, int quantity) =>
      book.tags.contains('poetry') ? 20 : 0;
}

/// The best of the other rules. Being a PriceRule itself, it receives the
/// *other* rules (a bean is never injected into itself) and, `@Primary`,
/// is the one injected where a single PriceRule is asked for.
@Component()
@Primary()
@Log()
class BestDiscount implements PriceRule {
  BestDiscount(this.rules, this.rulesByName);

  /// In `@Order`: the first of equal discounts wins.
  final List<PriceRule> rules;

  /// By bean name, in registration order.
  final Map<String, PriceRule> rulesByName;

  @PostConstruct()
  void report() => log.debug('price rules: ${rulesByName.keys.join(', ')}');

  @override
  int discountPercent(Book book, int quantity) => rules
      .map((rule) => rule.discountPercent(book, quantity))
      .fold(0, (best, percent) => percent > best ? percent : best);
}
