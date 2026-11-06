import 'package:spring_boot_actuator/src/health/contributor.dart';
import 'package:spring_boot_actuator/src/health/disk_space_stub.dart'
    if (dart.library.io) 'package:spring_boot_actuator/src/health/disk_space_io.dart'
    as platform;
import 'package:spring_boot_actuator/src/health/health.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

const _log = SpringLog(
  'spring.boot.actuate.system.DiskSpaceHealthIndicator',
);

/// The space of the file system that holds a path.
///
/// Spring Boot reads it from `java.io.File`; here a [DiskSpaceReader]
/// measures it.
final class DiskSpace {
  /// The space of [path]: [total] and [free] bytes, and whether it
  /// [exists].
  const DiskSpace({
    required this.path,
    required this.total,
    required this.free,
    required this.exists,
  });

  /// The path, absolute.
  final String path;

  /// The size of the file system, in bytes.
  final int total;

  /// The bytes the application can still write.
  final int free;

  /// Whether the path exists.
  final bool exists;
}

/// Measures the [DiskSpace] of a path.
///
/// The default one asks the operating system (`df` on Linux and macOS,
/// .NET's `DriveInfo` through PowerShell on Windows); where there is no
/// file system to ask (the web) it returns `null`. Tests pass their own.
typedef DiskSpaceReader = Future<DiskSpace?> Function(String path);

/// `UP` while the file system of [path] has at least [threshold] bytes
/// free, `DOWN` below: the report's `diskSpace`, with the sizes as details.
///
/// ```properties
/// management.health.diskspace.path=/var/data
/// management.health.diskspace.threshold=1GB
/// ```
///
/// ```json
/// {"status": "UP", "details": {"total": 499963174912,
///   "free": 91300605952, "threshold": 10485760,
///   "path": "/srv/app/.", "exists": true}}
/// ```
///
/// When the space cannot be measured the status is `UNKNOWN`, with the
/// error as detail. Spring Boot (Java): `DiskSpaceHealthIndicator`.
class DiskSpaceHealthIndicator extends AbstractHealthIndicator {
  /// The indicator of [path] (the working directory by default) with
  /// [threshold] (10 MB by default), measured by [reader].
  DiskSpaceHealthIndicator({
    this.path = '.',
    DataSize? threshold,
    DiskSpaceReader? reader,
  }) : threshold = threshold ?? DataSize.ofMegabytes(10),
       reader = reader ?? platform.readDiskSpace,
       super('DiskSpace health check failed');

  /// The path whose file system is checked.
  final String path;

  /// The least free space that is `UP`.
  final DataSize threshold;

  /// Measures the space.
  final DiskSpaceReader reader;

  @override
  Future<void> doHealthCheck(HealthBuilder builder) async {
    final DiskSpace? space;
    try {
      space = await reader(path);
    } on Object catch (error) {
      builder.unknown().withException(error);
      return;
    }
    if (space == null) {
      builder.unknown().withDetail(
        'error',
        'The disk space cannot be measured here',
      );
      return;
    }
    final limit = threshold.toBytes();
    if (space.free >= limit) {
      builder.up();
    } else {
      _log.warning(
        'Free disk space at path ${space.path} below threshold. Available: '
        '${space.free} bytes (threshold: $threshold)',
      );
      builder.down();
    }
    builder
        .withDetail('total', space.total)
        .withDetail('free', space.free)
        .withDetail('threshold', limit)
        .withDetail('path', space.path)
        .withDetail('exists', space.exists);
  }
}
