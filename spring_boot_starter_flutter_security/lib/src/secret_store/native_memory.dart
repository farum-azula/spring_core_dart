import 'dart:convert';
import 'dart:ffi';

/// C memory for one call to the OS, from the OS's own allocator
/// (`LocalAlloc` on Windows, `g_malloc0` on Linux): zeroed when
/// allocated, everything freed by [releaseAll].
///
/// The Windows and Linux secret stores use it instead of `package:ffi`,
/// which the starter does not depend on (only on this repository).
final class NativeArena implements Allocator {
  /// An arena over [allocateZeroed] and [release].
  NativeArena(this._allocateZeroed, this._release);

  final Pointer<Void> Function(int size) _allocateZeroed;
  final void Function(Pointer<Void> pointer) _release;
  final _allocated = <Pointer<Void>>[];

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final pointer = _allocateZeroed(byteCount == 0 ? 1 : byteCount);
    if (pointer == nullptr) {
      throw StateError('out of native memory');
    }
    _allocated.add(pointer);
    return pointer.cast();
  }

  @override
  void free(Pointer<NativeType> pointer) {
    _allocated.remove(pointer.cast<Void>());
    _release(pointer.cast());
  }

  /// Frees everything still allocated.
  void releaseAll() {
    for (final pointer in _allocated) {
      _release(pointer);
    }
    _allocated.clear();
  }

  /// A copy of [bytes] followed by a zero byte.
  Pointer<Uint8> bytes(List<int> bytes) {
    final pointer = allocate<Uint8>(bytes.length + 1);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  /// [text] as a zero-terminated UTF-8 C string.
  Pointer<Uint8> string(String text) => bytes(utf8.encode(text));
}

/// The text of the zero-terminated UTF-8 C string at [pointer].
String readCString(Pointer<Uint8> pointer) {
  var length = 0;
  while (pointer[length] != 0) {
    length++;
  }
  return utf8.decode(pointer.asTypedList(length));
}

/// The length in bytes of the zero-terminated C string at [pointer].
int cStringLength(Pointer<Uint8> pointer) {
  var length = 0;
  while (pointer[length] != 0) {
    length++;
  }
  return length;
}

/// Overwrites [length] bytes at [pointer] with zeros (a secret's copy,
/// before it is freed).
void wipe(Pointer<Uint8> pointer, int length) =>
    pointer.asTypedList(length).fillRange(0, length, 0);
