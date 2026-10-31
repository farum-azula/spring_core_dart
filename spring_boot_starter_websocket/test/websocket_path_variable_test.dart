// `@PathVariable` parameters of other types than String on a
// `@WebSocketEndpoint`: converted like a controller's, a value that does
// not convert answers the handshake with 400, a type nothing converts
// stops the start. The definitions are written by hand, as the generator
// writes them for an endpoint class.
import 'dart:async';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

enum Shelf { fiction, science }

final class OrderEndpoint {
  final opened = <(int, Shelf, double?)>[];

  void open(int id, Shelf shelf, double? price) =>
      opened.add((id, shelf, price));
}

final class Room {}

final class RoomEndpoint {
  void open(Room room) {}
}

BeanDefinition<OrderEndpoint> _orders(OrderEndpoint endpoint) =>
    BeanDefinition<OrderEndpoint>(
      name: 'orderEndpoint',
      types: const [OrderEndpoint],
      create: (_) => endpoint,
      annotatedMethods: [
        BeanMethod<OrderEndpoint>(
          'open',
          parameterTypes: const [int, Shelf, double],
          parameters: [
            const BeanParameter(
              'id',
              type: ClassType<int>(),
              isRequired: true,
              annotations: [PathVariable()],
            ),
            const BeanParameter(
              'shelf',
              type: EnumType<Shelf>(Shelf.values),
              isRequired: true,
              annotations: [PathVariable()],
            ),
            const BeanParameter(
              'price',
              type: ClassType<double>(nullable: true),
              isRequired: true,
              annotations: [PathVariable()],
            ),
          ],
          isVoid: true,
          invoke: (bean, arguments) => Function.apply(bean.open, arguments),
          annotations: const [OnOpen()],
        ),
      ],
      annotations: const [WebSocketEndpoint('/ws/orders/{shelf}/{id}/{price}')],
    );

final _rooms = BeanDefinition<RoomEndpoint>(
  name: 'roomEndpoint',
  types: const [RoomEndpoint],
  create: (_) => RoomEndpoint(),
  annotatedMethods: [
    BeanMethod<RoomEndpoint>(
      'open',
      parameterTypes: const [Room],
      parameters: [
        const BeanParameter(
          'room',
          type: ClassType<Room>(),
          isRequired: true,
          annotations: [PathVariable()],
        ),
      ],
      isVoid: true,
      invoke: (bean, arguments) => Function.apply(bean.open, arguments),
      annotations: const [OnOpen()],
    ),
  ],
  annotations: const [WebSocketEndpoint('/ws/rooms/{room}')],
);

WebSocketHandlerMapping _mapping(List<BeanDefinition<Object>> definitions) {
  final factory = DefaultListableBeanFactory();
  definitions.forEach(factory.registerBeanDefinition);
  return WebSocketHandlerMapping(
    beanFactory: factory,
    mapper: ObjectMapper(),
    sessions: WebSocketSessionRegistry(),
  );
}

Future<(MockServerHttpResponse, WebSocketSession?)> _connect(
  WebSocketHandlerMapping mapping,
  String target,
) async {
  final request = MockServerHttpRequest(HttpMethod.get, target);
  request.headers
    ..set('Upgrade', 'websocket')
    ..set('Connection', 'Upgrade');
  final response = MockServerHttpResponse();
  await mapping.getHandler(request)!.handle(request, response);
  final client = await request.webSocketClient
      .then<WebSocketSession?>((c) => c)
      .timeout(const Duration(milliseconds: 50), onTimeout: () => null);
  return (response, client);
}

void main() {
  test('int, enum and double path variables are converted', () async {
    final endpoint = OrderEndpoint();
    final mapping = _mapping([_orders(endpoint)]);
    final (_, client) = await _connect(mapping, '/ws/orders/science/42/9.5');
    expect(client, isNotNull);
    await pumpEventQueue();
    expect(endpoint.opened, [(42, Shelf.science, 9.5)]);
    await client!.close();
  });

  test('a value that does not convert: 400, no connection', () async {
    final endpoint = OrderEndpoint();
    final mapping = _mapping([_orders(endpoint)]);
    for (final target in [
      '/ws/orders/science/forty-two/1',
      '/ws/orders/poetry/42/1',
      '/ws/orders/science/42/cheap',
    ]) {
      final (response, client) = await _connect(mapping, target);
      expect(response.statusCode, 400, reason: target);
      expect(response.bodyText, startsWith('The path variable {'));
      expect(client, isNull);
    }
    expect(endpoint.opened, isEmpty);
  });

  test('a type nothing converts a String to stops the start', () {
    expect(
      () => _mapping([_rooms]).initialize(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains(
            'RoomEndpoint.open(room): a @PathVariable must be a String or a '
            'type the ConversionService converts a String to',
          ),
        ),
      ),
    );
  });
}
