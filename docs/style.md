# Code style

The style recommended for applications on the spring_core_dart family,
and the one the guides ([server](../example/server_guide/README.md),
[Flutter](../example/flutter_guide/README.md)) are written in.

## Use it

Copy [`style/analysis_options.yaml`](style/analysis_options.yaml) next to
your `pubspec.yaml`:

```sh
curl -o analysis_options.yaml \
  https://raw.githubusercontent.com/farum-azula/spring_core_dart/main/docs/style/analysis_options.yaml
dart pub add dev:lints          # a Dart application
# a Flutter application: change the include to package:flutter_lints/flutter.yaml
```

`dart format .` and `dart analyze` (and every editor) then apply it to the
whole application. What it sets:

- **Formatting:** 80 columns, and **trailing commas preserved**: a list
  that ends with a comma stays one item per line; without one, what fits
  goes on one line. That is how the beans below keep their column.
- **Analysis:** the Dart team's recommended lints, strict casts, inference
  and raw types (the generator and the container read your types: no
  silent `dynamic`), the generated `*.spring.dart` files left out, and a
  few rules the framework's asynchronous lifecycle makes worth it
  (`unawaited_futures`).

## Beans of a widget

`SpringStatelessWidget<(...)>`, `SpringStatefulWidget<(...)>` and
`SpringState<W, (...)>` name their beans in a record.

**One bean** stays in place:

```dart
class BasketBadge extends SpringStatelessWidget<(Basket,)> {
  @override
  Widget build(BuildContext context) {
    final (basket,) = beans;
    return Badge(label: Text('${basket.count}'));
  }
}
```

**Several beans** get a typedef named after the widget, one bean per line
with a trailing comma, and are read the same way:

```dart
/// The beans of [BasketPage].
typedef BasketPageBeans = (
  Basket,
  Session,
  OrderService,
);

class BasketPage extends SpringStatefulWidget<BasketPageBeans> {
  const BasketPage({super.key});

  @override
  State<BasketPage> createState() => _BasketPageState();
}

class _BasketPageState extends SpringState<BasketPage, BasketPageBeans> {
  @override
  Widget build(BuildContext context) {
    final (
      basket,
      session,
      orders,
    ) = beans;
    ...
  }
}
```

The class line stays short, the widget and its `State` share one record,
and the editor's hints (types, the `dart_spring` navigation from a bean
type to its beans) read one per line. The trailing comma is what keeps the
column: with `trailing_commas: preserve` the formatter leaves it, without
the comma it puts the list back on one line.

## Placeholders in annotations

A `${...}` in an annotation is Spring's placeholder, not Dart's
interpolation: write a raw string.

```dart
@Value(r'${shop.name}')                  // not '${shop.name}'
@Scheduled(fixedDelayString: r'${stock.refresh:5m}')
```

The `dart_spring` extension for Zed marks the plain string as an error.

## One dependency, one import

An application lists the starter it uses and imports it alone: each
starter brings and re-exports what it builds on
([dependencies](dependencies.md#5-what-an-application-gets)).

```dart
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
// not also spring_boot_dart, spring_core_dart, spring_web_dart
```
