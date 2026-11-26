import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';

/// The status classes the Network tab filters by.
enum NetworkStatusFilter {
  /// Every entry.
  all('All'),

  /// `1xx` and `2xx`, and a WebSocket open or closed normally.
  success('2xx'),

  /// `3xx`.
  redirect('3xx'),

  /// `4xx`.
  clientError('4xx'),

  /// `5xx`.
  serverError('5xx'),

  /// No answer.
  failed('Failed'),

  /// Still in flight.
  pending('Pending');

  const NetworkStatusFilter(this.label);

  /// Its chip's label.
  final String label;

  /// Whether an entry of [status] passes.
  bool matches(NetworkStatusClass status) => switch (this) {
    all => true,
    success =>
      status == NetworkStatusClass.success ||
          status == NetworkStatusClass.informational,
    redirect => status == NetworkStatusClass.redirect,
    clientError => status == NetworkStatusClass.clientError,
    serverError => status == NetworkStatusClass.serverError,
    failed => status == NetworkStatusClass.failed,
    pending => status == NetworkStatusClass.pending,
  };
}

/// Which entries of the network journal show: by [text] in the address,
/// by [method] (`WS` for the WebSockets), by [status]. Kept by the Network
/// tab's section while the panel is closed, so it opens as it was left;
/// a compact view may keep one of its own.
class DebugNetworkFilter extends ChangeNotifier {
  /// A filter that lets every entry through.
  DebugNetworkFilter();

  /// The order of the method chips: the methods that read, those that
  /// write, `WS` for the WebSockets; a method not listed comes after them,
  /// by name.
  static const methodOrder = [
    'GET',
    'HEAD',
    'OPTIONS',
    'TRACE',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'WS',
  ];

  /// The method chips for [entries]: each method they have and the one
  /// chosen ([method]), in [methodOrder].
  List<String> methodsOf(Iterable<NetworkEntry> entries) {
    final methods = {
      for (final entry in entries) entry.method,
      ?_method,
    };
    int rank(String method) {
      final index = methodOrder.indexOf(method);
      return index < 0 ? methodOrder.length : index;
    }

    return methods.toList()..sort(
      (a, b) =>
          rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : a.compareTo(b),
    );
  }

  String _text = '';
  String? _method;
  NetworkStatusFilter _status = NetworkStatusFilter.all;

  /// What the address must contain, in any case; empty: any.
  String get text => _text;

  set text(String value) {
    if (value != _text) {
      _text = value;
      notifyListeners();
    }
  }

  /// The method an entry must have (`WS` for a WebSocket); `null`: any.
  String? get method => _method;

  set method(String? value) {
    if (value != _method) {
      _method = value;
      notifyListeners();
    }
  }

  /// The class its status must be in.
  NetworkStatusFilter get status => _status;

  set status(NetworkStatusFilter value) {
    if (value != _status) {
      _status = value;
      notifyListeners();
    }
  }

  /// Whether [entry] shows.
  bool matches(NetworkEntry entry) {
    if (_method case final method? when entry.method != method) {
      return false;
    }
    if (!_status.matches(entry.statusClass)) {
      return false;
    }
    final text = _text.trim().toLowerCase();
    return text.isEmpty || entry.url.toString().toLowerCase().contains(text);
  }
}
