// SecurityContextHolder: the static entry point to the current context,
// which delegates to a strategy that can be replaced; plus the contexts of
// the strategies themselves. Tests that replace the strategy restore it.
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

void main() {
  late SecurityContextHolderStrategy original;

  setUp(() => original = SecurityContextHolder.getContextHolderStrategy());

  tearDown(() {
    SecurityContextHolder.clearContext();
    SecurityContextHolder.setContextHolderStrategy(original);
  });

  group('the static holder', () {
    test('uses the Zone strategy unless told otherwise', () {
      expect(original, isA<ZoneSecurityContextHolderStrategy>());
    });

    test('an empty context at first; set and clear replace it', () {
      expect(SecurityContextHolder.getContext().authentication, isNull);

      SecurityContextHolder.setContext(
        SecurityContextImpl(TestingAuthenticationToken('ada', null)),
      );
      expect(SecurityContextHolder.getContext().authentication!.name, 'ada');

      SecurityContextHolder.clearContext();
      expect(SecurityContextHolder.getContext().authentication, isNull);
    });

    test('changing the authentication of the context is seen by the next '
        'reader', () {
      SecurityContextHolder.getContext().authentication =
          TestingAuthenticationToken('ada', null);
      expect(SecurityContextHolder.getContext().authentication!.name, 'ada');
    });

    test('createEmptyContext gives a new context each time and does not '
        'make it current', () {
      final a = SecurityContextHolder.createEmptyContext();
      final b = SecurityContextHolder.createEmptyContext();
      expect(a, isA<SecurityContextImpl>());
      expect(identical(a, b), isFalse);
      expect(identical(a, SecurityContextHolder.getContext()), isFalse);
    });

    test('runWithContext gives the body a context of its own', () {
      SecurityContextHolder.setContext(
        SecurityContextImpl(TestingAuthenticationToken('outer', null)),
      );

      final inside = SecurityContextHolder.runWithContext(
        () => SecurityContextHolder.getContext().authentication!.name,
        SecurityContextImpl(TestingAuthenticationToken('inner', null)),
      );
      final empty = SecurityContextHolder.runWithContext(
        () => SecurityContextHolder.getContext().authentication,
      );

      expect(inside, 'inner');
      expect(empty, isNull);
      expect(SecurityContextHolder.getContext().authentication!.name, 'outer');
    });

    test('the strategy can be replaced; everything then goes through it', () {
      final replacement = _CountingStrategy();

      SecurityContextHolder.setContextHolderStrategy(replacement);

      expect(
        SecurityContextHolder.getContextHolderStrategy(),
        same(replacement),
      );
      SecurityContextHolder.setContext(SecurityContextImpl());
      SecurityContextHolder.getContext();
      SecurityContextHolder.createEmptyContext();
      SecurityContextHolder.runWithContext(() {});
      SecurityContextHolder.clearContext();
      expect(replacement.calls, [
        'setContext',
        'getContext',
        'createEmptyContext',
        'runWithContext',
        'clearContext',
      ]);
    });

    test('a global strategy shares one context across scopes (for a '
        'Flutter app, never a server)', () async {
      SecurityContextHolder.setContextHolderStrategy(
        GlobalSecurityContextHolderStrategy(),
      );
      SecurityContextHolder.setContext(
        SecurityContextImpl(TestingAuthenticationToken('ada', null)),
      );

      Future<String?> later() async =>
          SecurityContextHolder.getContext().authentication?.name;

      expect(await later(), 'ada');
    });
  });

  group('ZoneSecurityContextHolderStrategy', () {
    test('set and clear work on the program-wide context', () {
      final strategy = ZoneSecurityContextHolderStrategy()
        ..setContext(
          SecurityContextImpl(TestingAuthenticationToken('app', null)),
        );
      expect(strategy.getContext().authentication!.name, 'app');

      strategy.clearContext();
      expect(strategy.getContext().authentication, isNull);
    });

    test('set and clear inside a scope do not touch the program-wide '
        'context', () {
      final strategy = ZoneSecurityContextHolderStrategy()
        ..setContext(
          SecurityContextImpl(TestingAuthenticationToken('app', null)),
        );

      strategy.runWithContext(() {
        strategy.setContext(
          SecurityContextImpl(TestingAuthenticationToken('request', null)),
        );
        expect(strategy.getContext().authentication!.name, 'request');
        strategy.clearContext();
        expect(strategy.getContext().authentication, isNull);
      });

      expect(strategy.getContext().authentication!.name, 'app');
    });

    test("two strategies do not see each other's scopes", () {
      final a = ZoneSecurityContextHolderStrategy();
      final b = ZoneSecurityContextHolderStrategy();

      a.runWithContext(() {
        expect(a.isScoped, isTrue);
        expect(b.isScoped, isFalse);
      }, SecurityContextImpl(TestingAuthenticationToken('ada', null)));
    });
  });
}

final class _CountingStrategy implements SecurityContextHolderStrategy {
  final calls = <String>[];
  SecurityContext _context = SecurityContextImpl();

  @override
  SecurityContext getContext() {
    calls.add('getContext');
    return _context;
  }

  @override
  void setContext(SecurityContext context) {
    calls.add('setContext');
    _context = context;
  }

  @override
  void clearContext() {
    calls.add('clearContext');
    _context = SecurityContextImpl();
  }

  @override
  SecurityContext createEmptyContext() {
    calls.add('createEmptyContext');
    return SecurityContextImpl();
  }

  @override
  R runWithContext<R>(R Function() body, [SecurityContext? context]) {
    calls.add('runWithContext');
    return body();
  }
}
