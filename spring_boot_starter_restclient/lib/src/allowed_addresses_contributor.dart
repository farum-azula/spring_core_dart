/// Adds entries to the allow list of the starter's transport (the
/// `httpClientAllowedAddresses` bean): the addresses another starter was
/// given by hand in its own properties, as the base URL of a
/// `spring.http.serviceclient` group is. The OAuth2 client's contributes
/// the hosts of its providers' endpoints.
///
/// Declare one as a bean; every one is asked when the allow list is made.
/// An entry has a form of `AllowedAddresses` (a host, `*.domain`, an
/// address, a CIDR block, a URL whose host is taken). Contribute only what
/// the application wrote itself: an address read from the network (a
/// discovery document) is not allowed by hand.
///
/// ```dart
/// @Bean()
/// AllowedAddressesContributor inventory(InventoryProperties inventory) =>
///     AllowedAddressesContributor.of([inventory.url]);
/// ```
///
/// Spring (Java): no counterpart; Spring Boot allows every address until
/// an `InetAddressFilter` is set.
abstract interface class AllowedAddressesContributor {
  /// The contributor of [entries].
  const factory AllowedAddressesContributor.of(Iterable<String> entries) =
      _FixedContributor;

  /// The entries to allow.
  Iterable<String> allowedAddresses();
}

final class _FixedContributor implements AllowedAddressesContributor {
  const _FixedContributor(this._entries);

  final Iterable<String> _entries;

  @override
  Iterable<String> allowedAddresses() => _entries;
}
