# Example

`pubspec.yaml`:

```yaml
dependencies:
  spring_core_dart: ^0.1.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0
```

`lib/src/beans.dart` — the scan root (everything under `lib/src/` is
scanned):

```dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:my_app/src/beans.beans.dart';

@ComponentScan()
final BeanModule appBeans = $appBeans;
```

`lib/src/greeting.dart`:

```dart
import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class Greeter {
  String greet(String name);
}

@Service()
class EnglishGreeter implements Greeter {
  EnglishGreeter(@Value(r'${greeting.suffix:!}') this.suffix);

  final String suffix;

  @override
  String greet(String name) => 'Hello, $name$suffix';
}
```

Run the generator:

```bash
dart run build_runner build
```

It writes `lib/src/beans.beans.dart` (simplified):

```dart
final BeanModule $appBeans = BeanModule('appBeans', [
  BeanDefinition<EnglishGreeter>(
    name: 'englishGreeter',
    types: const [EnglishGreeter, Greeter],
    dependencies: const [Dependency.value(r'${greeting.suffix:!}')],
    create: (r) => EnglishGreeter(r.value<String>(r'${greeting.suffix:!}')),
    aopProxy: AopProxyFactory(...),
  ),
]);
```

Use it:

```dart
void main() {
  final context = ApplicationContext.run([appBeans]);
  print(context.getBean<Greeter>().greet('Ada')); // Hello, Ada!
  context.close();
}
```

A complete example with every feature lives in the repository:
<https://github.com/farum-azula/spring_core_dart/tree/main/example>.
