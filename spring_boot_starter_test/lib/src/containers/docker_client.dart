import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_boot_starter_test/src/containers/docker_endpoint.dart';
import 'package:spring_boot_starter_test/src/containers/docker_exception.dart';
import 'package:spring_boot_starter_test/src/containers/tar_archive.dart';

/// The output channel a [DockerLogLine] was written to.
enum DockerStream {
  /// The container's standard output.
  stdout,

  /// The container's standard error.
  stderr,
}

/// One line a container printed.
final class DockerLogLine {
  /// A line of [text] written to [stream], without its line break.
  const DockerLogLine(this.stream, this.text);

  /// Where the container wrote it.
  final DockerStream stream;

  /// The line, without the line break.
  final String text;

  @override
  String toString() => text;
}

/// What a container is made of, as the daemon's `POST /containers/create`
/// takes it.
///
/// `GenericContainer` fills it from its fluent methods; use it directly
/// with [DockerClient.createContainer] for what they do not cover.
///
/// Testcontainers (Java): the `CreateContainerCmd` of docker-java.
final class DockerContainerConfig {
  /// A container of [image]; every other setting is optional.
  const DockerContainerConfig({
    required this.image,
    this.environment = const {},
    this.command,
    this.entrypoint,
    this.exposedPorts = const [],
    this.labels = const {},
    this.binds = const [],
    this.autoRemove = false,
    this.publishIp = '',
    this.healthCheck,
  });

  /// The image, such as `postgres:17`.
  final String image;

  /// Environment variables, by name.
  final Map<String, String> environment;

  /// The command (`CMD`), or `null` for the image's own.
  final List<String>? command;

  /// The entry point, or `null` for the image's own.
  final List<String>? entrypoint;

  /// The container ports to publish, each on a random free host port (read
  /// them back with [DockerContainerState.mappedPort]).
  final List<int> exposedPorts;

  /// Labels, by name.
  final Map<String, String> labels;

  /// Bind mounts, as `/host/path:/container/path[:ro]`.
  final List<String> binds;

  /// Whether the daemon removes the container when it exits.
  final bool autoRemove;

  /// The host interface the ports are published on; empty is all of them.
  final String publishIp;

  /// A health check of the container's own, replacing the image's: the
  /// command in exec form (`['CMD-SHELL', 'pg_isready']`) and how often it
  /// runs, how long it may take and how many failures make the container
  /// `unhealthy`.
  final ({List<String> test, Duration interval, Duration timeout, int retries})?
  healthCheck;

  /// The JSON body of the create request.
  Map<String, Object?> toJson() => {
    'Image': image,
    if (environment.isNotEmpty)
      'Env': [for (final e in environment.entries) '${e.key}=${e.value}'],
    'Cmd': ?command,
    'Entrypoint': ?entrypoint,
    if (exposedPorts.isNotEmpty)
      'ExposedPorts': {
        for (final port in exposedPorts) '$port/tcp': <String, Object?>{},
      },
    if (labels.isNotEmpty) 'Labels': labels,
    if (healthCheck case final check?)
      'Healthcheck': {
        'Test': check.test,
        'Interval': check.interval.inMicroseconds * 1000,
        'Timeout': check.timeout.inMicroseconds * 1000,
        'Retries': check.retries,
      },
    'HostConfig': {
      if (exposedPorts.isNotEmpty)
        'PortBindings': {
          for (final port in exposedPorts)
            '$port/tcp': [
              {'HostIp': publishIp, 'HostPort': ''},
            ],
        },
      if (binds.isNotEmpty) 'Binds': binds,
      if (autoRemove) 'AutoRemove': true,
    },
  };
}

/// What `docker inspect` says about a container, in the parts a test
/// needs.
final class DockerContainerState {
  /// A state; the daemon's answer is parsed by [DockerContainerState.fromJson].
  const DockerContainerState({
    required this.id,
    required this.running,
    required this.status,
    required this.exitCode,
    required this.health,
    required this.ports,
    required this.labels,
    this.error = '',
  });

