import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// Where the server is: `api.*` of `lib/resources/application*.properties`,
/// per platform profile (the Android emulator reaches the computer at
/// `10.0.2.2`). Validated at startup: a bad value stops the start with a
/// report instead of failing at the first request.
///
/// ```sh
/// flutter run --dart-define=API_HOST=192.168.1.20:8080   # a phone on the LAN
/// ```
@ConfigurationProperties('api')
@Validated()
class ApiProperties {
  /// `localhost:8080`: host and port of the server guide.
  @NotBlank()
  String host = 'localhost:8080';

  /// `http://${api.host}`: the Feign clients' URL.
  @Matches(r'https?://.+')
  String baseUrl = 'http://localhost:8080';

  /// `ws://${api.host}`: the support chat's URL.
  @Matches(r'wss?://.+')
  String wsUrl = 'ws://localhost:8080';
}
