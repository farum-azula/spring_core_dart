import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_figure.dart';

/// The memory of a native app: the process's resident memory, and the
/// Dart heap of the UI isolate's group from the VM service, which a debug
/// or a profile build has. The VM service is connected to when something
/// starts to show the figures, and let go of when nothing does.
MemoryFigureSource platformMemorySource() => _NativeMemory();

const _rssNote =
    'All the memory the system holds for the app: the Dart heap, the '
    'engine, textures, code and libraries.';

const _heapNote =
    'The Dart objects of the UI isolate\'s group, of the capacity the VM '
    'reserved; from the VM service, in debug and profile builds.';

final class _NativeMemory implements MemoryFigureSource {
  _VmServiceHeap? _heap;

  @override
  void open() => _heap ??= _VmServiceHeap()..connect();

  @override
  Future<List<MemoryFigure>> read() async {
    final heap = await _heap?.read();
    final rss = _rss();
    return [
      MemoryFigure(
        name: 'Process (RSS)',
        note: _rssNote,
        used: rss,
        short: 'mem',
        unavailable: rss == null ? 'the system does not tell' : null,
      ),
      MemoryFigure(
        name: 'Dart heap',
        note: _heapNote,
        used: heap?.used,
        amounts: [
          if (heap case final heap?) MemoryAmount('capacity', heap.capacity),
        ],
        unavailable: heap == null
            ? (_heap?.unavailable ?? 'connecting to the VM service')
            : null,
      ),
    ];
  }

  @override
  void close() {
    _heap?.close();
    _heap = null;
  }

  static int? _rss() {
    try {
      return ProcessInfo.currentRss;
    } on Object {
      return null;
    }
  }
}

// A heap's use and capacity, as the VM service tells them.
final class _Heap {
  const _Heap(this.used, this.capacity);

  final int used;
  final int capacity;
}

// The one call of the VM service the block makes (`getMemoryUsage`), over
// a WebSocket of its own: no package for one JSON-RPC method.
final class _VmServiceHeap {
  static const _timeout = Duration(seconds: 2);

  WebSocket? _socket;
  String? _isolateId;
  final _answers = <String, Completer<Map<String, Object?>>>{};
  var _next = 0;
  var _closed = false;

  // Why there is no heap; `null` while connecting or connected.
  String? unavailable;

  Future<void> connect() async {
    try {
      final info = await developer.Service.getInfo();
      final address = info.serverWebSocketUri;
      if (address == null) {
        unavailable = 'not available: no VM service (a release build, or run without one)';
        return;
      }
      _isolateId = developer.Service.getIsolateId(Isolate.current);
      final socket = await WebSocket.connect(
        address.toString(),
      ).timeout(_timeout);
      if (_closed) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.listen(
        _answer,
        onDone: () => unavailable ??= 'not available: the VM service closed',
        onError: (Object _) {},
        cancelOnError: false,
      );
    } on Object {
      unavailable = 'not available: the VM service did not answer';
    }
  }

  Future<_Heap?> read() async {
    final socket = _socket;
    final isolateId = _isolateId;
    if (socket == null || isolateId == null) {
      return null;
    }
    final id = '${_next++}';
    final answer = Completer<Map<String, Object?>>();
    _answers[id] = answer;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': 'getMemoryUsage',
        'params': {'isolateId': isolateId},
      }),
    );
    try {
      final result = await answer.future.timeout(_timeout);
      final used = result['heapUsage'];
      final capacity = result['heapCapacity'];
      return used is int && capacity is int ? _Heap(used, capacity) : null;
    } on Object {
      return null;
    } finally {
      _answers.remove(id);
    }
  }

  void _answer(Object? message) {
    if (message is! String) {
      return;
    }
    final decoded = jsonDecode(message);
    if (decoded is! Map<String, Object?>) {
      return;
    }
    final answer = _answers[decoded['id']];
    final result = decoded['result'];
    if (answer != null && result is Map<String, Object?>) {
      answer.complete(result);
    }
  }

  void close() {
    _closed = true;
    unawaited(_socket?.close());
    _socket = null;
  }
}
