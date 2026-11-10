// The files of the download scenarios and the directory of the uploads,
// made when the server starts (never committed: bench.directory is under
// build/ or wherever tool/load.dart points it).
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:load_bench/src/bench_properties.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Creates `bench.directory` before any bean exists: the SQLite database
/// of `spring.datasource.url` is opened in it as soon as the data source
/// starts.
@Component()
class BenchDirectory implements BeanFactoryPostProcessor {
  BenchDirectory(@Value(r'${bench.directory}') this.path);

  final String path;

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      Directory('$path/uploads').createSync(recursive: true);
}

/// The files `GET /files/{name}` serves, and where uploads are written.
@Component()
class BenchFiles {
  BenchFiles(this._properties);

  final BenchProperties _properties;

  // Unique among the server's isolates and processes sharing a directory.
  final String _prefix = Random.secure().nextInt(1 << 32).toRadixString(16);
  int _uploads = 0;

  /// Whether every file exists with its size: `GET /bench/info` says so,
  /// and the load tool waits for it.
  bool ready = false;

  /// The name and size of each file.
  Map<String, int> get sizes => {
    'small': _properties.files.smallSize.toBytes(),
    'medium': _properties.files.mediumSize.toBytes(),
    'huge': _properties.files.hugeSize.toBytes(),
  };

  /// The path of the file called [name] (`small`, `medium`, `huge`).
  String path(String name) => '${_properties.directory}/$name.bin';

  /// A new path for an upload, deleted by the handler once it is counted.
  String newUpload() =>
      '${_properties.directory}/uploads/$_prefix-${_uploads++}.bin';

  /// Writes the files that are missing or have another size. A file is
  /// written under a temporary name and renamed, so several isolates (or
  /// servers) starting on one directory never read half a file.
  Future<void> prepare() async {
    await _generate('small', sparse: false);
    await _generate('medium', sparse: false);
    await _generate('huge', sparse: true);
    ready = true;
  }

  Future<void> _generate(String name, {required bool sparse}) async {
    final size = sizes[name]!;
    final file = File(path(name));
    if (file.existsSync() && file.lengthSync() == size) {
      return;
    }
    final temporary = File('${file.path}.$_prefix.tmp');
    final out = await temporary.open(mode: FileMode.write);
    try {
      if (sparse) {
        // No block is written: the file takes no room, reads give zeros.
        await out.truncate(size);
      } else {
        // The same bytes on every machine: a fixed seed.
        final random = Random(size);
        final block = Uint8List(64 * 1024);
        for (var written = 0; written < size; written += block.length) {
          for (var i = 0; i < block.length; i++) {
            block[i] = random.nextInt(256);
          }
          await out.writeFrom(block, 0, min(block.length, size - written));
        }
      }
    } finally {
      await out.close();
    }
    await temporary.rename(file.path);
  }
}

/// Makes the files once the context is ready; the server already
/// listens, so `GET /bench/info` answers `"ready": false` until then.
@Component()
class BenchFilesRunner implements ApplicationRunner {
  BenchFilesRunner(this._files);

  final BenchFiles _files;

  @override
  Future<void> run(ApplicationArguments args) => _files.prepare();
}
