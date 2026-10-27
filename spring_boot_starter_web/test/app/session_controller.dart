import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
@RequestMapping('/session')
class SessionController {
  /// Counts this client's requests in its session.
  @GetMapping('/count')
  int count(ServerHttpRequest request) {
    final session = request.getSession()!;
    final count = ((session.getAttribute('count') as int?) ?? 0) + 1;
    session.setAttribute('count', count);
    return count;
  }

  /// Whether the client has a session, without creating one.
  @GetMapping('/peek')
  bool peek(ServerHttpRequest request) =>
      request.getSession(create: false) != null;

  @PostMapping('/rotate')
  Future<String> rotate(ServerHttpRequest request) => request.changeSessionId();

  @PostMapping('/invalidate')
  void invalidate(ServerHttpRequest request) =>
      request.getSession(create: false)?.invalidate();
}
