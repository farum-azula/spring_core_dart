import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

/// What the bytes of a connection said about one request, before `dart:io`
/// parsed it. `dart:io` keeps only the last `Host` of a request, so a second
/// one can be seen nowhere else.
enum RequestHeadVerdict {
  /// One `Host` header, or none.
  sound(null),

  /// Two or more `Host` headers: a 400, as Tomcat answers
  /// (`http11processor.request.multipleHosts`; RFC 9112 §3.2).
  repeatedHost('A request cannot have more than one Host header'),

  /// `dart:io` delivered a request the scanner did not count, so nothing is
  /// known about its headers: refused rather than served unchecked.
  unchecked('The request could not be checked');

  RequestHeadVerdict(this.problem);

  /// What the 400 says; `null` when the request may go on.
  final String? problem;
}

/// Follows the request heads in the bytes of one connection, reading them
/// as `dart:io`'s `_HttpParser` does, and counts their `Host` headers.
///
/// It never changes or holds a byte: it only reads the chunk `dart:io` is
/// about to get. To know where the next head starts it follows the framing
/// (`Content-Length`, chunked, an upgrade) with the parser's own rules, its
/// tolerances included (a bare LF, `Transfer-Encoding` after
/// `Content-Length`, folded values). A body is skipped by its length: its
/// bytes are not looked at, also inside chunks.
///
/// What `dart:io` would refuse ends the scan, since `dart:io` then closes
/// the connection. Should a request arrive all the same, [next] answers
/// [RequestHeadVerdict.unchecked].
final class RequestHeadScanner {
  // The states of `_HttpParser` that matter for finding the next head.
  static const int _requestLine = 0;
  static const int _firstField = 1;
  static const int _name = 2;
  static const int _valueStart = 3;
  static const int _value = 4;
  static const int _valueEndingCr = 5;
  static const int _foldOrEnd = 6;
  static const int _headEnding = 7;
  static const int _body = 8;
  static const int _chunkEndCr = 9;
  static const int _chunkEndLf = 10;
  static const int _chunkSize = 11;
  static const int _chunkExtension = 12;
  static const int _chunkSizeEnding = 13;
  static const int _lastChunkCr = 14;
  static const int _lastChunkLf = 15;
  // An upgraded connection, or one `dart:io` is about to close.
  static const int _finished = 16;

  static const int _cr = 13;
  static const int _lf = 10;
  static const int _sp = 32;
  static const int _ht = 9;
  static const int _colon = 58;
  static const int _semicolon = 59;

  // `dart:io` fails a head past 1 MB, and a chunk size past this.
  static const int _maxValue = 1024 * 1024;
  static const int _maxChunkSize = 0x7FFFFFFF;

  // The longest name of [_fields].
  static const int _maxName = 17;

  static final List<_HeadField> _fields = <_HeadField>[
    _HeadField('host', onName: (scanner) => scanner._countHost()),
    _HeadField(
      'content-length',
      onValue: (scanner, value) => scanner._readContentLength(value),
    ),
    _HeadField(
      'transfer-encoding',
      onValue: (scanner, value) => scanner._readTransferEncoding(value),
    ),
    _HeadField(
      'connection',
      onValue: (scanner, value) => scanner._readConnection(value),
    ),
  ];

  int _state = _requestLine;

  // The heads seen, the first with a repeated Host, the requests answered.
  var _heads = 0;
  int? _repeatedHost;
  var _served = 0;

  // The field being read.
  final _nameBytes = Uint8List(_maxName);
  var _nameLength = 0;
  _HeadField? _field;
  Uint8List? _valueBytes;
  var _valueLength = 0;

  // The head being read.
  var _hosts = 0;
  var _sawLength = false;
  var _length = 0;
  var _sawEncoding = false;
  var _chunked = false;
  var _upgrade = false;

  // What is left of the body or of the chunk.
  var _remaining = 0;

