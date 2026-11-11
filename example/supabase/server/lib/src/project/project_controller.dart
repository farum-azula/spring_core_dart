import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:supabase_example_server/src/project/avatars.dart';
import 'package:supabase_example_server/src/project/functions.dart';

/// `GET /api/avatar`.
@Introspected()
class AvatarLink {
  const AvatarLink(this.url);

  final String url;
}

/// What the server asks of the project's other services for the caller:
/// an Edge Function and Storage, both through declared interfaces.
@RestController()
@RequestMapping('/api')
class ProjectController {
  ProjectController(this.functions, this.avatars);

  final Functions functions;
  final Avatars avatars;

  /// `GET /api/stats?from=server`: the answer of the Edge Function `stats`,
  /// called as the caller of this request.
  @GetMapping('/stats')
  Future<Map<String, Object?>> stats({
    @RequestParam('from') String from = 'server',
  }) => functions.stats(from);

  /// A signed URL of the caller's avatar; 404 while they have none (the
  /// app uploads it).
  @GetMapping('/avatar')
  Future<AvatarLink> avatar() async => AvatarLink('${await avatars.link()}');
}
