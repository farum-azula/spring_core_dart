import 'package:flutter/material.dart';
import 'package:neon_books_app/src/basket/basket.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The basket's icon with the number of books: it reads `basket.count` in
/// build, so a book added anywhere rebuilds it (and nothing around it),
/// like the counter's number in `flutter create`'s app.
class BasketBadge extends SpringStatelessWidget<(Basket,)> {
  const BasketBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final (basket,) = beans;
    final count = basket.count;
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: const Icon(Icons.shopping_basket_outlined),
    );
  }
}
