import 'package:neon_books_server/src/admin/log_service.dart';
import 'package:neon_books_server/src/admin/order_feed.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Admins only: the request rules (`/api/admin/**` needs ADMIN) and the
/// services' annotations check it twice.
@RestController()
@RequestMapping('/api/admin')
class AdminController {
  AdminController(this.logs, this.orders);

  final LogService logs;
  final AdminOrderFeed orders;

  /// `GET /api/admin/logs?level=warn&logger=neon&limit=50`.
  @GetMapping('/logs')
  List<LogLine> recentLogs({
    @RequestParam.of(name: 'level', defaultValue: '') String level = '',
    @RequestParam.of(name: 'logger', defaultValue: '') String logger = '',
    @RequestParam.of(name: 'q', defaultValue: '') String text = '',
    @RequestParam.of(name: 'limit', defaultValue: '100') int limit = 100,
  }) => logs.recent(
    minLevel: level.isEmpty ? null : _level(level),
    logger: logger.isEmpty ? null : logger,
    text: text.isEmpty ? null : text,
    limit: limit,
  );

  /// Orders placed and shipped, live.
  @GetMapping('/orders/live')
  SseEmitter liveOrders() => orders.subscribe();

  static SpringLogLevel _level(String name) => switch (name.toLowerCase()) {
    'trace' => SpringLogLevel.trace,
    'debug' => SpringLogLevel.debug,
    'info' => SpringLogLevel.info,
    'warn' || 'warning' => SpringLogLevel.warning,
    'error' => SpringLogLevel.error,
    _ => throw ResponseStatusException(
      HttpStatus.badRequest,
      'Unknown level $name',
    ),
  };
}
