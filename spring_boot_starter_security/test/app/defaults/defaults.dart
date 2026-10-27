// No security configuration: Spring Boot's defaults (every request needs a
// login; form login and HTTP Basic; the default user).
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import 'defaults.spring.dart';

@ComponentScan()
final BeanModule defaultSecurityBeans = $defaultSecurityBeans;
