import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_edge/src/fetch/fetch_runtime_stub.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_edge/src/fetch/fetch_runtime_js.dart'
    as platform;

/// Runs [application] as a function behind the fetch API: the `main` of
/// an application for Supabase Edge Functions, Cloudflare Workers or AWS
/// Lambda.
///
/// ```dart
/// import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
///
/// import 'spring_gen/main.spring.dart';
///
/// @SpringBootApplication()
/// void main() => runFetchApplication(() => springApplication);
/// ```
///
/// Compiled to JavaScript (`dart run spring_boot_starter_edge:build`), it
/// opens no socket: it gives the platform's entry file a handler, starts
/// the context once per instance, with the platform's environment
/// variables as the environment, and answers every request through the
/// dispatcher. Controllers, filters, security and Feign clients are those
/// of a server.
///
/// Run on the Dart VM (`dart run bin/main.dart`), the same `main` starts
/// the application as an ordinary server on `server.port`: that is how a
/// function is developed and debugged.
///
/// [properties] are above every other property source.
///
/// Spring (Java): `SpringBootLambdaContainerHandler` of the serverless
/// Java container, and the adapters of Spring Cloud Function.
void runFetchApplication(
  SpringApplication Function() application, {
  Map<String, Object?> properties = const {},
}) => platform.startFetchApplication(application, properties);
