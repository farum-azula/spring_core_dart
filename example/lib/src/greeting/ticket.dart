import 'package:spring_core_dart/spring_core_dart.dart';

/// A new instance for every injection.
@Component()
@Scope(ScopeType.prototype)
class Ticket {
  static int _next = 0;

  final int number = ++_next;
}
