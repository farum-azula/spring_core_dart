import 'package:spring_boot_starter_edge/src/cloudflare/cloudflare.dart';

/// Where there is no Worker (the Dart VM): no bindings.
CloudflareBindings createCloudflareBindings() => const _NoBindings();

final class _NoBindings implements CloudflareBindings {
  const _NoBindings();

  @override
  bool has(String binding) => false;

  @override
  bool get loaded => false;

  @override
  KvNamespace kv(String binding) => throw _none(binding);

  @override
  D1Database d1(String binding) => throw _none(binding);

  static StateError _none(String binding) => StateError(
    'No binding "$binding": the application does not run in a Cloudflare '
    'Worker',
  );
}
