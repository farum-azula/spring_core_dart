// What the WebSocket handlers and the methods that send JSON need of the
// classes they read and write (the WebSocket part, IntrospectionNeed).
import 'package:spring_core_dart_generator/src/core/introspection/introspection_scanner.dart'
    show mayCallMapper;
import 'package:spring_core_dart_generator/src/websocket/websocket_generation.dart';
import 'package:test/test.dart';

import '../support/introspection_needs.dart';

void main() {
  late final String output;

  setUpAll(() async {
    (output, _) = await generateNeeds(needsModels);
  });

  String shape(String name) => shapeOf(output, name);

  group('messages', () {
    test('an endpoint reads in the message and writes out the reply', () {
      expect(
        shape('ChatMessage'),
        'set text; instantiate; constructor; parts write',
      );
      expect(shape('ChatReply'), 'get text; parts read');
    });

    test('the other handlers describe nothing', () {
      expect(introspectionOf(output, 'Untouched'), isNull);
    });
  });

  group('direct calls of the ObjectMapper', () {
    test('so do the WebSocket methods that write a value as JSON', () {
      expect(shape('Pushed'), 'get p; parts read');
      expect(shape('Broadcast'), 'get b; parts read');
    });

    test('broadcast and sendJson count only where the starter is imported', () {
      // `StreamController.broadcast` is everywhere: such a library is not
      // resolved, as one that names no mapper method.
      const source =
          'final stream = controller.stream.asBroadcastStream();\n'
          'final events = StreamController<int>.broadcast();\n'
          'void send(Object o) => session.sendJson(o);';
      final webSocket = [
        for (final writer in const WebSocketGeneration().jsonWriters)
          writer.method,
      ];
      expect(mayCallMapper(source), isFalse);
      expect(mayCallMapper(source, writers: webSocket), isTrue);
      expect(mayCallMapper('mapper.readValue<Book>(text);'), isTrue);
      expect(mayCallMapper('final a = 1;', writers: webSocket), isFalse);
    });
  });
}
