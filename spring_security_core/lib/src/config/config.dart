import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/spring_gen/src/config/config.spring.dart';

/// The typed properties of the package, scanned in this folder.
@ComponentScan()
final BeanModule securityCoreConfigBeans = $securityCoreConfigBeans;
