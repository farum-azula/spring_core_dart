import 'dart:convert';
import 'dart:typed_data';

/// A file to put into a tar archive: the path inside the container
/// (absolute or relative to the extraction directory), its [bytes] and its
/// permission bits.
final class TarFile {
  /// A regular file at [path] with [bytes]; [mode] is the Unix permission
  /// (`0644` by default).
  const TarFile(this.path, this.bytes, {this.mode = 420});

  /// The path inside the container.
  final String path;

  /// The content.
  final List<int> bytes;

  /// The permission bits, as the number (`0x1A4` is `0644`).
  final int mode;
}

/// Writes [files] as a ustar archive, the format Docker's `PUT
/// /containers/{id}/archive` unpacks.
///
/// Only regular files, owned by root, with the time [modified]; the
/// directories above a file are created by the daemon when it unpacks. A
/// path longer than ustar's 100 characters is split into prefix and name
/// at a `/`; one that cannot be split throws an [ArgumentError].
///
/// Testcontainers (Java): `TarArchiveOutputStream` of commons-compress, in
/// `copyFileToContainer`.
Uint8List tarArchive(List<TarFile> files, {DateTime? modified}) {
  final time = (modified ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  final out = BytesBuilder(copy: false);
  for (final file in files) {
    final (prefix, name) = _split(file.path.replaceFirst(RegExp('^/+'), ''));
    final header = Uint8List(512);
    void put(int offset, int length, String text) {
      final bytes = utf8.encode(text);
      header.setRange(offset, offset + bytes.length.clamp(0, length), bytes);
    }

    String octal(int value, int digits) =>
        '${value.toRadixString(8).padLeft(digits - 1, '0')}\u0000';

    put(0, 100, name);
    put(100, 8, octal(file.mode & 0xFFF, 8));
    put(108, 8, octal(0, 8));
    put(116, 8, octal(0, 8));
    put(124, 12, octal(file.bytes.length, 12));
    put(136, 12, octal(time, 12));
    put(148, 8, '        '); // the checksum counts these as spaces
    put(156, 1, '0');
    put(257, 6, 'ustar\u0000');
    put(263, 2, '00');
    put(345, 155, prefix);
    final sum = header.fold<int>(0, (a, b) => a + b);
    put(148, 8, '${sum.toRadixString(8).padLeft(6, '0')}\u0000 ');
    out
      ..add(header)
      ..add(file.bytes);
    final padding = (512 - file.bytes.length % 512) % 512;
    if (padding > 0) {
      out.add(Uint8List(padding));
    }
  }
  out.add(Uint8List(1024)); // the end of the archive
  return out.takeBytes();
}

// ustar keeps 100 characters of name and 155 of prefix.
(String, String) _split(String path) {
  if (utf8.encode(path).length <= 100) {
    return ('', path);
  }
  for (var i = path.length - 1; i > 0; i--) {
    if (path[i] != '/') {
      continue;
    }
    final prefix = path.substring(0, i);
    final name = path.substring(i + 1);
    if (utf8.encode(prefix).length <= 155 && utf8.encode(name).length <= 100) {
      return (prefix, name);
    }
  }
  throw ArgumentError.value(
    path,
    'path',
    'is too long for a tar archive (100 characters for the file name, 155 '
        'for its directory)',
  );
}
