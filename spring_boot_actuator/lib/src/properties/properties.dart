import 'package:spring_boot_actuator/spring_gen/src/properties/properties.spring.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The typed properties of the actuator (`management.*`, `spring.info.*`),
/// scanned in this folder. The actuator starter imports the module.
@ComponentScan()
final BeanModule actuatorProperties = $actuatorProperties;