  /// The verdict on the next request `dart:io` delivers on this connection.
  /// Called once per request, in order.
  RequestHeadVerdict next() {
    final index = _served++;
    if (index >= _heads) {
      return RequestHeadVerdict.unchecked;
    }
    return index == _repeatedHost
        ? RequestHeadVerdict.repeatedHost
        : RequestHeadVerdict.sound;
  }

  /// Reads [bytes], the next chunk of the connection.
  void scan(Uint8List bytes) {
    final length = bytes.length;
    var index = 0;
    while (index < length) {
      switch (_state) {
        case _requestLine:
          while (index < length && bytes[index] != _lf) {
            index++;
          }
          if (index < length) {
            index++;
            _state = _firstField;
          }
        case _firstField:
          final byte = bytes[index++];
          if (byte == _cr) {
            _state = _headEnding;
          } else if (byte == _lf) {
            _state = _headEnding;
            index--;
          } else {
            _startName(byte);
          }
        case _name:
          final byte = bytes[index++];
          if (byte == _colon) {
            _endName();
          } else {
            _addToName(byte);
          }
        case _valueStart:
          final byte = bytes[index++];
          if (byte == _cr) {
            _state = _valueEndingCr;
          } else if (byte == _lf) {
            _state = _foldOrEnd;
          } else if (byte != _sp && byte != _ht) {
            _addToValue(byte);
            if (_state == _valueStart) {
              _state = _value;
            }
          }
        case _value:
          index = _field?.readsValue ?? false
              ? _readValue(bytes, index)
              : _skipValue(bytes, index);
        case _valueEndingCr:
          if (bytes[index++] == _lf) {
            _state = _foldOrEnd;
          } else {
            _state = _finished;
          }
        case _foldOrEnd:
          final byte = bytes[index++];
          if (byte == _sp || byte == _ht) {
            _addToValue(_sp);
            if (_state == _foldOrEnd) {
              _state = _valueStart;
            }
          } else {
            _endField();
            if (_state == _finished) {
              return;
            }
            if (byte == _cr) {
              _state = _headEnding;
            } else if (byte == _lf) {
              _state = _headEnding;
              index--;
            } else {
              _startName(byte);
            }
          }
        case _headEnding:
          if (bytes[index++] == _lf) {
            _endHead();
          } else {
            _state = _finished;
          }
        case _body:
          final available = length - index;
          final taken = available < _remaining ? available : _remaining;
          index += taken;
          _remaining -= taken;
          if (_remaining == 0) {
            if (_chunked) {
              _state = _chunkEndCr;
            } else {
              _endMessage();
            }
          }
        case _chunkEndCr:
          final byte = bytes[index++];
          if (byte == _lf) {
            _state = _chunkEndLf;
            index--;
          } else if (byte == _cr) {
            _state = _chunkEndLf;
          } else {
            _state = _finished;
          }
        case _chunkEndLf:
          if (bytes[index++] == _lf) {
            _state = _chunkSize;
          } else {
            _state = _finished;
          }
        case _chunkSize:
          final byte = bytes[index++];
          if (byte == _cr) {
            _state = _chunkSizeEnding;
          } else if (byte == _lf) {
            _state = _chunkSizeEnding;
            index--;
          } else if (byte == _semicolon) {
            _state = _chunkExtension;
          } else {
            _addChunkDigit(byte);
          }
        case _chunkExtension:
          final byte = bytes[index++];
          if (byte == _cr) {
            _state = _chunkSizeEnding;
          } else if (byte == _lf) {
            _state = _chunkSizeEnding;
            index--;
          }
        case _chunkSizeEnding:
          if (bytes[index++] != _lf) {
            _state = _finished;
          } else {
            _state = _remaining > 0 ? _body : _lastChunkCr;
          }
        case _lastChunkCr:
          final byte = bytes[index++];
          if (byte == _lf) {
            _state = _lastChunkLf;
            index--;
          } else if (byte != _cr) {
            _state = _finished;
          }
        case _lastChunkLf:
          if (bytes[index++] == _lf) {
            _endMessage();
          } else {
            _state = _finished;
          }
        default:
          return;
      }
    }
  }

