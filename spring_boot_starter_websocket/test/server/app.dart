// The server application of the tests: endpoints written by the generator
// into app.spring.dart (dart run build_runner build).
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

import 'app.spring.dart';

@ComponentScan()
final BeanModule wsServerBeans = $wsServerBeans;
