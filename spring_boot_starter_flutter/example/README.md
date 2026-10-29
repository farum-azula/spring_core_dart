# spring_boot_starter_flutter: example

The counter app of `flutter create`, on Spring Boot. The count lives in
a bean (an object the framework creates and shares) instead of a
`State`, and the widgets get it from the application context.

[`example.dart`](example.dart) is the whole app:

- `Counter` is a `@ChangeNotifierComponent`: a plain class whose bean
  notifies its listeners after every method, with no `extends
  ChangeNotifier` and no `notifyListeners()`.
- `main` carries `@SpringBootApplication()` and runs
  `SpringApplicationWidget`, which starts the application and gives its
  beans to the widgets below. Here it gets the app's own `MaterialApp`
  through `child:`.
- `CounterPage` and `CounterText` are `SpringStatelessWidget<(Counter,)>`:
  they list the bean they need in their type and read it as `beans`.
  `CounterText` reads `counter.value`, so it rebuilds after each tap.
  `CounterPage` only calls `counter.increment`, so it does not.

The generator writes `example.spring.dart` from it
(`dart run build_runner build`).

## Run it

`example.dart` lives inside the package, which has no platform folders.
To run it, make an app around it:

```sh
flutter create counter && cd counter
flutter pub add spring_boot_starter_flutter
flutter pub add dev:build_runner dev:spring_core_dart_generator
# copy example.dart to lib/main.dart, and change its import
# 'example.spring.dart' to 'main.spring.dart'
dart run build_runner build
flutter run
```

## The same in a project, step by step

The steps below build the counter again, with the parts a real app
uses: the app widget and texts from configuration files, settings per
platform, and a test. A complete app with every feature, tests and
golden screenshots: the
[Flutter guide](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide).

### Setup

```yaml
dependencies:
  flutter:
    sdk: flutter
  spring_boot_starter_flutter: ^0.4.3

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3
```

### 1. Start the application

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'main.spring.dart'; // generated

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    // No MaterialApp in the code: the app widget is built from
    // spring.flutter.app.* in the configuration files.
    home: const CounterPage(),
  ),
);
```

```properties
# lib/resources/application.properties
# Scaffold and AppBar need a MaterialApp; the default is a WidgetsApp.
spring.flutter.app.type=material
spring.flutter.app.title=${counter.title}
```

Run the generator; it writes `lib/main.spring.dart` and embeds the files
of `lib/resources/`:

```bash
dart run build_runner build   # or `watch` while developing
```

### 2. Settings from properties

The counter's settings are a class bound to `counter.*`. `@Validated()`
checks them when the app starts.

```dart
@ConfigurationProperties('counter')
@Validated()
class CounterProperties {
  String title = 'Counter';

  @Min(1)
  int step = 1;
}
```

```properties
# lib/resources/application.properties
counter.step=1
```

```properties
# lib/resources/application-mobile.properties: Android and iOS only
counter.title=Counter (mobile)
```

The platform is an active profile (`mobile` and `android` on Android,
`desktop` and `macos` on a Mac, ...), so `application-mobile.properties`
is read on phones only. A build can override a value:
`flutter run --dart-define=COUNTER_STEP=5`. A value that fails
validation (`COUNTER_STEP=0`) stops the start with a report on screen.

### 3. State in a bean

```dart
@ChangeNotifierComponent() // the bean notifies its listeners after every method
@BuildContextAccess()      // generates the getter `context.counter`
class Counter {
  Counter(this._properties); // the settings bean is injected

  final CounterProperties _properties;
  int value = 0;

  void increment() => value += _properties.step;
}
```

### 4. Beans in widgets

```dart
class CounterPage extends SpringStatelessWidget<(Counter,)> {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final (counter,) = beans;
    return Scaffold(
      appBar: AppBar(title: Text(context.message('counter.heading'))),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.message('counter.pushed')),
            const CounterValue(),
          ],
        ),
      ),
      // Only calls a method: a tap does not rebuild the page.
      floatingActionButton: FloatingActionButton(
        onPressed: counter.increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CounterValue extends SpringStatelessWidget<(Counter,)> {
  const CounterValue({super.key});

  @override
  Widget build(BuildContext context) {
    final (counter,) = beans; // reads counter.value: rebuilt after each tap
    return Text('${counter.value}');
  }
}
```

A plain widget elsewhere can reach the bean with the generated getter,
for example to reset it from a menu: `context.counter`. A getter does not
rebuild the widget; the Spring widgets above do.

### 5. Texts

The texts live in message files, one per language. The app supports the
languages it has files for.

```properties
# lib/resources/messages.properties
counter.heading=Counter
counter.pushed=You have pushed the button this many times:
```

```properties
# lib/resources/messages_ja.properties
counter.heading=カウンター
counter.pushed=ボタンを押した回数：
```

`context.message('counter.pushed')` gives the text in the app's current
language.

### 6. Tests

`springBootTest` (from `spring_boot_starter_test`: `flutter pub add
dev:spring_boot_starter_test`) starts the application for the test
file, with test properties.
`SpringScope` gives its context to the widget, and `SpringApp` builds
the app widget of the properties around it.

```dart
// test/counter_test.dart
import 'package:counter/main.dart';
import 'package:counter/main.spring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

void main() {
  final app = springBootTest(
    springApplication,
    properties: {'counter.step': 2},
  );

  setUp(app.markDirty); // a fresh Counter for every test

  testWidgets('a tap adds counter.step', (tester) async {
    await tester.pumpWidget(
      SpringScope(
        applicationContext: app.context,
        child: const SpringApp(home: CounterPage()),
      ),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
  });
}
```

```bash
flutter test
```
