// The controllers every test application shares (scanned from here).
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import '../../spring_gen/app/web/web.spring.dart';

@ComponentScan()
final BeanModule securityWebBeans = $securityWebBeans;
