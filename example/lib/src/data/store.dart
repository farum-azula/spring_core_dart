import 'package:spring_core_dart/spring_core_dart.dart';

class User {
  const User(this.name);

  final String name;
}

/// Generic contract: beans are matched by the full type, e.g. `Store<User>`.
abstract interface class Store<T> {
  List<T> findAll();
}

@Repository()
class UserStore implements Store<User> {
  @override
  List<User> findAll() => const [User('Ada'), User('Linus'), User('Grace')];
}