  int _skipValue(Uint8List bytes, int start) {
    var index = start;
    final length = bytes.length;
    while (index < length) {
      final byte = bytes[index++];
      if (byte == _cr) {
        _state = _valueEndingCr;
        return index;
      }
      if (byte == _lf) {
        _state = _foldOrEnd;
        return index;
      }
    }
    return index;
  }

  int _readValue(Uint8List bytes, int start) {
    var index = start;
    final length = bytes.length;
    while (index < length) {
      final byte = bytes[index++];
      if (byte == _cr) {
        _state = _valueEndingCr;
        return index;
      }
      if (byte == _lf) {
        _state = _foldOrEnd;
        return index;
      }
      _addToValue(byte);
      if (_state == _finished) {
        return index;
      }
    }
    return index;
  }

  void _startName(int byte) {
    _nameLength = 0;
    _field = null;
    _valueLength = 0;
    _state = _name;
    _addToName(byte);
  }

  void _addToName(int byte) {
    if (_nameLength < _maxName) {
      _nameBytes[_nameLength] = _lowerCase(byte);
    }
    _nameLength++;
  }

  // `_HttpParser._toLowerCaseByte`.
  static int _lowerCase(int byte) =>
      ((byte - 0x41) & 0x7f) < 26 ? byte | 0x20 : byte;

  void _endName() {
    _state = _valueStart;
    for (final field in _fields) {
      if (field.isNamed(_nameBytes, _nameLength)) {
        _field = field;
        field.onName?.call(this);
        return;
      }
    }
  }

  void _addToValue(int byte) {
    if (!(_field?.readsValue ?? false)) {
      return;
    }
    if (_valueLength >= _maxValue) {
      _state = _finished;
      return;
    }
    var buffer = _valueBytes ??= Uint8List(64);
    if (_valueLength == buffer.length) {
      buffer = _valueBytes = Uint8List(buffer.length * 2)
        ..setRange(0, _valueLength, buffer);
    }
    buffer[_valueLength++] = byte;
  }

  void _endField() {
    final field = _field;
    _field = null;
    final onValue = field?.onValue;
    if (onValue == null) {
      return;
    }
    final buffer = _valueBytes ?? Uint8List(0);
    var end = _valueLength;
    while (end > 0 && (buffer[end - 1] == _sp || buffer[end - 1] == _ht)) {
      end--;
    }
    onValue(this, latin1.decode(Uint8List.sublistView(buffer, 0, end)));
  }

  void _countHost() {
    _hosts++;
    if (_hosts == 2) {
      _repeatedHost ??= _heads;
    }
  }

  // `_HttpParser`: a second Content-Length fails unless a Transfer-Encoding
  // came between them; one after a Transfer-Encoding is not read at all.
  void _readContentLength(String value) {
    if (_sawLength) {
      _state = _finished;
      return;
    }
    if (_sawEncoding) {
      return;
    }
    _sawLength = true;
    // `_HttpHeaders._addContentLength`.
    if (value.isEmpty) {
      _state = _finished;
      return;
    }
    var number = 0;
    var digits = 0;
    var counting = 0;
    for (var i = 0; i < value.length; i++) {
      final digit = value.codeUnitAt(i) ^ 0x30;
      if (digit > 9) {
        _state = _finished;
        return;
      }
      number = number * 10 + digit;
      if (number != 0) {
        counting = 1;
      }
      digits += counting;
    }
    if (digits >= 16) {
      _state = _finished;
      return;
    }
    _length = number;
  }

