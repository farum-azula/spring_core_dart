# Code style

The code style recommended for applications built on the spring_core_dart
family, and the one the guides ([server](../example/server_guide/README.md),
[Flutter](../example/flutter_guide/README.md)) are written in. It is one
file to copy, so a new project starts with formatting and analysis that
suit the framework: the generator and the container read your types, and
much of the framework is asynchronous.

## Use it

Copy [`style/analysis_options.yaml`](style/analysis_options.yaml) next to
your `pubspec.yaml`:

```sh
curl -o analysis_options.yaml \
  https://raw.githubusercontent.com/farum-azula/spring_core_dart/main/docs/style/analysis_options.yaml
dart pub add dev:lints          # a Dart application
# a Flutter application: change the include to package:flutter_lints/flutter.yaml
```

From then on `dart format .`, `dart analyze` and every editor apply it to
the whole application. What it sets:

- **Formatting:** 80 columns, and **trailing commas preserved**. A list
  that ends with a comma stays one item per line; a list without one is
  put on one line when it fits. That is how the beans of a widget keep
  their column ([below](#beans-of-a-widget)).
- **Analysis:** the Dart team's recommended lints, plus strict casts,
  strict inference and strict raw types. The generator and the container
  read your types, so a silent `dynamic` would hide a mistake until run
  time. The generated `*.spring.dart` files are left out of the analysis.
- **A few extra lint rules:** `unawaited_futures` (the framework's
  lifecycle, events and requests are asynchronous, so a future that is
  started must be awaited or marked `unawaited(...)`),
  `prefer_final_locals`, `prefer_single_quotes` and `directives_ordering`.

## Beans of a widget

In a Flutter app, `SpringStatelessWidget<(...)>`,
`SpringStatefulWidget<(...)>` and `SpringState<W, (...)>` receive their
beans as a record: the type argument lists the beans the widget needs,
and the `beans` getter returns them. How to write that record depends on
how many beans there are.

**One bean** stays on the class line:

```dart
// The badge only needs the basket.
class BasketBadge extends SpringStatelessWidget<(Basket,)> {
  const BasketBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final (basket,) = beans;
    return Badge(label: Text('${basket.count}'));
  }
}
```

**Several beans** get a typedef named after the widget, one bean per line
with a trailing comma, and are read back the same way:

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

Why: the class line stays short, the widget and its `State` share one
record type, and the editor's hints (the types, and the `dart_spring`
navigation from a bean type to its beans) read one per line. The trailing
comma is what keeps the column: with `trailing_commas: preserve` the
formatter leaves the list as it is, and without the comma it would put
the list back on one line.

## Placeholders in annotations

A `${...}` in an annotation is a Spring placeholder, filled from the
configuration when the application starts. In a normal Dart string `$`
starts Dart's own interpolation, so the code would not compile or would
insert a Dart variable. Write a raw string (`r'...'`):

```dart
@Value(r'${shop.name}')                                // not '${shop.name}'
@Scheduled(fixedDelayString: r'${stock.refresh:5m}')
```

The `dart_spring` extension for Zed marks the plain string as an error.

## One dependency, one import

An application lists the one starter it builds on and imports only that
starter: each starter brings and re-exports the packages it builds on
([dependencies](dependencies.md#5-what-an-application-gets)). Listing or
importing those packages as well adds nothing, and their versions could
drift from the starter's.

```dart
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
// not also spring_boot_dart, spring_core_dart or spring_web_dart
```
