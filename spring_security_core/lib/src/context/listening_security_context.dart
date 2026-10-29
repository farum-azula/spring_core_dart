import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/context/security_context.dart';

/// What changed when a [SecurityContext] was set or cleared: the context
/// before and the one after.
///
/// [ListeningSecurityContextHolderStrategy] hands one to its listeners
/// after each `setContext` and `clearContext`. A Flutter app uses it to
/// redraw what depends on the logged-in user
/// (`spring_boot_starter_flutter_security`'s `PrincipalNotifier` does).
///
/// Spring (Java): `SecurityContextChangedEvent`.
class SecurityContextChangedEvent extends ApplicationEvent {
  /// A change from [oldContext] to [newContext] (`null`: cleared).
  SecurityContextChangedEvent(this.oldContext, this.newContext)
    : super(SecurityContextHolder);

  /// The context before the change.
  final SecurityContext oldContext;

  /// The context after the change; `null` when the context was cleared.
  final SecurityContext? newContext;

  /// Whether the context was cleared (`clearContext`, a logout).
  bool get isCleared => newContext == null;
}

/// Called after each change of the current [SecurityContext] made through
/// a [ListeningSecurityContextHolderStrategy].
///
/// Spring (Java): `SecurityContextChangedListener`.
abstract interface class SecurityContextChangedListener {
  /// Called after the change; [event] has the contexts before and after.
  void securityContextChanged(SecurityContextChangedEvent event);
}

/// A [SecurityContextHolderStrategy] that tells listeners about every
/// `setContext` and `clearContext`, and leaves the rest to the strategy
/// it wraps.
///
/// A login or logout sets or clears the context; code that shows the
/// user (a Flutter app's widgets) needs to know when that happens. Wrap
/// the strategy in use with it, once at startup:
///
/// ```dart
/// SecurityContextHolder.setContextHolderStrategy(
///   ListeningSecurityContextHolderStrategy(
///     SecurityContextHolder.getContextHolderStrategy(),
///     [auditListener],
///   ),
/// );
/// ```
///
/// Only changes made through it are seen: code that changes the
/// `authentication` of a context object in place, or that kept the old
/// strategy, does not notify. Changes inside a `runWithContext` scope are
/// reported too; a listener that cares about the program-wide context
/// only reads it again outside every scope.
///
/// Spring (Java): `ListeningSecurityContextHolderStrategy`, the same
/// wrapper.
final class ListeningSecurityContextHolderStrategy
    implements SecurityContextHolderStrategy {
  /// A strategy passing every call to [delegate] and telling [listeners]
  /// about the changes.
  ListeningSecurityContextHolderStrategy(
    this.delegate, [
    Iterable<SecurityContextChangedListener> listeners = const [],
  ]) : _listeners = [...listeners];

  /// The strategy that keeps the contexts.
  final SecurityContextHolderStrategy delegate;

  final List<SecurityContextChangedListener> _listeners;

  /// Adds [listener]; it is told about the changes from now on.
  void addListener(SecurityContextChangedListener listener) =>
      _listeners.add(listener);

  /// Removes [listener]; nothing happens when it was not added.
  void removeListener(SecurityContextChangedListener listener) =>
      _listeners.remove(listener);

  @override
  SecurityContext getContext() => delegate.getContext();

  @override
  void setContext(SecurityContext context) {
    final old = delegate.getContext();
    delegate.setContext(context);
    _publish(SecurityContextChangedEvent(old, context));
  }

  @override
  void clearContext() {
    final old = delegate.getContext();
    delegate.clearContext();
    _publish(SecurityContextChangedEvent(old, null));
  }

  @override
  SecurityContext createEmptyContext() => delegate.createEmptyContext();

  @override
  R runWithContext<R>(R Function() body, [SecurityContext? context]) =>
      delegate.runWithContext(body, context);

  void _publish(SecurityContextChangedEvent event) {
    for (final listener in [..._listeners]) {
      listener.securityContextChanged(event);
    }
  }
}
