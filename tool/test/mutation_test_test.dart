// tool/mutation_test.dart: every mutant changes the code, in the intended
// way (a mutant equal to the original would "survive" and look like a
// missing test).
import 'package:test/test.dart';

import '../mutation_test.dart';

Map<String, String> _mutants(String line) => {
  for (final mutant in mutantsOf('f.dart', [line]))
    mutant.mutation.name: mutant.mutated,
};

void main() {
  test('every mutation changes the line', () {
    for (final line in [
      '    if (!allowed.contains(method)) {',
      '    if (a == b && c != d || e < f) {',
      '    return x.isEmpty ? count + 1 : count - 1;',
      '    final ok = list.any((x) => x >= 2) && list.every((x) => x <= 9);',
      '    flag = true; other = false;',
    ]) {
      for (final mutant in mutantsOf('f.dart', [line])) {
        expect(
          mutant.mutated,
          isNot(mutant.original),
          reason: mutant.mutation.name,
        );
      }
    }
  });

  test('the replacements', () {
    final mutants = _mutants('    if (!allowed.contains(method)) {');
    expect(mutants['!x → x'], '    if (allowed.contains(method)) {');
    expect(
      _mutants('    if (list.contains(a)) {')['contains → !contains'],
      '    if (!list.contains(a)) {',
    );
    expect(_mutants('    a == b;')['== → !='], '    a != b;');
    expect(_mutants('    a <= b;')[' <= → <'], '    a < b;');
  });

  test('comments and string literals are not mutated', () {
    expect(mutantsOf('f.dart', ['    // a == b']), isEmpty);
    expect(mutantsOf('f.dart', ["    print('a == b');"]), isEmpty);
  });
}
