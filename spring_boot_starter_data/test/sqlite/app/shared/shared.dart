// A second module of the SQLite test application, with its own
// @ComponentScan: the generator writes the SQLite glue into it as well as
// into the application's module, and the context must still hold one driver.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import 'shared.spring.dart';

/// A bean of the shared module.
@Component()
class SharedBean {}

/// The module the application imports.
@ComponentScan()
final BeanModule sharedBeans = $sharedBeans;
