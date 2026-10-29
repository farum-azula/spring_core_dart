// The browser of the spa mode on the VM: a tab (address, history,
// storages, navigation) and a WebCrypto vault on a software key.
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The browser tab: its address, its history entry, its storages, and
/// where it was sent.
final class FakeSpaPage implements SpaBrowserPage {
  FakeSpaPage([String base = 'http://localhost:5050/'])
    : baseUri = Uri.parse(base),
      location = Uri.parse(base);

  @override
  final Uri baseUri;

  @override
  Uri location;

  @override
  final InMemoryBrowserStorage sessionStorage = InMemoryBrowserStorage();

  @override
  final InMemoryBrowserStorage localStorage = InMemoryBrowserStorage();

  final visited = <Uri>[];
  final replaced = <Uri>[];

  @override
  String? cookie(String name) => null;

  @override
  void navigate(Uri url) => visited.add(url);

  @override
  void replaceLocation(Uri url) {
    replaced.add(url);
    location = url;
  }

  /// Everything the page keeps between loads, for the "never a token"
  /// checks.
  String get stored =>
      jsonEncode({...sessionStorage.items, ...localStorage.items});
}

/// A vault on a software key, counting its loads; [der] makes it answer
/// DER signatures, as a platform key would.
final class FakeVault implements BrowserKeyVault {
  FakeVault({this.der = false});

  final bool der;
  final SoftwareDPoPKey key = SoftwareDPoPKey.generate();
  int loads = 0;
  bool deleted = false;

  @override
  Future<BrowserKeyPair> loadOrCreate(String name) async {
    loads++;
    return _Pair(key, der: der);
  }

  @override
  Future<void> delete(String name) async => deleted = true;
}

final class _Pair implements BrowserKeyPair {
  _Pair(this.key, {required this.der});

  final SoftwareDPoPKey key;
  final bool der;

  @override
  Map<String, Object?> get publicJwk => key.publicJwk;

  @override
  Future<Uint8List> sign(Uint8List input) async {
    final raw = await key.sign(input);
    if (!der) {
      return raw;
    }
    List<int> integer(List<int> bytes) {
      var value = bytes.skipWhile((b) => b == 0).toList();
      if (value.isEmpty || value.first & 0x80 != 0) {
        value = [0, ...value];
      }
      return [0x02, value.length, ...value];
    }

    final body = [...integer(raw.sublist(0, 32)), ...integer(raw.sublist(32))];
    return Uint8List.fromList([0x30, body.length, ...body]);
  }
}
