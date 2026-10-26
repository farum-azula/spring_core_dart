# spring_boot_starter_flutter: example

**What it does:** the counter app of `flutter create` on Spring Boot: the
count lives in a bean, widgets get it from the application context, and the
texts and settings come from properties files.

`example.dart` is the whole app: a `@ChangeNotifierComponent` counter,
Spring widgets and `@SpringBootApplication` on `main`; the generator
writes `example.spring.dart`. The steps below show the same in a project. A
complete app with tests and golden screenshots:
[`example/flutter_counter`](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_counter).

## Setup

```yaml
dependencies:
  flutter:
    sdk: flutter
  spring_boot_starter_flutter: ^0.3.1

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.3.1
```

## 1. Start the application

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'main.spring.dart'; // generated

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const CounterPage(), // the app widget comes from spring.flutter.app.*
  ),
);
```

```properties
# lib/resources/application.properties
spring.flutter.app.type=material   # Scaffold and AppBar need a MaterialApp
spring.flutter.app.title=Counter
```

```bash
dart run build_runner build   # or `watch` while developing
```

## 2. State in a bean

```dart
@ChangeNotifierComponent() // the proxy notifies the listeners after every method
@BuildContextAccess()      // generates `context.counter`
class Counter {
  int value = 0;
  void increment() => value++;
}
```

## 3. Beans in widgets

```dart
class CounterValue extends SpringStatelessWidget<(Counter,)> {
  const CounterValue({super.key});

  @override
  Widget build(BuildContext context) {
    final (counter,) = beans; // rebuilt when the counter notifies
    return Text('${counter.value}');
  }
}

FloatingActionButton(
  onPressed: context.counter.increment, // the generated getter
  child: const Icon(Icons.add),
);
```

## 4. Settings from properties

```properties
# lib/resources/application.properties
counter.step=1
# lib/resources/application-mobile.properties (Android and iOS)
counter.title=Counter (mobile)
```

```dart
@ConfigurationProperties('counter')
@Validated()
class CounterProperties {
  String title = 'Counter';
  @Min(1)
  int step = 1;
}
```

`flutter run --dart-define=COUNTER_STEP=5` overrides a property at build
time; a value that fails validation stops the start with a report.

## 5. Texts

```properties
# lib/resources/messages.properties, messages_ja.properties, ...
counter.pushed=You have pushed the button this many times:
```

```dart
Text(context.message('counter.pushed'));
```

## 6. Tests

```dart
final app = springBootTest(springApplication, properties: {'counter.step': 2});

testWidgets('a tap adds counter.step', (tester) async {
  await tester.pumpWidget(
    SpringScope(applicationContext: app.context, child: const CounterApp()),
  );
  await tester.tap(find.byIcon(Icons.add));
  await tester.pump();
  expect(find.text('2'), findsOneWidget);
});
```
