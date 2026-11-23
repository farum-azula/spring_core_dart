/// A name a security expression can use without a prefix, on its root.
final class SecurityName {
  /// [name], shown as [signature] and explained by [documentation].
  const SecurityName(
    this.name,
    this.signature,
    this.documentation, {
    this.isMethod = false,
    this.isProperty = false,
    this.takesArguments = false,
    this.onlyIn,
    this.memberType,
  });

  /// The name as written.
  final String name;

  /// How it is used: `hasRole('ADMIN')`.
  final String signature;

  /// What it means.
  final String documentation;

  /// Whether it can be called.
  final bool isMethod;

  /// Whether it can be read without a call.
  final bool isProperty;

  /// Whether a call needs arguments.
  final bool takesArguments;

  /// The annotations in which it has a value; `null` for all.
  final Set<String>? onlyIn;

  /// The key in [securityMembers] of what it holds.
  final String? memberType;

  /// The text a chosen proposal inserts: the cursor lands where the
  /// arguments go.
  String get insertText => switch ((isMethod, isProperty, takesArguments)) {
    (true, false, true) => '$name(',
    (true, false, false) => '$name()',
    _ => name,
  };

  /// The hover.
  String get hover => '**$signature**\n\n$documentation';
}

/// The annotations whose first argument is a security expression.
const securityAnnotations = {
  'PreAuthorize',
  'PostAuthorize',
  'PreFilter',
  'PostFilter',
};

/// What the root of a security expression offers
/// (`MethodSecurityExpressionRoot`).
const securityNames = <String, SecurityName>{
  'hasRole': SecurityName(
    'hasRole',
    "hasRole('ADMIN')",
    'Whether the user has the role. `ROLE_` is added when missing, and a '
        '`RoleHierarchy` bean applies.',
    isMethod: true,
    takesArguments: true,
  ),
  'hasAnyRole': SecurityName(
    'hasAnyRole',
    "hasAnyRole('ADMIN', 'STAFF')",
    'Whether the user has one of the roles. `ROLE_` is added when missing.',
    isMethod: true,
    takesArguments: true,
  ),
  'hasAuthority': SecurityName(
    'hasAuthority',
    "hasAuthority('SCOPE_read')",
    'Whether the user has the authority, written in full.',
    isMethod: true,
    takesArguments: true,
  ),
  'hasAnyAuthority': SecurityName(
    'hasAnyAuthority',
    "hasAnyAuthority('SCOPE_read', 'SCOPE_write')",
    'Whether the user has one of the authorities, written in full.',
    isMethod: true,
    takesArguments: true,
  ),
  'hasPermission': SecurityName(
    'hasPermission',
    "hasPermission(#order, 'cancel')",
    'Asks the `PermissionEvaluator` bean, and denies when there is none. '
        "Also `hasPermission(#id, 'Order', 'cancel')`.",
    isMethod: true,
    takesArguments: true,
  ),
  'isAuthenticated': SecurityName(
    'isAuthenticated',
    'isAuthenticated()',
    'Whether the user logged in (not anonymous).',
    isMethod: true,
  ),
  'isFullyAuthenticated': SecurityName(
    'isFullyAuthenticated',
    'isFullyAuthenticated()',
    'Whether the user logged in during this session (not "remember me").',
    isMethod: true,
  ),
  'isAnonymous': SecurityName(
    'isAnonymous',
    'isAnonymous()',
    'Whether the user is anonymous.',
    isMethod: true,
  ),
  'isRememberMe': SecurityName(
    'isRememberMe',
    'isRememberMe()',
    'Whether the user came back through "remember me".',
    isMethod: true,
  ),
  'permitAll': SecurityName(
    'permitAll',
    'permitAll',
    'Always `true`.',
    isMethod: true,
    isProperty: true,
  ),
  'denyAll': SecurityName(
    'denyAll',
    'denyAll',
    'Always `false`.',
    isMethod: true,
    isProperty: true,
  ),
  'principal': SecurityName(
    'principal',
    'principal',
    'The current user, such as `principal.username`.',
    isProperty: true,
    memberType: 'UserDetails',
  ),
  'authentication': SecurityName(
    'authentication',
    'authentication',
    'The current `Authentication`, such as `authentication.name`.',
    isProperty: true,
    memberType: 'Authentication',
  ),
  'returnObject': SecurityName(
    'returnObject',
    'returnObject',
    'What the method returned. Only in `@PostAuthorize`.',
    isProperty: true,
    onlyIn: {'PostAuthorize'},
  ),
  'filterObject': SecurityName(
    'filterObject',
    'filterObject',
    'The element being filtered. Only in `@PreFilter` and `@PostFilter`.',
    isProperty: true,
    onlyIn: {'PreFilter', 'PostFilter'},
  ),
  'this': SecurityName(
    'this',
    'this',
    'The bean the method belongs to.',
    isProperty: true,
  ),
};

/// What expressions can read on the security types; passwords and
/// credentials are not readable. A member's value is the key of its own
/// members, or `null`.
const securityMembers = <String, Map<String, String?>>{
  'Authentication': {
    'name': null,
    'principal': 'UserDetails',
    'authorities': null,
    'details': null,
    'authenticated': null,
  },
  'UserDetails': {
    'username': null,
    'authorities': null,
    'enabled': null,
    'accountNonExpired': null,
    'accountNonLocked': null,
    'credentialsNonExpired': null,
  },
};
