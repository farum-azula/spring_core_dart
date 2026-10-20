import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/creation_log.dart';
import 'package:spring_core_dart_example/src/data/store.dart';

/// Created on first use, not at refresh.
@Component()
@Lazy()
class Report {
  /// Several constructors: the `@Autowired` one is used.
  @Autowired()
  Report.fromStore(Store<User> store) : userCount = store.findAll().length {
    creationLog.add('report');
  }

  Report.empty() : userCount = 0;

  final int userCount;
}
