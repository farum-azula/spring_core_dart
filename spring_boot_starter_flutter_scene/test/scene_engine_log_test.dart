// The engine's messages (written with Flutter's debugPrint) as records of
// the application's log: told apart from Flutter's own, given a level,
// and debugPrint given back.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner, doesNotHaveBean, hasSingleBean;

import 'support/fakes.dart';

void main() {
  late List<SpringLogRecord> records;
  late List<String?> printed;
  late SpringLogHandler handler;
  late DebugPrintCallback print;

  setUp(() {
    records = [];
    printed = [];
    handler = SpringLog.handler;
    print = debugPrint;
    SpringLog.handler = records.add;
    debugPrint = (message, {wrapWidth}) => printed.add(message);
  });

  tearDown(() {
    SpringLog.handler = handler;
    debugPrint = print;
  });

  test('an engine message is a record of the logger flutter_scene', () {
    final log = SceneEngineLog()..install();
    debugPrint(
      'flutter_scene: pipeline build took 66ms mid-frame. Draw this '
      'material once during a load screen.',
    );
    debugPrint('Unpacking glTF (nodes: 1, meshes: 1)');
    debugPrint('fscene: failed to load texture 7');
    log.uninstall();

    expect(printed, isEmpty);
    expect(
      [for (final record in records) record.loggerName],
      [
        'flutter_scene',
        'flutter_scene',
        'flutter_scene',
      ],
    );
    // The engine's name is the logger's, not the message's.
    expect(records[0].message, startsWith('pipeline build took 66ms'));
    expect(records[0].level, SpringLogLevel.warning);
    expect(records[1].message, 'Unpacking glTF (nodes: 1, meshes: 1)');
    expect(records[1].level, SpringLogLevel.info);
    expect(records[2].level, SpringLogLevel.warning);
  });

  test("Flutter's own messages go on as they were", () {
    final log = SceneEngineLog()..install();
    debugPrint('Another exception was thrown: boom');
    debugPrint(null);
    log.uninstall();

    expect(records, isEmpty);
    expect(printed, ['Another exception was thrown: boom', null]);
  });

  test('told apart by where the call came from, without a known beginning', () {
    final engine = StackTrace.fromString(
      '#0 Scene.bake (package:flutter_scene/src/scene.dart:10:3)\n'
      '#1 main (file:///app/main.dart:1:1)',
    );
    final starter = StackTrace.fromString(
      '#0 SceneEngine.start '
      '(package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart:1:1)',
    );
    expect(SceneEngineLog.isEngine('Skipping mesh', stack: engine), isTrue);
    expect(SceneEngineLog.isEngine('Skipping mesh', stack: starter), isFalse);
    expect(SceneEngineLog.isEngine('fscene: x', stack: starter), isTrue);
  });

  test('uninstall gives debugPrint back; twice is once', () {
    final before = debugPrint;
    final log = SceneEngineLog()
      ..install()
      ..install();
    expect(log.installed, isTrue);
    expect(debugPrint, isNot(before));
    log
      ..uninstall()
      ..uninstall();
    expect(debugPrint, before);
  });

  test('something that replaced debugPrint since is left in place', () {
    final log = SceneEngineLog()..install();
    void other(String? message, {int? wrapWidth}) {}
    debugPrint = other;
    log.uninstall();
    expect(debugPrint, other);
  });

  group('the bean', () {
    final runner = const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterSceneAutoConfiguration)
        .withBean<SceneBackend>(FakeBackend.new);

    test('installed with the context, given back when it closes', () {
      final before = debugPrint;
      runner.run((context) {
        expect(context, hasSingleBean<SceneEngineLog>());
        expect(context.getBean<SceneEngineLog>().installed, isTrue);
        expect(debugPrint, isNot(before));
      });
      expect(debugPrint, before);
    });

    test('left alone by its property, and with scenes off', () {
      final before = debugPrint;
      runner.withPropertyValues(['spring.flutter.scene.engine-log=false']).run((
        context,
      ) {
        expect(context, doesNotHaveBean<SceneEngineLog>());
        expect(debugPrint, before);
      });
      runner.withPropertyValues(['spring.flutter.scene.enabled=false']).run((
        context,
      ) {
        expect(context, doesNotHaveBean<SceneEngineLog>());
      });
    });
  });
}
