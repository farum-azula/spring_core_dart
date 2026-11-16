import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/local_file_store.dart';

/// The file of [path] in [place] on the disk, `null` when [files] keeps
/// none (a store of the app's own) or it is not there.
Future<String?> filePathOf(
  FileStore files,
  FilePlace place,
  String path,
) async {
  if (files is! LocalFileStore || !await files.exists(place, path)) {
    return null;
  }
  return files.pathOf(place, path);
}
