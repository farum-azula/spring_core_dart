import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_scheduling/spring_gen/src/config/config.spring.dart';

/// The typed properties of the starter, scanned in this folder.
@ComponentScan()
final BeanModule schedulingProperties = $schedulingProperties;
