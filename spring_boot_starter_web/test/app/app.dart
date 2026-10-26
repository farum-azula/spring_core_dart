// The application the tests start: its beans are written by the generator
// into app.spring.dart (dart run build_runner build).
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'app.spring.dart';

@ComponentScan()
final BeanModule webTestBeans = $webTestBeans;
