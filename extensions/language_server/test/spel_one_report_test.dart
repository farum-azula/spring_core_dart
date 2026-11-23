// Two roles read a `#{...}` of a storage annotation: one mistake is one
// problem.
import 'package:test/test.dart';

import 'support/editor_fixture.dart';

void main() {
  test('an unknown member of a bean is reported once', () {
    final fixture = EditorFixture.create();
    addTearDown(fixture.dispose);
    final path = fixture.open('lib/a.dart', '''
@Service()
class Rules {
  bool ok() => true;
}

class Links {
  @SignedUrl('#{@rules.zzz()}/a.png')
  void link() {}
}
''');
    expect(
      [
        for (final problem in fixture.workspace.problems(path))
          if (problem.message.contains('zzz')) problem.message,
      ],
      ["Unknown member 'zzz' of Rules"],
    );
  });
}
