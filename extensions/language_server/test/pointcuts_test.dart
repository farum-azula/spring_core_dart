import 'package:dart_spring_language_server/src/pointcuts.dart';
import 'package:test/test.dart';

void main() {
  List<String> scan(String source) => [
    for (final part in scanPointcut(source)) '$part',
  ];

  test('designators, operators and named references', () {
    expect(scan('within(*Service) && !Audit.orders() or bean(x)'), [
      'designator(within)',
      'type(*Service)',
      'operator(&&)',
      'operator(!)',
      'aspect(Audit)',
      'reference(orders)',
      'operator(or)',
      'designator(bean)',
      'bean(x)',
    ]);
  });

  test('execution patterns', () {
    expect(scan('execution(public Future<int> Calc.slow*(int, *, ..))'), [
      'designator(execution)',
      'designator(public)',
      'type(Future)',
      'type(int)',
      'declaringType(Calc)',
      'member(slow*)',
      'type(int)',
      'wildcard(*)',
      'wildcard(..)',
    ]);
    expect(scan('execution(* *(..))'), [
      'designator(execution)',
      'wildcard(*)',
      'wildcard(*)',
      'wildcard(..)',
    ]);
  });

  test('broken expressions do not throw', () {
    for (final source in ['', 'within(', 'execution(* a.b(', '&& ||', '))']) {
      expect(() => scanPointcut(source), returnsNormally, reason: source);
    }
  });

  test('offsets point at the source', () {
    const source = '@annotation(Timed)';
    final part = scanPointcut(source).last;
    expect(source.substring(part.start, part.end), 'Timed');
  });
}