  /// Reads the answer of `GET /containers/{id}/json`.
  factory DockerContainerState.fromJson(Map<String, Object?> json) {
    final state = (json['State'] as Map<String, Object?>?) ?? const {};
    final health = state['Health'] as Map<String, Object?>?;
    final network = json['NetworkSettings'] as Map<String, Object?>?;
    final published = (network?['Ports'] as Map<String, Object?>?) ?? const {};
    final config = json['Config'] as Map<String, Object?>?;
    final ports = <String, int>{};
    for (final MapEntry(:key, :value) in published.entries) {
      final bindings = value as List<Object?>?;
      for (final binding in bindings ?? const <Object?>[]) {
        final port = int.tryParse(
          '${(binding! as Map<String, Object?>)['HostPort']}',
        );
        if (port != null) {
          ports.putIfAbsent(key, () => port);
        }
      }
    }
    return DockerContainerState(
      id: '${json['Id']}',
      running: state['Running'] == true,
      status: '${state['Status']}',
      exitCode: (state['ExitCode'] as num?)?.toInt() ?? 0,
      health: health == null ? null : '${health['Status']}',
      ports: ports,
      labels: {
        for (final e
            in ((config?['Labels'] as Map<String, Object?>?) ?? const {})
                .entries)
          e.key: '${e.value}',
      },
      error: '${state['Error'] ?? ''}',
    );
  }

  /// The container's id.
  final String id;

  /// Whether the container's process is running.
  final bool running;

  /// `created`, `running`, `paused`, `restarting`, `exited`, `dead`...
  final String status;

  /// The exit code of the container's process once it exited.
  final int exitCode;

  /// The health check's status (`starting`, `healthy`, `unhealthy`), or
  /// `null` when the image defines no health check.
  final String? health;

  /// The published ports: `5432/tcp` to its port on the host.
  final Map<String, int> ports;

  /// The container's labels.
  final Map<String, String> labels;

  /// The error the daemon reports, empty when there is none.
  final String error;

  /// The host port the TCP [port] of the container is published on, or
  /// `null` when it is not published.
  int? mappedPort(int port) => ports['$port/tcp'];
}

/// A container of the list `GET /containers/json` returns.
final class DockerContainerSummary {
  /// A listed container.
  const DockerContainerSummary({
    required this.id,
    required this.image,
    required this.state,
    required this.labels,
  });

  /// The container's id.
  final String id;

  /// The image it was created from.
  final String image;

  /// `running`, `exited`, `created`...
  final String state;

  /// The container's labels.
  final Map<String, String> labels;
}

/// The outcome of a command run in a container with [DockerClient.exec].
final class DockerExecResult {
  /// A finished command.
  const DockerExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The command's exit code.
  final int exitCode;

  /// What it wrote to standard output.
  final String stdout;

  /// What it wrote to standard error.
  final String stderr;
}

/// A client of the Docker Engine API, over the daemon's Unix socket (or
/// `tcp://`) on `dart:io`: no package, no `docker` command.
///
/// It covers what a test needs: [ping], [version], [imageExists],
/// [pullImage], [createContainer], [putFiles], [startContainer],
/// [containerLogs], [inspectContainer], [exec], [listContainers],
/// [stopContainer] and [removeContainer]. A call the daemon rejects throws
/// a [DockerException] with the daemon's message; a daemon that cannot be
/// reached throws a [DockerUnavailableException]. The paths carry no API
/// version, so the daemon answers in its current one.
///
/// Tests use `GenericContainer` and the modules built on it; use this
/// class for what they do not cover.
///
/// ```dart
/// final docker = await DockerClient.connect();
/// await docker.pullImage('redis:7.4-alpine');
/// final id = await docker.createContainer(
///   const DockerContainerConfig(image: 'redis:7.4-alpine',
///       exposedPorts: [6379]),
/// );
/// await docker.startContainer(id);
/// final state = await docker.inspectContainer(id);
/// print(state.mappedPort(6379)); // the random host port
/// await docker.removeContainer(id);
/// docker.close();
/// ```
///
/// Testcontainers (Java): `DockerClientFactory.lazyClient()`, a docker-java
/// `DockerClient`.
final class DockerClient {
  /// A client of the daemon at [endpoint]; nothing connects until the first
  /// call.
  DockerClient(this.endpoint) : _http = HttpClient() {
    _http
      ..idleTimeout = const Duration(seconds: 2)
      ..connectionTimeout = const Duration(seconds: 10)
      ..findProxy = ((_) => 'DIRECT');
    if (endpoint.socketPath case final path?) {
      final address = InternetAddress(path, type: InternetAddressType.unix);
      _http.connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect(address, 0);
    }
  }

