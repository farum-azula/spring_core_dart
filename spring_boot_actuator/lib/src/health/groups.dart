import 'package:spring_boot_actuator/src/endpoint/operation.dart';
import 'package:spring_boot_actuator/src/health/contributor.dart';

/// Who is shown the details or the components of a health report.
///
/// Spring Boot (Java): `Show`.
enum Show {
  /// Nobody.
  never,

  /// Logged-in users who have one of the configured roles (any logged-in
  /// user when no role is configured).
  whenAuthorized,

  /// Everybody.
  always;

  /// Whether a request of [securityContext] is shown it; [roles] are the
  /// configured roles.
  bool isShown(SecurityContext securityContext, List<String> roles) =>
      switch (this) {
        Show.never => false,
        Show.always => true,
        Show.whenAuthorized => isAuthorized(securityContext, roles),
      };

  /// Whether the user of [securityContext] is logged in and has one of
  /// [roles] (any role when [roles] is empty).
  static bool isAuthorized(
    SecurityContext securityContext,
    List<String> roles,
  ) =>
      securityContext.principal != null &&
      (roles.isEmpty || roles.any(securityContext.isUserInRole));
}

/// A part of the health report: the contributors it includes, who sees
/// what, how the statuses aggregate and which HTTP status they answer.
///
/// The whole report is the primary group;
/// `management.endpoint.health.group.<name>.*` adds named groups
/// (`/actuator/health/<name>`), and the probes add `liveness` and
/// `readiness`.
///
/// Spring Boot (Java): `HealthEndpointGroup`.
abstract interface class HealthEndpointGroup {
  /// Whether the contributor [name] (a top-level name, or `parent/child`
  /// for one inside a composite) is in the group.
  bool isMember(String name);

  /// Whether a request of [securityContext] is shown the components.
  bool showComponents(SecurityContext securityContext);

  /// Whether a request of [securityContext] is shown the details.
  bool showDetails(SecurityContext securityContext);

  /// How the statuses of the members aggregate.
  StatusAggregator get statusAggregator;

  /// The HTTP status of the group's status.
  HttpCodeStatusMapper get httpCodeStatusMapper;

  /// An extra path the group answers at (`server:/livez`), or `null`.
  String? get additionalPath;
}

/// The primary group and the named groups of the health report.
///
/// Spring Boot (Java): `HealthEndpointGroups`.
abstract interface class HealthEndpointGroups {
  /// The groups of [primary] and [named].
  factory HealthEndpointGroups.of(
    HealthEndpointGroup primary,
    Map<String, HealthEndpointGroup> named,
  ) = _HealthEndpointGroups;

  /// The group of the whole report.
  HealthEndpointGroup get primary;

  /// The names of the named groups.
  List<String> get names;

  /// The named group [name], or `null`.
  HealthEndpointGroup? get(String name);
}

final class _HealthEndpointGroups implements HealthEndpointGroups {
  _HealthEndpointGroups(this.primary, Map<String, HealthEndpointGroup> named)
    : _named = Map.unmodifiable(named);

  @override
  final HealthEndpointGroup primary;

  final Map<String, HealthEndpointGroup> _named;

  @override
  List<String> get names => List.unmodifiable(_named.keys);

  @override
  HealthEndpointGroup? get(String name) => _named[name];
}

/// A [HealthEndpointGroup] from the properties: the members it
/// [include]s minus those it [exclude]s, and its settings.
///
/// Spring Boot (Java): `AutoConfiguredHealthEndpointGroup` with its
/// `IncludeExcludeGroupMemberPredicate`.
final class SimpleHealthEndpointGroup implements HealthEndpointGroup {
  /// A group of [include] (every contributor when empty or `*`) minus
  /// [exclude].
  SimpleHealthEndpointGroup({
    List<String> include = const [],
    List<String> exclude = const [],
    this.showDetailsMode = Show.never,
    this.showComponentsMode,
    List<String> roles = const [],
    this.statusAggregator = StatusAggregator.defaults,
    this.httpCodeStatusMapper = HttpCodeStatusMapper.defaults,
    this.additionalPath,
  }) : include = _clean(include),
       exclude = _clean(exclude),
       roles = List.unmodifiable(roles);

  /// The included names (`*` for all; empty for all).
  final Set<String> include;

  /// The excluded names (`*` for all).
  final Set<String> exclude;

  /// Who is shown the details.
  final Show showDetailsMode;

  /// Who is shown the components; `null` for the same as
  /// [showDetailsMode].
  final Show? showComponentsMode;

  /// The roles `when-authorized` asks for.
  final List<String> roles;

  @override
  final StatusAggregator statusAggregator;

  @override
  final HttpCodeStatusMapper httpCodeStatusMapper;

  @override
  final String? additionalPath;

  static Set<String> _clean(List<String> names) => {
    for (final name in names)
      if (name.trim().isNotEmpty) name.trim(),
  };

  @override
  bool isMember(String name) {
    bool matches(Set<String> names) {
      if (names.contains('*') || names.contains(name)) {
        return true;
      }
      // `db` covers `db/primary`.
      var current = name;
      while (current.contains('/')) {
        current = current.substring(0, current.lastIndexOf('/'));
        if (names.contains(current)) {
          return true;
        }
      }
      return false;
    }

    // A composite is a member when one of its parts is included
    // (`db/primary`), so the report reaches that part.
    final included =
        include.isEmpty ||
        matches(include) ||
        include.any((member) => member.startsWith('$name/'));
    return included && !matches(exclude);
  }

  @override
  bool showComponents(SecurityContext securityContext) =>
      showComponentsMode?.isShown(securityContext, roles) ??
      showDetails(securityContext);

  @override
  bool showDetails(SecurityContext securityContext) =>
      showDetailsMode.isShown(securityContext, roles);
}
