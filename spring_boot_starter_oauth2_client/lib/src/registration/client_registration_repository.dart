import 'dart:async';

import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';

/// Finds the [ClientRegistration] of an id, such as `keycloak`.
///
/// Everything that logs in or gets tokens starts here: the authorized
/// client manager, the Feign interceptor and the logins (the security
/// starter's `oauth2Login()`, the app login of
/// `spring_boot_starter_flutter_security`). The starter declares one
/// built from the `spring.security.oauth2.client.*` properties; declare
/// your own bean to keep registrations elsewhere (a database of tenants,
/// for example).
///
/// ```dart
/// final registration = await repository.findByRegistrationId('keycloak');
/// log.info(registration?.providerDetails.tokenUri);
/// ```
///
/// Spring (Java): `ClientRegistrationRepository`. [findByRegistrationId]
/// returns a `Future` here, because a registration whose provider is
/// discovered from its `issuer-uri` is resolved at its first use, not at
/// startup.
abstract interface class ClientRegistrationRepository {
  /// The registration [registrationId], or `null` when there is none.
  ///
  /// Throws when the registration exists but its provider cannot be
  /// discovered right now (no network, a wrong issuer); the next call
  /// tries again.
  Future<ClientRegistration?> findByRegistrationId(String registrationId);
}

/// Builds a registration when it is first needed, such as one whose
/// provider is discovered from its issuer.
typedef ClientRegistrationSupplier = Future<ClientRegistration> Function();

/// A [ClientRegistrationRepository] holding its registrations in memory.
///
/// It is the repository the starter declares from the properties. A
/// registration is either given whole, or as a [ClientRegistrationSupplier]
/// that is called on first use and whose result is kept; a supplier that
/// fails is called again next time. That is how a registration with an
/// `issuer-uri` lets the application start without the provider (an app
/// starts offline).
///
/// ```dart
/// @Bean()
/// ClientRegistrationRepository registrations() =>
///     InMemoryClientRegistrationRepository([
///       CommonOAuth2Provider.google
///           .getBuilder('google')
///           .clientId('...apps.googleusercontent.com')
///           .build(),
///     ]);
/// ```
///
/// Spring (Java): `InMemoryClientRegistrationRepository`; the lazy
/// suppliers are this package's (Spring Boot discovers at startup).
final class InMemoryClientRegistrationRepository
    implements ClientRegistrationRepository {
  /// A repository of [registrations].
  ///
  /// Throws an [ArgumentError] when there are none or two share an id.
  InMemoryClientRegistrationRepository(
    Iterable<ClientRegistration> registrations,
  ) : this.lazy({
        for (final registration in _unique(registrations))
          registration.registrationId: () async => registration,
      });

  /// A repository whose registrations [suppliers] build on first use, by
  /// id.
  ///
  /// Throws an [ArgumentError] when [suppliers] is empty.
  InMemoryClientRegistrationRepository.lazy(
    Map<String, ClientRegistrationSupplier> suppliers,
  ) : _suppliers = Map.unmodifiable(suppliers) {
    if (suppliers.isEmpty) {
      throw ArgumentError('registrations cannot be empty');
    }
  }

  final Map<String, ClientRegistrationSupplier> _suppliers;
  final Map<String, Future<ClientRegistration>> _resolved = {};

  /// The ids of the registrations, such as `keycloak` and `google`, in the
  /// order given; a login page lists them.
  Iterable<String> get registrationIds => _suppliers.keys;

  @override
  Future<ClientRegistration?> findByRegistrationId(
    String registrationId,
  ) async {
    final supplier = _suppliers[registrationId];
    if (supplier == null) {
      return null;
    }
    final pending = _resolved[registrationId] ??= supplier();
    try {
      return await pending;
    } on Object {
      // Not kept: the next call tries again (the provider may be back).
      if (identical(_resolved[registrationId], pending)) {
        unawaited(_resolved.remove(registrationId));
      }
      rethrow;
    }
  }

  static Iterable<ClientRegistration> _unique(
    Iterable<ClientRegistration> registrations,
  ) {
    final ids = <String>{};
    for (final registration in registrations) {
      if (!ids.add(registration.registrationId)) {
        throw ArgumentError(
          'Duplicate key ${registration.registrationId}',
        );
      }
    }
    return registrations;
  }
}
