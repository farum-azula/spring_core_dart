import 'dart:async';

import 'package:spring_security_core/spring_security_core.dart';

const _quick = Duration(milliseconds: 1);

/// Methods that are both checked and retried: method security comes
/// first, so a denied call runs nothing and is never retried.
@Service()
class RetriedOrders {
  final calls = <String>[];

  /// Admins only; fails once, then succeeds.
  @PreAuthorize("hasRole('ADMIN')")
  @Retryable(delay: _quick)
  Future<String> cancel(String id) async {
    calls.add('cancel $id');
    if (calls.length < 2) {
      throw TimeoutException('slow');
    }
    return 'cancelled $id';
  }

  /// The result is checked after the call: a refused result is not
  /// retried either.
  @PostAuthorize('returnObject == authentication.name')
  @Retryable(delay: _quick)
  Future<String> owner(String id) async {
    calls.add('owner $id');
    return 'bob';
  }
}
