import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

/// The body of `send-invite`.
@Introspected()
class Invite {
  const Invite({required this.email});

  final String email;
}

/// Its answer: `<the caller's id>|<the address>`.
@Introspected()
class InviteResult {
  const InviteResult({required this.id});

  final String id;
}

/// The Edge Functions of the project, as a Feign client of
/// `<spring.supabase.url>/functions/v1`: each call carries the anon key
/// and the user's token, so the function knows who asks.
@EdgeFunctions()
abstract interface class Functions {
  /// `POST /functions/v1/api/send-invite`.
  @EdgeFunction('api/send-invite')
  Future<InviteResult> sendInvite(@RequestBody() Invite invite);
}
