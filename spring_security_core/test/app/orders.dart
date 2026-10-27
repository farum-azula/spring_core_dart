import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_security_core/spring_security_core.dart';

class Purchase {
  Purchase(this.id, this.owner);

  final String id;
  final String owner;

  @override
  String toString() => 'Purchase($id, $owner)';
}

@Service()
class OrderService {
  final calls = <String>[];

  @PreAuthorize("hasRole('ADMIN') or #order.owner == principal.username")
  void cancel(Purchase order) => calls.add('cancel ${order.id}');

  @PreAuthorize("hasRole('ADMIN') or #order.owner == authentication.name")
  Future<String> cancelLater(Purchase order) async {
    calls.add('cancelLater ${order.id}');
    return 'cancelled ${order.id}';
  }

  @PostAuthorize('returnObject.owner == authentication.name')
  Purchase find(String id) {
    calls.add('find $id');
    return Purchase(id, id == '1' ? 'ada' : 'bob');
  }

  @PostAuthorize('returnObject.owner == authentication.name')
  Future<Purchase> findLater(String id) async => find(id);

  @Secured(['ROLE_SUPPORT'])
  String refund(String id) => 'refunded $id';

  @PreFilter('filterObject.owner == authentication.name')
  List<Purchase> keep(List<Purchase> orders) => orders;

  @PreFilter('filterObject.owner == authentication.name', filterTarget: 'mine')
  int count(List<Purchase> mine, List<Purchase> other) =>
      mine.length + other.length;

  @PostFilter('filterObject.owner == authentication.name')
  List<Purchase> all() => [
    Purchase('1', 'ada'),
    Purchase('2', 'bob'),
    Purchase('3', 'ada'),
  ];

  @PostFilter('filterObject.owner == authentication.name')
  Future<List<Purchase>> allLater() async => all();

  @PostFilter('filterObject.value == authentication.name')
  Map<String, String> owners() => {'1': 'ada', '2': 'bob'};

  @PreAuthorize('permitAll')
  String open() => 'open';

  @PreAuthorize('denyAll')
  String closed() => 'closed';

  @PreAuthorize("hasPermission(#order, 'cancel')")
  bool mayCancel(Purchase order) => true;

  @PreAuthorize('isAnonymous()')
  String anonymousOnly() => 'anonymous';

  @PreAuthorize("hasAnyRole('ADMIN', 'SUPPORT') and isAuthenticated()")
  String staff() => 'staff';

  @PreAuthorize('@shop.isOpen()')
  String shopping() => 'shopping';

  @PreAuthorize("'not a boolean'")
  String broken() => 'broken';

  /// Calls [cancel] through `this`: not checked (no proxy in between).
  void cancelInside(Purchase order) => cancel(order);

  String unsecured() => 'unsecured';
}

@Service()
@PreAuthorize("hasRole('ADMIN')")
class AdminService {
  String report() => 'report';

  @PreAuthorize('permitAll')
  String status() => 'ok';
}

@Service()
class Reports {
  int runs = 0;

  // Security before the cache: a cached report is never returned to a
  // caller who may not ask for it.
  @PreAuthorize("hasRole('ADMIN')")
  @Cacheable('reports')
  String report(String id) {
    runs++;
    return 'report $id';
  }
}

// A bean called from an expression is @Introspected (no reflection).
@Component('shop')
@Introspected()
class Shop {
  bool open = true;

  bool isOpen() => open;
}

@Component()
class OrderPermissions implements PermissionEvaluator {
  @override
  bool hasPermission(
    Authentication authentication,
    Object? targetDomainObject,
    Object permission,
  ) =>
      permission == 'cancel' &&
      targetDomainObject is Purchase &&
      targetDomainObject.owner == authentication.name;

  @override
  bool hasPermissionById(
    Authentication authentication,
    Object? targetId,
    String targetType,
    Object permission,
  ) => false;
}

@Configuration()
class HierarchyConfig {
  @Bean()
  RoleHierarchy roleHierarchy() =>
      RoleHierarchyImpl.fromHierarchy('ROLE_ADMIN > ROLE_SUPPORT');
}