  /// Finds the daemon ([DockerEndpoint.resolve]) and checks it answers.
  ///
  /// Throws a [DockerUnavailableException] with the reason when it does
  /// not.
  static Future<DockerClient> connect({
    Map<String, String>? environment,
  }) async {
    final endpoint = DockerEndpoint.resolve(environment: environment);
    if (endpoint == null) {
      throw DockerUnavailableException(
        DockerEndpoint.unavailableReason(environment: environment) ??
            'No Docker daemon found',
      );
    }
    final client = DockerClient(endpoint);
    try {
      await client.ping();
    } on Object {
      client.close();
      rethrow;
    }
    return client;
  }

  /// The daemon this client talks to.
  final DockerEndpoint endpoint;

  final HttpClient _http;

  /// Closes the connections to the daemon.
  void close() => _http.close(force: true);

  /// Checks that the daemon answers (`GET /_ping`).
  Future<void> ping() async {
    final response = await _send('GET', '/_ping');
    final body = (await utf8.decodeStream(response)).trim();
    if (body != 'OK') {
      throw DockerUnavailableException(
        'The daemon at $endpoint answered "$body" to a ping, not "OK"',
      );
    }
  }

  /// The daemon's version information (`GET /version`): `Version`,
  /// `ApiVersion`, `Os`, `Arch`...
  Future<Map<String, Object?>> version() =>
      _send('GET', '/version').then(_json);

  /// Splits an image reference into the name to pull and its tag: `latest`
  /// when none is given, none for a digest (`name@sha256:...`).
  static (String, String?) parseImage(String image) {
    if (image.contains('@')) {
      return (image, null);
    }
    final colon = image.lastIndexOf(':');
    if (colon > image.lastIndexOf('/')) {
      return (image.substring(0, colon), image.substring(colon + 1));
    }
    return (image, 'latest');
  }

  /// Whether [image] is in the daemon's local store.
  Future<bool> imageExists(String image) async {
    try {
      await _drain(await _send('GET', '/images/$image/json'));
      return true;
    } on DockerException catch (e) {
      if (e.statusCode == 404) {
        return false;
      }
      rethrow;
    }
  }

