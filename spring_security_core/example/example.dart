// Method security in a Spring Boot application: annotate bean methods with
// @PreAuthorize and friends, the generator writes the proxies the checks run
// on (example.spring.dart, from `dart run build_runner build`). Users and
// their hashed passwords come from a UserDetailsService bean; the
// AuthenticationManager is built from it.
//
//   dart run example/example.dart

// The example shows its results on the console.
// ignore_for_file: avoid_print

import 'package:spring_security_core/spring_security_core.dart';

import 'example.spring.dart';

class Order {
  const Order(this.id, this.owner);
  final String id;
  final String owner;

  @override
  String toString() => 'Order($id of $owner)';
}

@Service()
class OrderService {
  final _orders = const [Order('1', 'ada'), Order('2', 'bob')];

  /// Admins cancel any order, users their own.
  @PreAuthorize("hasRole('ADMIN') or #order.owner == authentication.name")
  Future<String> cancel(Order order) async => 'cancelled ${order.id}';

  /// The result is checked after the call.
  @PostAuthorize('returnObject.owner == authentication.name')
  Future<Order> find(String id) async =>
      _orders.firstWhere((order) => order.id == id);

  /// Each user sees only their own orders.
  @PostFilter("hasRole('ADMIN') or filterObject.owner == authentication.name")
  Future<List<Order>> all() async => [..._orders];
}

@Configuration()
class UserSetup {
  /// Passwords are stored hashed (`{argon2}...`), never as they are.
  @Bean()
  UserDetailsService users() {
    final encoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
    return InMemoryUserDetailsManager([
      User.withUsername('ada')
          .password(encoder.encode('ada-secret'))
          .roles(['USER'])
          .build(),
      User.withUsername('root')
          .password(encoder.encode('root-secret'))
          .roles(['ADMIN'])
          .build(),
    ]);
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = springApplication.run(args);
  final manager = context.getBean<AuthenticationManager>();
  final orders = context.getBean<OrderService>();

  // Log in (a Flutter app keeps the result as the logged-in user).
  final ada = await manager.authenticate(
    UsernamePasswordAuthenticationToken.unauthenticated('ada', 'ada-secret'),
  );
  SecurityContextHolder.setContext(SecurityContextImpl(ada));

  print(await orders.cancel(const Order('1', 'ada'))); // cancelled 1
  print(await orders.all()); // [Order(1 of ada)]
  try {
    await orders.find('2');
  } on AccessDeniedException catch (e) {
    print('find 2: ${e.message}'); // find 2: Access Denied
  }

  // A wrong password, an unknown user: the same answer.
  try {
    await manager.authenticate(
      UsernamePasswordAuthenticationToken.unauthenticated('ada', 'guess'),
    );
  } on BadCredentialsException catch (e) {
    print('login: ${e.message}'); // login: Bad credentials
  }

  // Work as another user for a while (a job, a test).
  final root = await manager.authenticate(
    UsernamePasswordAuthenticationToken.unauthenticated('root', 'root-secret'),
  );
  await SecurityContextHolder.runWithContext(() async {
    print(await orders.all()); // [Order(1 of ada), Order(2 of bob)]
  }, SecurityContextImpl(root));

  context.close();
}
