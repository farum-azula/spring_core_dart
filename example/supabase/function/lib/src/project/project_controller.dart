import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

/// The body of `POST /send-invite`.
@Introspected()
class Invite {
  const Invite({required this.email});

  @NotBlank()
  final String email;
}

/// Its answer: `<the caller's id>|<the address>`.
@Introspected()
class InviteResult {
  const InviteResult({required this.id});

  final String id;
}

/// What the app and the server of the example call
/// (`@EdgeFunction('api/send-invite')`, `@EdgeFunction('api/stats')`).
/// The app also runs in a browser, on another origin than the project:
/// `@CrossOrigin` answers its pre-flight.
@RestController()
@CrossOrigin(
  origins: ['*'],
  allowedHeaders: [
    'authorization',
    'apikey',
    'content-type',
    'accept',
    'x-client-info',
    'x-region',
  ],
)
class ProjectController {
  /// Who called, as the resource server read it from the checked token,
  /// and what the gateway passed on. `from=fail` answers 422.
  @GetMapping('/stats')
  Map<String, Object?> stats(
    JwtAuthenticationToken caller,
    ServerHttpRequest request, {
    @RequestParam('from') String? from,
  }) {
    if (from == 'fail') {
      throw ResponseStatusException(
        HttpStatus.unprocessableContent,
        'no stats from fail',
      );
    }
    return {
      'from': from,
      'method': request.method.value,
      'user': caller.name,
      'role': caller.jwt.claims['role'],
      // The signature, the issuer and the expiry were checked.
      'verified': caller.name,
      'apikey': request.headers.contains('apikey'),
    };
  }

  @PostMapping('/send-invite')
  InviteResult sendInvite(
    Authentication caller,
    @RequestBody() @Valid() Invite invite,
  ) => InviteResult(id: '${caller.name}|${invite.email}');
}
