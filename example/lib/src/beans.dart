import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/beans.beans.dart';

/// Every bean under `lib/src/`.
@ComponentScan()
final BeanModule exampleBeans = $exampleBeans;
