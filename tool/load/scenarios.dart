// The scenarios of tool/load.dart: one endpoint of the bench server
// (tool/load_bench) each, and how oha asks for it.

/// How a scenario is loaded.
enum ScenarioKind {
  /// Steps of a request rate (requests a second): small requests, where
  /// the question is how many a second the server answers in time.
  rate,

  /// Steps of concurrent transfers, each as fast as it goes: large bodies,
  /// where a rate means nothing and the question is the bytes a second.
  transfer,
}

/// One scenario: a request and what a good answer to it is.
final class Scenario {
  /// A scenario called [name] that sends [method] [path].
  const Scenario(
    this.name,
    this.title, {
    required this.path,
    this.kind = ScenarioKind.rate,
    this.method = 'GET',
    this.expected = const {200},
    this.headers = const {},
    this.contentType,
    this.bodyFile,
    this.bodyLinesFile,
    this.formFile,
    this.randomPath = false,
    this.uploadBytes,
    this.transfersData = false,
  });

  /// The name `--scenarios` takes (`json-post`).
  final String name;

  /// What it measures, for the report.
  final String title;

  /// Rate steps or transfer steps.
  final ScenarioKind kind;

  /// The HTTP method.
  final String method;

  /// The path on the bench server; a regular expression oha fills at
  /// random for each request when [randomPath].
  final String path;

  /// See [path].
  final bool randomPath;

  /// The status codes of a good answer; any other counts as an error.
  final Set<int> expected;

  /// Request headers.
  final Map<String, String> headers;

  /// The `Content-Type` of the body.
  final String? contentType;

  /// A file sent as the body.
  final String? bodyFile;

  /// A file whose lines are bodies; oha picks one at random for each
  /// request.
  final String? bodyLinesFile;

  /// A file sent as the part `file` of a `multipart/form-data` body.
  final String? formFile;

  /// The bytes of the body each request uploads, for the MB/s of uploads
  /// (oha counts only what it downloads).
  final int? uploadBytes;

  /// Whether the report shows MB/s: the downloads and the uploads.
  final bool transfersData;

  /// What the report says the request is (`GET /text`).
  String get request => '$method $path';
}

/// The bodies of `json-post`, one a line: one in ten breaks the
/// validation (a blank name, a negative price) and is answered with 400.
const jsonPostBodies = [
  '{"name":"Lamp","price":19.5,"quantity":3,"tags":["home","light"]}',
  '{"name":"Chair","description":"For an office","price":89,"quantity":1}',
  '{"name":"Pen","price":1.2,"quantity":100,"tags":["office","paper"]}',
  '{"name":"Notebook","description":"80 pages","price":3.4,"quantity":40}',
  '{"name":"Monitor","price":249.99,"quantity":2,"tags":["screen"]}',
  '{"name":"Cable","price":7,"quantity":15,"tags":["usb"]}',
  '{"name":"Keyboard","description":"Mechanical","price":59.9,"quantity":4}',
  '{"name":"Mouse","price":24.5,"quantity":0,"tags":["office"]}',
  '{"name":"Desk","description":"160 cm","price":310,"quantity":1}',
  '{"name":"","price":-1,"quantity":2}',
];

/// The body of `db-write`.
const dbWriteBody = '{"name":"load item","price":4.2,"quantity":7}';

/// The 64 KiB of `download-range`: the second mebibyte of the huge file.
const rangeHeader = 'bytes=1048576-1114111';

