// The start measured and paced: ApplicationStartup's steps (one per bean
// the context creates, tagged with its name) and the StartupPacer asked
// between two beans on the asynchronous path, its pause awaited.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

final class _Pacer implements StartupPacer {
  final asked = <String>[];
  final List<String> created;
  var pauses = 0;

  _Pacer(this.created);

  @override
  Future<void>? pace() {
    asked.add(created.last);
    pauses++;
    return pauses.isEven ? Future<void>.delayed(Duration.zero) : null;
  }
}

BeanModule _module(List<String> created) => BeanModule('test', [
  for (final name in ['a', 'b', 'c'])
    BeanDefinition<Object>(
      name: name,
      create: (_) {
        created.add(name);
        return Object();
      },
    ),
]);

void main() {
  test('a step per bean, tagged with its name', () {
    final startup = BufferingApplicationStartup();
    final factory = DefaultListableBeanFactory()
      ..applicationStartup = startup;
    final created = <String>[];
    for (final definition in _module(created).definitions) {
      factory.registerBeanDefinition(definition);
    }
    factory.preInstantiateSingletons();
    final steps = startup.steps.where(
      (s) => s.name == 'spring.beans.instantiate',
    );
    expect([for (final s in steps) s.tags.single], [
      ('beanName', 'a'),
      ('beanName', 'b'),
      ('beanName', 'c'),
    ]);
    expect(steps.every((s) => s.duration != null), isTrue);
  });

  test('nested steps know their parent; ended steps are told', () {
    final ended = <String>[];
    final startup = BufferingApplicationStartup(
      onEnd: (step) => ended.add(step.name),
    );
    final outer = startup.start('outer');
    final inner = startup.start('inner')..end();
    outer.end();
    expect(inner.parentId, outer.id);
    expect(ended, ['inner', 'outer']);
    expect(ApplicationStartup.none.start('x').tags, isEmpty);
  });

  test('the pacer is asked after each bean, its pause awaited', () async {
    final created = <String>[];
    final pacer = _Pacer(created);
    final factory = DefaultListableBeanFactory()..startupPacer = pacer;
    for (final definition in _module(created).definitions) {
      factory.registerBeanDefinition(definition);
    }
    await factory.preInstantiateSingletonsAsync();
    expect(pacer.asked, ['a', 'b', 'c']);
    expect(created, ['a', 'b', 'c']);
  });
}