  /// Downloads [image] from its registry, waiting for the end of the pull;
  /// its progress is ignored.
  ///
  /// Throws a [DockerException] saying which image could not be pulled and
  /// why (a name or tag that does not exist, a registry that asks for a
  /// login). Registry credentials are not sent: private images must be
  /// pulled beforehand (`docker login`, `docker pull`).
  Future<void> pullImage(String image) async {
    final (name, tag) = parseImage(image);
    final HttpClientResponse response;
    try {
      response = await _send(
        'POST',
        '/images/create',
        query: {'fromImage': name, 'tag': ?tag},
      );
    } on DockerException catch (e) {
      throw DockerException(
        "Cannot pull the image '$image': ${e.message}",
        statusCode: e.statusCode,
      );
    }
    // The progress is a stream of JSON lines; a failure is one of them.
    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) {
        continue;
      }
      final Object? event;
      try {
        event = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (event is Map<String, Object?> && event['error'] != null) {
        throw DockerException(
          "Cannot pull the image '$image': ${event['error']}",
        );
      }
    }
  }

  /// Creates a container from [config] without starting it, and returns
  /// its id. With [name] it is called that; the daemon names it otherwise.
  Future<String> createContainer(
    DockerContainerConfig config, {
    String? name,
  }) async {
    final body = await _json(
      await _send(
        'POST',
        '/containers/create',
        query: {'name': ?name},
        json: config.toJson(),
      ),
    );
    return '${body['Id']}';
  }

  /// Copies [files] into the container [id] (created or running), the
  /// parent directories included: they are written as a tar archive and
  /// unpacked at the root.
  Future<void> putFiles(String id, List<TarFile> files) async {
    await _drain(
      await _send(
        'PUT',
        '/containers/$id/archive',
        query: {'path': '/'},
        body: tarArchive(files),
        contentType: 'application/x-tar',
      ),
    );
  }

  /// Starts the container [id].
  Future<void> startContainer(String id) async {
    await _drain(await _send('POST', '/containers/$id/start'));
  }

  /// Stops the container [id]: its process gets SIGTERM, and SIGKILL after
  /// [timeout] (the daemon's default, 10 seconds, when `null`). A container
  /// that does not exist is not an error.
  Future<void> stopContainer(String id, {Duration? timeout}) => _ignoreMissing(
    () async {
      await _drain(
        await _send(
          'POST',
          '/containers/$id/stop',
          query: {if (timeout != null) 't': '${timeout.inSeconds}'},
        ),
      );
    },
  );

  /// Removes the container [id]; [force] kills it first, [volumes] removes
  /// its anonymous volumes. A container that does not exist is not an
  /// error.
  Future<void> removeContainer(
    String id, {
    bool force = true,
    bool volumes = true,
  }) => _ignoreMissing(
    () async {
      await _drain(
        await _send(
          'DELETE',
          '/containers/$id',
          query: {'force': '$force', 'v': '$volumes'},
        ),
      );
    },
  );

  /// The state of the container [id]: whether it runs, its health, its
  /// published ports. Throws a [DockerException] (status 404) when it does
  /// not exist.
  Future<DockerContainerState> inspectContainer(String id) async =>
      DockerContainerState.fromJson(
        await _json(await _send('GET', '/containers/$id/json')),
      );

  /// What the container [id] prints, line by line, standard output and
  /// error together.
  ///
  /// Without [follow] the stream ends after what was printed so far (the
  /// last [tail] lines when given); with it, it goes on until the container
  /// stops or the subscription is cancelled. The multiplexed frames of the
  /// daemon are split back into lines, per channel.
  Stream<DockerLogLine> containerLogs(
    String id, {
    bool follow = false,
    int? tail,
  }) async* {
    final response = await _send(
      'GET',
      '/containers/$id/logs',
      query: {
        'stdout': '1',
        'stderr': '1',
        if (follow) 'follow': '1',
        if (tail != null) 'tail': '$tail',
      },
    );
    yield* _demultiplex(response);
  }

  /// Runs [command] in the running container [id] and waits for it:
  /// Testcontainers' `execInContainer`.
  Future<DockerExecResult> exec(String id, List<String> command) async {
    final created = await _json(
      await _send(
        'POST',
        '/containers/$id/exec',
        json: {
          'AttachStdout': true,
          'AttachStderr': true,
          'Cmd': command,
        },
      ),
    );
    final execId = '${created['Id']}';
    final out = <String>[];
    final err = <String>[];
    final response = await _send(
      'POST',
      '/exec/$execId/start',
      json: {'Detach': false, 'Tty': false},
    );
    await for (final line in _demultiplex(response)) {
      (line.stream == DockerStream.stdout ? out : err).add(line.text);
    }
    final info = await _json(await _send('GET', '/exec/$execId/json'));
    return DockerExecResult(
      exitCode: (info['ExitCode'] as num?)?.toInt() ?? -1,
      stdout: out.join('\n'),
      stderr: err.join('\n'),
    );
  }

  /// The containers with all of the [labels] (`name=value`, or just
  /// `name`); [all] includes the stopped ones.
  Future<List<DockerContainerSummary>> listContainers({
    List<String> labels = const [],
    bool all = false,
  }) async {
    final response = await _send(
      'GET',
      '/containers/json',
      query: {
        'all': '$all',
        if (labels.isNotEmpty) 'filters': jsonEncode({'label': labels}),
      },
    );
    final body = jsonDecode(await utf8.decodeStream(response));
    return [
      for (final item in (body as List<Object?>).cast<Map<String, Object?>>())
        DockerContainerSummary(
          id: '${item['Id']}',
          image: '${item['Image']}',
          state: '${item['State']}',
          labels: {
            for (final e
                in ((item['Labels'] as Map<String, Object?>?) ?? const {})
                    .entries)
              e.key: '${e.value}',
          },
        ),
    ];
  }

  Uri _uri(String path, Map<String, String>? query) => Uri(
    scheme: 'http',
    host: endpoint.isUnix ? 'localhost' : endpoint.host,
    port: endpoint.port ?? 80,
    path: path,
    queryParameters: query == null || query.isEmpty ? null : query,
  );

  // Sends a request and returns the response when the daemon accepts it;
  // otherwise throws its message.
  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? json,
    List<int>? body,
    String? contentType,
  }) async {
    final HttpClientResponse response;
    try {
      final request = await _http.openUrl(method, _uri(path, query));
      final bytes = json == null ? body : utf8.encode(jsonEncode(json));
      if (bytes != null) {
        request.headers.contentType = json == null
            ? ContentType.parse(contentType ?? 'application/octet-stream')
            : ContentType.json;
        request
          ..contentLength = bytes.length
          ..add(bytes);
      }
      response = await request.close();
    } on SocketException catch (e) {
      throw DockerUnavailableException(
        'Cannot connect to the Docker daemon at $endpoint: ${e.message}',
      );
    } on HttpException catch (e) {
      throw DockerUnavailableException(
        'The Docker daemon at $endpoint did not answer as HTTP: ${e.message}',
      );
    }
    if (response.statusCode >= 400) {
      final text = await utf8.decodeStream(response);
      throw DockerException(
        _daemonMessage(text) ?? 'HTTP ${response.statusCode} for $method $path',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  static String? _daemonMessage(String text) {
    try {
      if (jsonDecode(text) case {'message': final String message}) {
        return message;
      }
    } on FormatException {
      // Not JSON: use the text as it is.
    }
    return text.trim().isEmpty ? null : text.trim();
  }

  static Future<Map<String, Object?>> _json(HttpClientResponse response) async {
    final text = await utf8.decodeStream(response);
    return text.trim().isEmpty
        ? const {}
        : (jsonDecode(text) as Map<String, Object?>);
  }

  static Future<void> _drain(HttpClientResponse response) =>
      response.drain<void>();

  static Future<void> _ignoreMissing(Future<void> Function() call) async {
    try {
      await call();
    } on DockerException catch (e) {
      if (e.statusCode != 404) {
        rethrow;
      }
    }
  }

  // The daemon multiplexes stdout and stderr into frames of an 8-byte
  // header (channel, 3 zero bytes, the length as 4 big-endian bytes) and
  // the payload. Frames do not follow line breaks: lines are put together
  // per channel.
  static Stream<DockerLogLine> _demultiplex(Stream<List<int>> chunks) async* {
    var buffer = BytesBuilder(copy: false);
    var pending = Uint8List(0);
    final partial = {
      DockerStream.stdout: <int>[],
      DockerStream.stderr: <int>[],
    };
    Iterable<DockerLogLine> lines(DockerStream stream, List<int> bytes) sync* {
      final line = partial[stream]!..addAll(bytes);
      var start = 0;
      for (var i = 0; i < line.length; i++) {
        if (line[i] == 10) {
          var end = i;
          if (end > start && line[end - 1] == 13) {
            end--;
          }
          yield DockerLogLine(
            stream,
            utf8.decode(line.sublist(start, end), allowMalformed: true),
          );
          start = i + 1;
        }
      }
      partial[stream] = line.sublist(start);
    }

    await for (final chunk in chunks) {
      buffer.add(chunk);
      pending = buffer.takeBytes();
      var offset = 0;
      while (pending.length - offset >= 8) {
        final size = ByteData.sublistView(
          pending,
          offset + 4,
          offset + 8,
        ).getUint32(0);
        if (pending.length - offset - 8 < size) {
          break;
        }
        final channel = pending[offset];
        final payload = pending.sublist(offset + 8, offset + 8 + size);
        offset += 8 + size;
        yield* Stream.fromIterable(
          lines(
            channel == 2 ? DockerStream.stderr : DockerStream.stdout,
            payload,
          ),
        );
      }
      buffer = BytesBuilder(copy: false)..add(pending.sublist(offset));
    }
    for (final MapEntry(:key, :value) in partial.entries) {
      if (value.isNotEmpty) {
        yield DockerLogLine(key, utf8.decode(value, allowMalformed: true));
      }
    }
  }
}
