### The basket, a bean

`Basket` is a **bean**: one per app, shared by every screen
([beans](https://github.com/farum-azula/spring_core_dart)).

```dart
@Service()
final class Basket {
  final titles = <String>['Spring in Action'];
  int get count => titles.length; // 1
}
```

```yaml
spring:
  flutter:
    theme:
      active: neon   # neon-night, sepia, high-contrast
      motion: { durations: { fast: 120ms } }
```
