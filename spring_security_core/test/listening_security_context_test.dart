// ListeningSecurityContextHolderStrategy: listeners hear about every set
// and clear, the delegate keeps the contexts, and removed listeners hear
// nothing more.
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

final class _Recorder implements SecurityContextChangedListener {
  final events = <SecurityContextChangedEvent>[];

  @override
  void securityContextChanged(SecurityContextChangedEvent event) =>
      events.add(event);
}

void main() {
  test('reports a set with the contexts before and after', () {
    final delegate = ZoneSecurityContextHolderStrategy();
    final recorder = _Recorder();
    final strategy = ListeningSecurityContextHolderStrategy(delegate, [
      recorder,
    ]);
    final ada = SecurityContextImpl(TestingAuthenticationToken('ada', null));

    strategy.setContext(ada);

    expect(delegate.getContext(), same(ada));
    expect(strategy.getContext(), same(ada));
    final event = recorder.events.single;
    expect(event.oldContext.authentication, isNull);
    expect(event.newContext, same(ada));
    expect(event.isCleared, isFalse);
    expect(event.source, SecurityContextHolder);
  });

  test('reports a clear as a change to no context', () {
    final recorder = _Recorder();
    final strategy = ListeningSecurityContextHolderStrategy(
      GlobalSecurityContextHolderStrategy(),
    )..addListener(recorder);
    final ada = SecurityContextImpl(TestingAuthenticationToken('ada', null));
    strategy
      ..setContext(ada)
      ..clearContext();

    expect(recorder.events, hasLength(2));
    expect(recorder.events.last.oldContext, same(ada));
    expect(recorder.events.last.isCleared, isTrue);
    expect(strategy.getContext().authentication, isNull);
  });

  test('a removed listener hears nothing more', () {
    final recorder = _Recorder();
    ListeningSecurityContextHolderStrategy(
        ZoneSecurityContextHolderStrategy(),
        [recorder],
      )
      ..removeListener(recorder)
      ..setContext(SecurityContextImpl());

    expect(recorder.events, isEmpty);
  });

  test('scopes and empty contexts come from the delegate', () {
    final delegate = ZoneSecurityContextHolderStrategy();
    final strategy = ListeningSecurityContextHolderStrategy(delegate);
    final bob = SecurityContextImpl(TestingAuthenticationToken('bob', null));

    final name = strategy.runWithContext(
      () => strategy.getContext().authentication?.name,
      bob,
    );

    expect(name, 'bob');
    expect(strategy.getContext().authentication, isNull);
    expect(strategy.createEmptyContext(), isA<SecurityContextImpl>());
  });
}
