import 'dart:io';

import 'package:spring_boot_actuator/src/health/disk_space.dart';

/// The space of [path]'s file system, from `df -Pk` (POSIX output, in
/// kilobytes) or, on Windows, .NET's `DriveInfo`. A path that does not
/// exist has no space, as `java.io.File` reports it.
Future<DiskSpace?> readDiskSpace(String path) async {
  final directory = Directory(path);
  final absolute = directory.absolute.path;
  // Synchronous on purpose: one stat, cheaper than a round trip.
  final exists = directory.existsSync() || File(path).existsSync();
  if (!exists) {
    return DiskSpace(path: absolute, total: 0, free: 0, exists: false);
  }
  if (Platform.isWindows) {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      _driveInfoScript,
      absolute,
    ]);
    if (result.exitCode != 0) {
      throw ProcessException('powershell', const [], '${result.stderr}');
    }
    final parts = '${result.stdout}'.trim().split(RegExp(r'\s+'));
    return DiskSpace(
      path: absolute,
      total: int.parse(parts[0]),
      free: int.parse(parts[1]),
      exists: true,
    );
  }
  if (Platform.isIOS) {
    return null; // no df, and no process to start
  }
  final result = await Process.run('df', ['-Pk', absolute]);
  if (result.exitCode != 0) {
    throw ProcessException('df', ['-Pk', absolute], '${result.stderr}');
  }
  // Filesystem 1024-blocks Used Available Capacity Mounted on; the names
  // of the file system and the mount point may hold spaces, so the fields
  // are counted from the capacity (`42%`).
  final fields = '${result.stdout}'
      .trim()
      .split('\n')
      .last
      .trim()
      .split(
        RegExp(r'\s+'),
      );
  final capacity = fields.lastIndexWhere(RegExp(r'^\d+%$').hasMatch);
  if (capacity < 3) {
    throw FormatException('Unexpected df output', '${result.stdout}');
  }
  final available = int.parse(fields[capacity - 1]);
  final blocks = int.parse(fields[capacity - 3]);
  return DiskSpace(
    path: absolute,
    total: blocks * 1024,
    free: available * 1024,
    exists: true,
  );
}

// Prints the total and the free bytes of the drive of the path argument.
const _driveInfoScript =
    r'$d = New-Object System.IO.DriveInfo((Resolve-Path $args[0]).Path); '
    r'"$($d.TotalSize) $($d.AvailableFreeSpace)"';
