// The application the tests start: its beans are written by the generator
// into app.spring.dart (dart run build_runner build).
import 'package:spring_boot_starter_actuator/spring_boot_starter_actuator.dart';

import '../spring_gen/app/app.spring.dart';

@ComponentScan()
final BeanModule actuatorTestBeans = $actuatorTestBeans;
