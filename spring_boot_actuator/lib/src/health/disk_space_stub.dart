import 'package:spring_boot_actuator/src/health/disk_space.dart';

/// No file system to measure (the web).
Future<DiskSpace?> readDiskSpace(String path) async => null;
