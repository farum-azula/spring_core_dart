// The settings of the bench, `bench.*`: tool/load.dart passes them on the
// command line (`--bench.directory=...`, `--bench.files.huge-size=1GB`).
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// The `bench.*` properties.
@ConfigurationProperties('bench')
class BenchProperties {
  /// Where the files to download are generated and the uploads are
  /// written; the SQLite database is there too
  /// (`spring.datasource.url`). Created at startup.
  String directory = 'build/load_bench';

  /// The files to download (`files.*`).
  BenchFilesProperties files = BenchFilesProperties();

  /// The uploads (`upload.*`).
  BenchUploadProperties upload = BenchUploadProperties();

  /// The JSON scenario (`json.*`).
  BenchJsonProperties json = BenchJsonProperties();

  /// The bearer token of the secure scenario (`security.*`).
  BenchSecurityProperties security = BenchSecurityProperties();
}

/// The `bench.files.*` properties: the size of each file of
/// `GET /files/{name}`.
class BenchFilesProperties {
  /// `small.bin`: pseudo-random bytes.
  DataSize smallSize = DataSize.ofKilobytes(4);

  /// `medium.bin`: pseudo-random bytes.
  DataSize mediumSize = DataSize.ofMegabytes(10);

  /// `huge.bin`: a sparse file (zeros that take no room on disk).
  DataSize hugeSize = DataSize.ofMegabytes(512);
}

/// The `bench.upload.*` properties.
class BenchUploadProperties {
  /// The largest body of `PUT /upload/raw`, instead of
  /// `server.max-http-request-body-size`; `-1` for no limit. The multipart
  /// uploads have `spring.web.multipart.max-file-size` and
  /// `max-request-size`.
  DataSize maxSize = DataSize.ofGigabytes(2);
}

/// The `bench.json.*` properties.
class BenchJsonProperties {
  /// How many objects `GET /json` answers.
  int items = 50;
}

/// The `bench.security.*` properties.
class BenchSecurityProperties {
  /// The HMAC key (HS256, at least 32 bytes) that signs and checks the
  /// bearer token of `GET /secure/text`. The same on every isolate, so a
  /// token one of them issued is good for all.
  String jwtSecret = 'load-bench-secret-of-at-least-32-bytes';

  /// How long the token `GET /bench/info` hands out is valid.
  Duration tokenLifetime = const Duration(hours: 24);
}
