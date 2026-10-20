import 'package:spring_core_dart/spring_core_dart.dart';

class LegacyService {
  String get name => 'legacy';
}

/// Outside the scanned directory; registered through `@Import`.
@Configuration()
class LegacyConfig {
  @Bean()
  LegacyService legacyService() => LegacyService();
}
