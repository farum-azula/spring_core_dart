// The Flutter counter app (`flutter create`) on spring_boot_starter_flutter: the count
// lives in a bean, the texts come from messages files, the title and the
// step from application properties, and each platform gets its profile.
//
//   flutter run                        # any device
//   flutter run --dart-define=COUNTER_STEP=5
import 'package:flutter/widgets.dart';
import 'package:flutter_counter/main.spring.dart';
import 'package:flutter_counter/src/counter_app.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    child: const CounterApp(),
  ),
);
