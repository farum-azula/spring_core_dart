import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/creation_log.dart';
import 'package:spring_core_dart_example/src/data/report.dart';
import 'package:spring_core_dart_example/src/data/store.dart';
import 'package:spring_core_dart_example/src/greeting/greeter.dart';
import 'package:spring_core_dart_example/src/greeting/ticket.dart';

/// Shows every injection style.
@Service()
class GreetingService {
  GreetingService(
    this.greeter,
    @Qualifier('fr') this.french, {
    required this.users,
    required this.all,
    required this.byName,
    required this.unique,
    required this.reports,
    @Value(r'${app.max-greetings:3}') required this.maxGreetings,
    this.missing,
    this.pirate,
  }) {
    creationLog.add('greetingService');
  }

  final Greeter greeter;
  final Greeter french;
  final Store<User> users;

  /// All greeters, ordered by `@Order`.
  final List<Greeter> all;
  final Map<String, Greeter> byName;
  final Set<Greeter> unique;

  /// Lazy access: the report bean is created on first use.
  final ObjectProvider<Report> reports;
  final int maxGreetings;

  /// No bean implements [Missing], so `null` is injected.
  final Missing? missing;

  /// Several greeters match; like Spring, `@Primary` wins over the
  /// parameter name (the name only breaks ties without a primary).
  final Greeter? pirate;

  /// Field injection.
  @Autowired()
  late final Ticket ticket;

  /// Qualified field injection by bean name.
  @Autowired()
  @Qualifier('french')
  late final Greeter frenchByName;

  /// Values from the environment, converted to the field type.
  @Value(r'${app.title:Untitled}')
  late final String title;

  @Value(r'${app.tags}')
  late final List<String> tags;

  @Value(r'${app.optional.missing}')
  String? optionalValue;

  /// Setter injection.
  Ticket? _secondTicket;
  Ticket? get secondTicket => _secondTicket;
  @Autowired()
  set secondTicket(Ticket? value) => _secondTicket = value;

  /// Method injection, after fields and setters.
  @Autowired()
  void init(BeanFactory factory) => initializedWith = factory;

  BeanFactory? initializedWith;

  @PostConstruct()
  void ready() => creationLog.add('greetingService:postConstruct');

  @PreDestroy()
  void shutdown() => creationLog.add('greetingService:preDestroy');

  String greetAll() => users
      .findAll()
      .take(maxGreetings)
      .map((u) => greeter.greet(u.name))
      .join('; ');
}

abstract interface class Missing {}
