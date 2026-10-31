import 'dart:async';

import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';

/// Switches auditing on: the properties marked `@CreatedDate`,
/// `@LastModifiedDate`, `@CreatedBy` and `@LastModifiedBy` are set when an
/// entity is saved. Put it on a `@Configuration` class.
///
/// The auditor (who `@CreatedBy` and `@LastModifiedBy` record) comes from
/// the [AuditorAware] bean named [auditorAwareRef], or the only one when
/// the name is empty; the time from the [DateTimeProvider] bean named
/// [dateTimeProviderRef], or the system clock when the name is empty and
/// there is none.
///
/// ```dart
/// @Configuration()
/// @EnableDataAuditing()
/// class AuditConfig {}
/// ```
///
/// Spring (Java):
/// `org.springframework.data.jdbc.repository.config.EnableJdbcAuditing`.
class EnableDataAuditing {
  /// Switches auditing on, with the beans [auditorAwareRef] and
  /// [dateTimeProviderRef] when named.
  const EnableDataAuditing({
    this.auditorAwareRef = '',
    this.dateTimeProviderRef = '',
    this.setDates = true,
    this.modifyOnCreate = true,
  });

  /// The name of the [AuditorAware] bean; empty for the only one.
  final String auditorAwareRef;

  /// The name of the [DateTimeProvider] bean; empty for the only one, or the
  /// system clock.
  final String dateTimeProviderRef;

  /// Whether `@CreatedDate` and `@LastModifiedDate` are set; when false only
  /// the auditor properties are.
  final bool setDates;

  /// Whether an insert also sets the `@LastModifiedDate` and
  /// `@LastModifiedBy` properties (as the creation's values).
  final bool modifyOnCreate;
}

/// Tells who is acting: the value of `@CreatedBy` and `@LastModifiedBy`
/// properties. With the security starter, the logged-in user's name.
///
/// An answer of null (nobody is logged in) leaves the properties as they
/// are.
///
/// Spring (Java): `org.springframework.data.domain.AuditorAware`.
abstract interface class AuditorAware<T> {
  /// The current auditor, or null when there is none; may be asynchronous.
  FutureOr<T?> getCurrentAuditor();
}

/// Tells the time auditing records, a clock that tests can replace. By
/// default the system clock ([DateTime.now]).
///
/// Spring (Java): `org.springframework.data.auditing.DateTimeProvider`.
class DateTimeProvider {
  /// A provider answering [clock]'s time (by default [DateTime.now]).
  const DateTimeProvider([DateTime Function()? clock]) : _clock = clock;

  final DateTime Function()? _clock;

  /// The current time.
  DateTime now() => (_clock ?? DateTime.now)();
}

/// Decides whether an entity is new, so `save` inserts it, or existing, so
/// `save` updates it.
///
/// The rule is Spring Data JDBC's: with a `@Version` property, an entity is
/// new when the version is null or (an `int`) 0; a `DateTime` version is
/// new only when null. Without one, an entity is new when its id is null.
/// A class with neither a version nor an id cannot be saved: a
/// [MappingException].
///
/// Spring (Java):
/// `org.springframework.data.support.IsNewStrategy` (the default is
/// `PersistentEntityIsNewStrategy`).
class IsNewStrategy {
  /// The default rule.
  const IsNewStrategy();

  /// Whether [instance] of [entity]'s class has not been stored yet.
  bool isNew(PersistentEntity<Object> entity, Object instance) {
    if (entity.versionProperty case final version?) {
      final value = version.getValue(instance);
      return value == null || (value is int && value == 0);
    }
    if (entity.idProperty case final id?) {
      return id.getValue(instance) == null;
    }
    throw MappingException(
      '${entity.introspection.className} has neither an @Id nor a @Version '
      'property: it cannot tell whether it is new',
    );
  }
}

/// Sets the audit properties of an entity about to be saved: the time and
/// the auditor, created at the insert, last modified at the insert (when
/// [modifyOnCreate]) and at each update.
///
/// An entity with `final` audit properties is copied (see
/// [EntityConverter.withValues]): use what the methods return, not the
/// instance given.
///
/// Spring (Java):
/// `org.springframework.data.auditing.AuditingHandler`
/// (`IsNewAwareAuditingHandler`).
class AuditingHandler {
  /// A handler setting properties through [converter], with the auditor from
  /// [auditorAware] (none when null) and the time from [dateTimeProvider].
  AuditingHandler({
    required this.converter,
    this.auditorAware,
    this.dateTimeProvider = const DateTimeProvider(),
    this.setDates = true,
    this.modifyOnCreate = true,
  });

  /// Reads and writes the properties.
  final EntityConverter converter;

  /// Tells who the auditor is; null for no auditor properties set.
  final AuditorAware<Object>? auditorAware;

  /// Tells the time.
  final DateTimeProvider dateTimeProvider;

  /// Whether dates are set at all.
  final bool setDates;

  /// Whether an insert sets the last-modified properties too.
  final bool modifyOnCreate;

  /// [instance] marked as created: `@CreatedDate` and `@CreatedBy` set, and
  /// (with [modifyOnCreate]) `@LastModifiedDate` and `@LastModifiedBy`.
  Future<T> markCreated<T extends Object>(
    PersistentEntity<T> entity,
    T instance,
  ) => _touch(entity, instance, created: true);

  /// [instance] marked as modified: `@LastModifiedDate` and
  /// `@LastModifiedBy` set; the created properties are kept.
  Future<T> markModified<T extends Object>(
    PersistentEntity<T> entity,
    T instance,
  ) => _touch(entity, instance, created: false);

  Future<T> _touch<T extends Object>(
    PersistentEntity<T> entity,
    T instance, {
    required bool created,
  }) async {
    final audited = entity.properties.where((p) => p.audit != null).toList();
    if (audited.isEmpty) {
      return instance;
    }
    final needsAuditor = audited.any(
      (p) =>
          p.audit == AuditKind.createdBy || p.audit == AuditKind.lastModifiedBy,
    );
    final auditor = needsAuditor
        ? await auditorAware?.getCurrentAuditor()
        : null;
    final now = setDates ? dateTimeProvider.now() : null;
    final changes = <String, Object?>{};
    for (final p in audited) {
      switch (p.audit!) {
        case AuditKind.createdDate:
          if (created && now != null) {
            changes[p.name] = now;
          }
        case AuditKind.createdBy:
          if (created && auditor != null) {
            changes[p.name] = auditor;
          }
        case AuditKind.lastModifiedDate:
          if ((!created || modifyOnCreate) && now != null) {
            changes[p.name] = now;
          }
        case AuditKind.lastModifiedBy:
          if ((!created || modifyOnCreate) && auditor != null) {
            changes[p.name] = auditor;
          }
      }
    }
    if (changes.isEmpty) {
      return instance;
    }
    // T is an entity, never a Future.
    // ignore: async_return_with_no_await
    return converter.withValues(entity, instance, changes);
  }
}
