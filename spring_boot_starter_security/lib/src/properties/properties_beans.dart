import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_security/spring_gen/src/properties/properties_beans.spring.dart';

/// The typed properties of the starter, scanned in this folder.
@ComponentScan()
final BeanModule securityConfigBeans = $securityConfigBeans;
