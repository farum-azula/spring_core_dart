import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

// Counts the members an advised bean was called through.
class _Recorder implements MethodInterceptor {
  final calls = <String>[];

  @override
  Object? invoke(MethodInvocation invocation) {
    calls.add(invocation.signature.name);
    return invocation.proceed();
  }
}

// Every properties bean of [module] that can be advised: its proxy must give
// the target's values, pass sets through to the target, and run the advice
// on each member.
void expectAdvisedPropertiesDelegate(BeanModule module) {
  for (final definition in module.definitions) {
    final proxies = definition.aopProxy;
    if (proxies == null) continue;
    if (proxies.unavailableReason != null) {
      test(
        '${definition.name}: advice on a class that cannot be proxied fails',
        () {
          final target = module.introspections
              .where((i) => i.beanType == definition.types.first)
              .firstOrNull
              ?.instantiate();
          if (target == null) return;
          final factory = ProxyFactory(target, proxies)..addAdvice(_Recorder());
          expect(factory.getProxy, throwsA(isA<AopConfigException>()));
        },
      );
      continue;
    }
    final type = definition.types.first;
    final introspection = module.introspections
        .where((i) => i.beanType == type && i.isInstantiable)
        .firstOrNull;
    if (introspection == null) continue;
    test('${definition.name}: an advised bean reads and writes its target', () {
      final target = introspection.instantiate();
      final recorder = _Recorder();
      final proxy = (ProxyFactory(
        target,
        proxies,
      )..addAdvice(recorder)).getProxy();
      expect(proxy, isNot(same(target)));
      for (final property in introspection.properties) {
        if (property.isReadable) {
          expect(
            property.getValue(proxy),
            property.getValue(target),
            reason: property.name,
          );
          expect(recorder.calls, contains(property.name));
        }
        if (property.isWritable && property.isReadable) {
          final before = recorder.calls.length;
          property.setValue(proxy, property.getValue(target));
          expect(recorder.calls.length, before + 1, reason: property.name);
        }
      }
    });
  }
}

// Every described class of [module]: each readable property gives a value and
// each writable one takes it back.
void expectIntrospectedPropertiesRoundTrip(BeanModule module) {
  for (final introspection in module.introspections) {
    if (!introspection.isInstantiable) continue;
    test('${introspection.className}: properties read and write back', () {
      final bean = introspection.instantiate();
      for (final property in introspection.properties) {
        if (!property.isReadable) continue;
        final value = property.getValue(bean);
        if (property.isWritable) {
          property.setValue(bean, value);
          expect(property.getValue(bean), value, reason: property.name);
        }
      }
    });
  }
}