  void _readTransferEncoding(String value) {
    _sawEncoding = true;
    final tokens = _tokens(value);
    if (tokens.isNotEmpty) {
      _chunked = tokens.last.trim().toLowerCase() == 'chunked';
    }
    _sawLength = false;
  }

  void _readConnection(String value) {
    for (final token in _tokens(value)) {
      if (token.length == 7 &&
          String.fromCharCodes(token.codeUnits.map(_lowerCase)) == 'upgrade') {
        _upgrade = true;
      }
    }
  }

  // `_HttpParser._tokenizeFieldValue`, whose first token always takes its
  // first character, a comma too.
  static List<String> _tokens(String value) {
    final length = value.length;
    final tokens = <String>[];
    var start = 0;
    while (start < length) {
      var end = start + 1;
      while (end < length && value.codeUnitAt(end) != 0x2C) {
        end++;
      }
      final comma = end;
      while (start < end && _isSpace(value.codeUnitAt(end - 1))) {
        end--;
      }
      tokens.add(value.substring(start, end));
      start = comma + 1;
      while (start < length && _isSpace(value.codeUnitAt(start))) {
        start++;
      }
    }
    return tokens;
  }

  static bool _isSpace(int unit) => unit == _sp || unit == _ht;

  void _endHead() {
    _heads++;
    if (_sawEncoding && !_chunked) {
      _state = _finished;
    } else if (_upgrade) {
      _state = _finished;
    } else if (_chunked) {
      _remaining = 0;
      _state = _chunkSize;
    } else if (_length > 0) {
      _remaining = _length;
      _state = _body;
    } else {
      _endMessage();
    }
    _hosts = 0;
    _sawLength = false;
    _length = 0;
    _sawEncoding = false;
    _upgrade = false;
  }

  void _endMessage() {
    _chunked = false;
    _remaining = 0;
    _state = _requestLine;
  }

  void _addChunkDigit(int byte) {
    final value = switch (byte) {
      >= 0x30 && <= 0x39 => byte - 0x30,
      >= 0x41 && <= 0x46 => byte - 0x41 + 10,
      >= 0x61 && <= 0x66 => byte - 0x61 + 10,
      _ => -1,
    };
    if (value < 0 || _remaining > _maxChunkSize >> 4) {
      _state = _finished;
      return;
    }
    _remaining = _remaining * 16 + value;
  }
}

/// A header [RequestHeadScanner] has to read.
final class _HeadField {
  _HeadField(String name, {this.onName, this.onValue})
    : _name = ascii.encode(name);

  final Uint8List _name;
  final void Function(RequestHeadScanner scanner)? onName;
  final void Function(RequestHeadScanner scanner, String value)? onValue;

  bool get readsValue => onValue != null;

  bool isNamed(Uint8List bytes, int length) {
    if (length != _name.length) {
      return false;
    }
    for (var i = 0; i < length; i++) {
      if (bytes[i] != _name[i]) {
        return false;
      }
    }
    return true;
  }
}

/// A connection's address that carries its [RequestHeadScanner]: the one
/// thing of the connection `dart:io` hands on with a request, by identity.
final class _ScannedAddress implements io.InternetAddress {
  _ScannedAddress(this._address, this.scanner);

  final io.InternetAddress _address;
  final RequestHeadScanner scanner;

  @override
  String get address => _address.address;

  @override
  String get host => _address.host;

  @override
  bool get isLinkLocal => _address.isLinkLocal;

  @override
  bool get isLoopback => _address.isLoopback;

  @override
  bool get isMulticast => _address.isMulticast;

  @override
  Uint8List get rawAddress => _address.rawAddress;

  @override
  io.InternetAddressType get type => _address.type;

  @override
  Future<io.InternetAddress> reverse() => _address.reverse();

  @override
  bool operator ==(Object other) =>
      other is _ScannedAddress ? other._address == _address : other == _address;

  @override
  int get hashCode => _address.hashCode;

  @override
  String toString() => _address.toString();
}

