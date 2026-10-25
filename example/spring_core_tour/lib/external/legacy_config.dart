// Outside the @ComponentScan root (lib/src/): registered only because
// ShopConfig imports it with @Import.
import 'package:spring_core_dart/spring_core_dart.dart';

class LegacyGreeter {
  LegacyGreeter(this.greeting);
  final String greeting;
}

@Configuration()
@PropertySource(['classpath:legacy.properties'])
class LegacyConfig {
  @Bean()
  LegacyGreeter legacyGreeter(@Value(r'${legacy.greeting}') String greeting) =>
      LegacyGreeter(greeting);
}
