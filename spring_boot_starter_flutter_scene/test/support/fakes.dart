import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
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
