// Self-invocation: a call through `this` skips the proxy, so advice (here
// @Timed) does not run. A @Lazy reference to the bean itself goes through
// the proxy, as in Spring (`@Lazy @Autowired MyService self`).
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/aop/aspects.dart';

abstract interface class BasketPricing {
  @Timed()
  double price(String isbn);

  /// Prices every book through the proxy: each `price` call is timed.
  double total(List<String> isbns);

  /// Prices every book through `this`: no advice.
  double totalDirect(List<String> isbns);
}

@Service()
class DefaultBasketPricing implements BasketPricing {
  /// @Lazy: a generated proxy that finds the bean (its AOP proxy) on first
  /// use, so injecting the bean into itself is not a cycle.
  DefaultBasketPricing(@Lazy() this._self);

  final BasketPricing _self;

  @override
  double price(String isbn) => 10;

  @override
  double total(List<String> isbns) =>
      isbns.fold(0, (sum, isbn) => sum + _self.price(isbn));

  @override
  double totalDirect(List<String> isbns) =>
      isbns.fold(0, (sum, isbn) => sum + price(isbn));
}
