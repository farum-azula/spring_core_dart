import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/greeting/greeter.dart';

/// Not a bean: created by someone else (e.g. Flutter) and injected with
/// `autowireBean`.
@Configurable()
class ScreenState {
  @Autowired()
  late final Greeter greeter;

  @Value(r'${app.title}')
  late final String title;
}
