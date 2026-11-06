import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_actuator/spring_gen/src/config/config.spring.dart';

/// The typed properties of the starter (`management.endpoints.web.*`),
/// scanned in this folder.
@ComponentScan()
final BeanModule actuatorWebProperties = $actuatorWebProperties;
