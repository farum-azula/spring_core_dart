import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/spring_gen/src/config/config.spring.dart';

/// The typed properties of the package, scanned in this folder.
@ComponentScan()
final BeanModule searchProperties = $searchProperties;