/// The verdict on [request], the next one of its connection; a connection
/// that was not accepted through a [HeadScannedSocket] has none to give.
RequestHeadVerdict requestHeadVerdict(io.HttpRequest request) =>
    switch (request.connectionInfo?.remoteAddress) {
      final _ScannedAddress address => address.scanner.next(),
      _ => RequestHeadVerdict.unchecked,
    };

/// An accepted socket whose incoming chunks a [RequestHeadScanner] reads
/// on their way to `dart:io`.
///
/// Nothing stands between the two: [listen] gives `dart:io` the socket's own
/// subscription, so pause, resume, cancel and back-pressure are the socket's,
/// and the chunk is the same object. When `dart:io` detaches the socket (a
/// WebSocket upgrade) it replaces the subscription's data handler, and the
/// scanner reads no more.
///
/// The peer's address and port are kept from the start: a socket that was
/// closed has neither, and the verdict is reached through them.
base class HeadScannedSocket extends Stream<Uint8List> implements io.Socket {
  /// Wraps [socket], just accepted.
  HeadScannedSocket(this.socket) {
    try {
      _remoteAddress = _ScannedAddress(socket.remoteAddress, _scanner);
      _remotePort = socket.remotePort;
      _port = socket.port;
    } on Object {
      // Gone already: dart:io then has no address for its requests, and
      // they are refused as unchecked.
      _remoteAddress = null;
    }
  }

  /// The accepted socket.
  final io.Socket socket;

  final _scanner = RequestHeadScanner();
  _ScannedAddress? _remoteAddress;
  int? _remotePort;
  int? _port;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => socket.listen(
    (chunk) {
      _scanner.scan(chunk);
      onData?.call(chunk);
    },
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  io.InternetAddress get remoteAddress =>
      _remoteAddress ?? socket.remoteAddress;

  @override
  int get remotePort => _remotePort ?? socket.remotePort;

  @override
  int get port => _port ?? socket.port;

  @override
  io.InternetAddress get address => socket.address;

  @override
  Encoding get encoding => socket.encoding;

  @override
  set encoding(Encoding value) => socket.encoding = value;

  @override
  void add(List<int> data) => socket.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      socket.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => socket.addStream(stream);

  @override
  Future<void> flush() => socket.flush();

  @override
  Future<void> close() => socket.close();

  @override
  Future<void> get done => socket.done;

  @override
  void destroy() => socket.destroy();

  @override
  void write(Object? object) => socket.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      socket.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => socket.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => socket.writeln(object);

  @override
  bool setOption(io.SocketOption option, bool enabled) =>
      socket.setOption(option, enabled);

  @override
  Uint8List getRawOption(io.RawSocketOption option) =>
      socket.getRawOption(option);

  @override
  void setRawOption(io.RawSocketOption option) => socket.setRawOption(option);
}

/// A [HeadScannedSocket] over TLS: `dart:io` tells a secure connection, and
/// finds the client's certificate, by this type. The scanner reads the
/// decrypted bytes.
final class SecureHeadScannedSocket extends HeadScannedSocket
    implements io.SecureSocket {
  /// Wraps the accepted TLS socket.
  SecureHeadScannedSocket(super.socket) : _secure = socket as io.SecureSocket;

  final io.SecureSocket _secure;

  @override
  io.X509Certificate? get peerCertificate => _secure.peerCertificate;

  @override
  String? get selectedProtocol => _secure.selectedProtocol;

  @override
  void renegotiate({
    bool useSessionCache = true,
    bool requestClientCertificate = false,
    bool requireClientCertificate = false,
    // The deprecated member of the interface is passed on as it is.
    // ignore: deprecated_member_use
  }) => _secure.renegotiate(
    useSessionCache: useSessionCache,
    requestClientCertificate: requestClientCertificate,
    requireClientCertificate: requireClientCertificate,
  );
}
