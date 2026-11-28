import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

/// The Edge Functions of the project, as an HTTP service interface of
/// `<spring.supabase.url>/functions/v1` (imported by `appBeans`, in the
/// group `supabase-functions`). A call made while a request is handled
/// carries the caller's token: the function sees the same user as this
/// server does.
@EdgeFunctions()
abstract interface class Functions {
  /// `GET /functions/v1/api/stats?from=...`: the function written in Dart
  /// (../../../function) answers who called it (`user`, `role`, and
  /// `verified`: the id its resource server read from the checked token).
  @EdgeFunction('api/stats', method: HttpMethod.get)
  Future<Map<String, Object?>> stats(@RequestParam('from') String from);
}