/// Every scenario, in the order of the report.
///
/// [files] is where the bench server generated `small.bin`, `medium.bin`
/// and `huge.bin` (its `bench.directory`): the uploads send them back.
/// [sizes] is the size of each, as `GET /bench/info` reports them.
/// [token] is the bearer token it hands out for `/secure/**`.
/// [jsonBodies] and [dbBody] are files holding [jsonPostBodies] (one a
/// line) and [dbWriteBody].
List<Scenario> scenarios({
  required String files,
  required Map<String, int> sizes,
  required String token,
  required String jsonBodies,
  required String dbBody,
}) => [
  const Scenario('text', 'Plain text', path: '/text'),
  const Scenario(
    'json',
    'JSON: a list of 50 objects written by the ObjectMapper',
    path: '/json',
  ),
  Scenario(
    'json-post',
    'JSON POST, validated (one body in ten is invalid: 400)',
    method: 'POST',
    path: '/json',
    contentType: 'application/json',
    bodyLinesFile: jsonBodies,
    expected: const {201, 400},
  ),
  Scenario(
    'secure',
    'Authenticated: a bearer token through the security filter chain',
    path: '/secure/text',
    headers: {'Authorization': 'Bearer $token'},
  ),
  const Scenario(
    'db-read',
    'Database read: a row by its key (spring_boot_starter_data, SQLite)',
    path: '/db/items/[1-9][0-9]{0,2}',
    randomPath: true,
  ),
  Scenario(
    'db-write',
    'Database write: an insert (spring_boot_starter_data, SQLite)',
    method: 'POST',
    path: '/db/items',
    contentType: 'application/json',
    bodyFile: dbBody,
    expected: const {201},
  ),
  const Scenario(
    'static',
    'Static file: a small text file from the static resource handler',
    path: '/static/hello.txt',
  ),
  const Scenario(
    'download-small',
    'Download, small file',
    path: '/files/small',
    transfersData: true,
  ),
  const Scenario(
    'download-range',
    'Download, a 64 KiB range of the huge file (206)',
    path: '/files/huge',
    headers: {'Range': rangeHeader},
    expected: {206},
    transfersData: true,
  ),
  const Scenario(
    'download-medium',
    'Download, medium file',
    kind: ScenarioKind.transfer,
    path: '/files/medium',
    transfersData: true,
  ),
  const Scenario(
    'download-huge',
    'Download, huge file',
    kind: ScenarioKind.transfer,
    path: '/files/huge',
    transfersData: true,
  ),
  for (final (size, kind) in [
    ('small', ScenarioKind.rate),
    ('medium', ScenarioKind.transfer),
    ('huge', ScenarioKind.transfer),
  ]) ...[
    Scenario(
      'upload-$size-multipart',
      'Upload, $size file as multipart/form-data',
      kind: kind,
      method: 'POST',
      path: '/upload/multipart',
      formFile: '$files/$size.bin',
      uploadBytes: sizes[size],
      transfersData: true,
    ),
    Scenario(
      'upload-$size-raw',
      'Upload, $size file as a raw body streamed to disk',
      kind: kind,
      method: 'PUT',
      path: '/upload/raw',
      contentType: 'application/octet-stream',
      bodyFile: '$files/$size.bin',
      uploadBytes: sizes[size],
      transfersData: true,
    ),
  ],
];

/// The names of [scenarios] (the sweeps), for `--help` and to check
/// `--scenarios` before the server is built.
const scenarioNames = [
  'text',
  'json',
  'json-post',
  'secure',
  'db-read',
  'db-write',
  'static',
  'download-small',
  'download-range',
  'download-medium',
  'download-huge',
  'upload-small-multipart',
  'upload-small-raw',
  'upload-medium-multipart',
  'upload-medium-raw',
  'upload-huge-multipart',
  'upload-huge-raw',
];

/// The scenarios that are not a sweep of one request: each starts a
/// server of its own, with the settings it is about, and has its own kind
/// of report. Name to title, in the order of the report.
const specialScenarios = {
  'cpu':
      "CPU-bound work in the request's isolate and through the "
      'IsolateTaskExecutor, with a light probe beside it',
  'scale-manual':
      'Scaling by hand under load: one isolate, more, and one again',
  'scale-auto': 'Automatic scaling over a ramp of load, up and down',
  'overload-concurrent':
      'More requests at a time than server.max-concurrent-requests',
  'overload-connections': 'More connections than server.max-connections',
  'slow-headers':
      'Connections that send their headers a line at a time (slowloris)',
  'slow-body': 'Request bodies that stall or trickle',
  'big-body': 'A body over server.max-http-request-body-size',
};

/// The light request sent beside a special scenario, to see whether the
/// server still answers others meanwhile.
const probeScenario = Scenario('probe', 'Probe', path: '/text');

/// The request the scaling scenarios load: JSON written on every
/// request, so an isolate is full at a rate oha reaches easily.
const timelineScenario = Scenario('json', 'JSON', path: '/json');

/// The groups `--scenarios` takes besides names.
const Map<String, List<String>> scenarioGroups = {
  'api': [
    'text',
    'json',
    'json-post',
    'secure',
    'db-read',
    'db-write',
    'static',
  ],
  'files': [
    'download-small',
    'download-range',
    'download-medium',
    'download-huge',
    'upload-small-multipart',
    'upload-small-raw',
    'upload-medium-multipart',
    'upload-medium-raw',
    'upload-huge-multipart',
    'upload-huge-raw',
  ],
  'sweep': scenarioNames,
  'scaling': ['scale-manual', 'scale-auto'],
  'overload': [
    'overload-concurrent',
    'overload-connections',
    'slow-headers',
    'slow-body',
    'big-body',
  ],
  'all': [
    ...scenarioNames,
    'cpu',
    'scale-manual',
    'scale-auto',
    'overload-concurrent',
    'overload-connections',
    'slow-headers',
    'slow-body',
    'big-body',
  ],
};
