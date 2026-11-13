import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_signals/src/annotations.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';

const _log = SpringLog('spring.flutter.signals');

/// Matches every member of a bean that has a `@Signal`, `@Computed` or
/// `@Effect` member: the annotated ones are followed, and each of the
/// bean's other methods is one batch of changes.
final class SignalsPointcut implements AnnotationPointcut {
  /// The pointcut over the beans [beans] knows by name.
  const SignalsPointcut(this.beans);

  /// The annotations that make a bean one of these: the generator keeps
  /// the proxies of the beans that carry them.
  static const List<Type> annotationTypes = [Signal, Computed, Effect];

  static const _objectMembers = {
    'toString',
    'noSuchMethod',
    '==',
    'hashCode',
    'runtimeType',
  };

  /// The beans with followed state.
  final SignalBeans beans;

  /// Whether [signature] carries one of the three annotations.
  static bool isAnnotated(MethodSignature signature) =>
      signature.mergedAnnotations.any(
        (annotation) =>
            annotation is Signal ||
            annotation is Computed ||
            annotation is Effect,
      );

  @override
  bool matches(MethodSignature signature, String beanName) =>
      isAnnotated(signature) ||
      (beans.names.contains(beanName) &&
          !_objectMembers.contains(signature.name));

  @override
  String toString() => 'SignalsPointcut';
}

/// The advice on a bean with followed state.
///
/// - A `@Signal` field: a read is followed (what reads it is told of the
///   next assignment), an assignment writes the field and tells them.
/// - A `@Computed` getter or method: computed once and kept until
///   something it read changes; a `Future` or `Stream` is kept the same
///   way, with its state beside it.
/// - Any other method or setter: one batch, so several assignments in it
///   tell their readers once, when it returns.
///
/// An error thrown by the bean's code (a computed value, an effect run by
/// an assignment) reaches the caller as it was thrown, not wrapped.
///
/// While the bean is being destroyed nothing is followed: its members
/// read and write its own fields.
final class SignalsInterceptor implements SelfCallInterceptor {
  /// The advice over the state kept in [beans].
  const SignalsInterceptor(this.beans);

  /// The beans with followed state.
  final SignalBeans beans;

  @override
  Object? invoke(MethodInvocation invocation) =>
      unwrapped(() => _invoke(invocation));

  Object? _invoke(MethodInvocation invocation) {
    final signature = invocation.signature;
    var followed = false;
    var computed = false;
    for (final annotation in signature.mergedAnnotations) {
      followed = followed || annotation is Signal;
      computed = computed || annotation is Computed;
    }
    if (!followed && !computed) {
      // A method, or a setter that is no followed field: one change.
      return signature.kind == MemberKind.getter
          ? invocation.proceed()
          : signals.batch(invocation.proceed);
    }
    final state = beans.of(invocation.proxy, signature.targetType);
    if (state.closed) {
      return invocation.proceed();
    }
    final name = signature.name;
    if (computed) {
      return _computed(state, name, invocation).read();
    }
    if (signature.kind == MemberKind.setter) {
      // A field nobody read yet has nobody to tell: it is mirrored when
      // it is first read, from the field itself.
      if (state.members[name] case final ValueMember member) {
        final value = member.unwrap(invocation.args.single);
        final result = invocation.proceed([value]);
        member.write(value);
        _log.debug(
          () => '${member.name} = ${member.hidden ? '(hidden)' : value}',
        );
        return result;
      }
      return invocation.proceed();
    }
    var member = state.members[name];
    if (member is! ValueMember) {
      final label = '${state.label}.$name';
      final hidden = signature.mergedAnnotations.whereType<Signal>().any(
        (signal) => signal.hidden,
      );
      final Object? value;
      try {
        value = invocation.proceed();
      } on Error {
        // A late field read before it is assigned: the read fails as it
        // always would, and its reader is told of the first assignment.
        (state.members[name] = ValueMember.unset(
          label,
          arguments: signature.returnTypeArguments,
          type: signature.returnType,
          hidden: hidden,
        )).follow();
        rethrow;
      }
      member = state.members[name] = ValueMember(
        label,
        value,
        arguments: signature.returnTypeArguments,
        type: signature.returnType,
        hidden: hidden,
      );
    }
    if (member.unset) {
      member.follow();
      return invocation.proceed();
    }
    return member.read();
  }

  ComputedMember _computed(
    SignalBean state,
    String name,
    MethodInvocation invocation,
  ) {
    final existing = state.members[name];
    if (existing is ComputedMember) {
      return existing;
    }
    final label = '${state.label}.$name';
    // The rest of the chain and the bean's own code, called again each
    // time the value is computed.
    Object? compute() => invocation.proceed();
    final returns = invocation.signature.returnType;
    // The type's name comes without its arguments.
    final member = returns == 'Future' || returns == 'Stream'
        ? AsyncMember(label, compute)
        : ComputedMember(label, compute);
    state.members[name] = member;
    return member;
  }

  @override
  String toString() => 'SignalsInterceptor';
}
