import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat_ast.dart' show FmatShadingModel;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart' show Fake;
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

/// An engine without a GPU: starts, or fails when told to.
final class FakeBackend implements SceneBackend {
  FakeBackend({this.fails = false});

  final bool fails;
  int starts = 0;

  @override
  String get name => 'fake';

  @override
  Future<void> start() async {
    starts++;
    if (fails) {
      throw StateError('no GPU here');
    }
  }
}

/// Makes a bare node for any file.
final class FakeImporter implements SceneModelImporter {
  final List<String> imported = [];

  @override
  Future<Node> import(Uint8List bytes, {required String name}) async {
    imported.add(name);
    return Node(name: name)..add(Node(name: '$name-part'));
  }
}

/// Files by their location; a missing one fails to read.
final class FakeResources implements ResourceLoader {
  FakeResources(this.files);

  final Map<String, List<int>> files;

  @override
  Resource getResource(String location) => switch (files[location]) {
    final bytes? => ByteArrayResource(Uint8List.fromList(bytes)),
    null => ByteArrayResource(Uint8List(0), description: location).missing,
  };
}

extension on ByteArrayResource {
  Resource get missing => _Missing(description);
}

final class _Missing extends AbstractResource {
  _Missing(this.description);

  @override
  final String description;

  @override
  bool exists() => false;

  @override
  Future<Uint8List> readAsBytes() =>
      throw StateError('$description does not exist');

  @override
  Uint8List readAsBytesSync() =>
      throw StateError('$description does not exist');
}

/// Keeps what is published.
final class RecordingEvents implements ApplicationEventPublisher {
  final List<Object> events = [];

  List<String> get names => [
    for (final event in events)
      if (event is ApplicationEvent) event.eventName,
  ];

  @override
  void publishEvent<T extends Object>(T event) => events.add(event);
}

/// Answers every request with [status] and [body], and keeps the requests.
final class FakeTransport implements HttpTransport {
  FakeTransport({this.status = 200, this.body = const [7, 7]});

  final int status;
  final List<int> body;
  final List<HttpRequest> requests = [];
  bool closed = false;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    requests.add(request);
    return HttpResponse(status, body: body);
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}

/// A material without a GPU: its parameters by name, how it is lit.
final class FakeMaterial extends Fake implements PreprocessedMaterial {
  FakeMaterial(this.id, {this.names = const ['tint', 'time']});

  final int id;
  final List<String> names;

  @override
  FmatShadingModel get shadingModel => FmatShadingModel.unlit;

  @override
  bool isOpaque() => false;

  @override
  MaterialParameters get parameters => FakeParameters(names);
}

/// The names of a material's parameters.
final class FakeParameters extends Fake implements MaterialParameters {
  FakeParameters(this.names);

  final List<String> names;

  @override
  Iterable<String> get parameterNames => names;
}

/// Makes a new material for every load and counts them; a source in
/// [failing] fails.
final class FakeMaterialLoader implements SceneMaterialLoader {
  FakeMaterialLoader({this.failing = const {}});

  final Set<String> failing;
  final List<String> loaded = [];

  @override
  Future<PreprocessedMaterial> load(String source) async {
    if (failing.contains(source)) {
      throw StateError('$source was not compiled');
    }
    loaded.add(source);
    return FakeMaterial(loaded.length);
  }
}
