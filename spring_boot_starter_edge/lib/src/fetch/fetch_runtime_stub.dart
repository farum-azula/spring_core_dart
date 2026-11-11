import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Where there is no fetch platform (the Dart VM): the application runs
/// as an ordinary server.
void startFetchApplication(
  SpringApplication Function() application,
  Map<String, Object?> properties,
) {
  application().runAsync(const [], properties: properties).ignore();
}
