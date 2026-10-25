// The Flutter counter app (`flutter create`) on spring_boot_starter_flutter: the count
// lives in a bean, the texts come from messages files, the title and the
// step from application properties, and each platform gets its profile.
// The app widget (a MaterialApp here) is built from spring.flutter.app.*
// in application.properties and the theme bean of lib/src/theme/.
//
//   flutter run                        # any device
//   flutter run --dart-define=COUNTER_STEP=5
import 'package:flutter/widgets.dart';
import 'package:flutter_counter/main.spring.dart';
import 'package:flutter_counter/src/counter/counter_page.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const CounterPage(),
  ),
);
