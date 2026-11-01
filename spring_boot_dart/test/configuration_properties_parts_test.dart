// @ConfigurationProperties classes are described with what the binder
// uses: it sets the properties, and reads their current values only when
// there is a getter. A class described without its constructor and setters
// cannot be bound, and says so.
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

class Server {
  String host = 'localhost';
  int port = 80;
}

BeanIntrospection<Server> describe(Set<IntrospectionPart> parts) {
  final read = parts.contains(IntrospectionPart.read);
  final write = parts.contains(IntrospectionPart.write);
  return BeanIntrospection<Server>(
    parts: parts,
    properties: [
      BeanProperty<Server>(
        'host',
        type: String,
        typeInfo: const ClassType<String>(),
        get: read ? (b) => b.host : null,
        set: write ? (b, v) => b.host = v! as String : null,
      ),
      BeanProperty<Server>(
        'port',
        type: int,
        typeInfo: const ClassType<int>(),
        get: read ? (b) => b.port : null,
        set: write ? (b, v) => b.port = v! as int : null,
      ),
    ],
    instantiate: write ? Server.new : null,
  );
}

void main() {
  StandardEnvironment environment(Map<String, Object?> properties) {
    final env = StandardEnvironment(systemEnvironment: const {})
      ..propertySources.addFirst(MapPropertySource('test', properties));
    ConfigurationPropertySources.attach(env);
    return env;
  }

  Binder binder(Set<IntrospectionPart> parts) => Binder(
    environment({'app.host': 'example.org', 'app.port': '8443'}),
    introspector: BeanIntrospector()..register(describe(parts)),
  );

  test('a class described with getters and setters is bound', () {
    final server = binder({
      IntrospectionPart.read,
      IntrospectionPart.write,
    }).bind('app', const ClassType<Server>()).get();
    expect(server.host, 'example.org');
    expect(server.port, 8443);
  });

  test('a class described for writing only is bound without reading it', () {
    final server = binder({
      IntrospectionPart.write,
    }).bind('app', const ClassType<Server>()).get();
    expect(server.host, 'example.org');
    expect(server.port, 8443);
  });

  test('a class described without its constructor and setters fails', () {
    expect(
      () => binder({
        IntrospectionPart.read,
      }).bind('app', const ClassType<Server>()),
      throwsA(
        isA<IntrospectionPartError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Server is described without its constructor and setters'),
            contains('it is bound from configuration'),
            contains('@Introspected()'),
          ),
        ),
      ),
    );
  });
}
