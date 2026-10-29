import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/api/stock_client.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The stock as the server reports it, live: a subscription to the
/// server-sent events of `GET /api/stock/events` while the Live stock
/// screen is open.
///
/// A `ChangeNotifier` of its own (unlike `Basket`): the events arrive in a
/// stream callback, not in a method call, so it calls
/// `notifyListeners()` there; `@NotifyListeners()` adds the notification
/// after the public methods but `stop` (called while the screen closes,
/// when nobody should rebuild).
@Component()
@NotifyListeners(exclude: ['stop'])
@Log(topic: 'neon.stock')
class LiveStock extends ChangeNotifier {
  LiveStock(this._client);

  final StockClient _client;
  StreamSubscription<StockChanged>? _subscription;
  final _available = <String, int>{};
  final _recent = <StockChanged>[];

  /// Whether the stream is open.
  bool get live => _subscription != null;

  /// The copies in stock per ISBN, as far as the events told. A getter:
  /// a widget reading it in build rebuilds on each event (a method call
  /// would not count as a read, and would notify).
  Map<String, int> get available => Map.unmodifiable(_available);

  /// The last events, the newest first.
  List<StockChanged> get recent => List.unmodifiable(_recent);

  /// Opens the stream (again, after [stop]).
  void start() {
    _subscription ??= _client.events().listen(
      _changed,
      onError: (Object error) => log.warning('stock events: $error'),
      onDone: () => _subscription = null,
    );
  }

  /// Closes the stream.
  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _changed(StockChanged change) {
    _available[change.isbn] = change.available;
    _recent.insert(0, change);
    if (_recent.length > 50) {
      _recent.removeLast();
    }
    log.debug('${change.isbn}: ${change.available}');
    notifyListeners();
  }
}
