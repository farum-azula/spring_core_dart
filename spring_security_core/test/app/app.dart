// The application the tests start: its beans and proxies are written by the
// generator into app.spring.dart (dart run build_runner build).
import 'package:spring_security_core/spring_security_core.dart';

import 'app.spring.dart';

@ComponentScan()
final BeanModule securityTestBeans = $securityTestBeans;
