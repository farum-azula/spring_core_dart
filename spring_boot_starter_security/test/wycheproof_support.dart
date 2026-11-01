// Reads Project Wycheproof's test vectors (test/fixtures/wycheproof/, see
// its README.md) for the tests that run them through the JWS code.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// One Wycheproof test case: its group's values and its own.
typedef Vector = ({
  String file,
  int tcId,
  String comment,
  List<String> flags,
  String result,
  Map<String, Object?> group,
  Map<String, Object?> test,
});

/// Every test case of the Wycheproof file [name] (`ecdsa_..._test.json`),
/// in file order.
List<Vector> loadVectors(String name) {
  final root = Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_security/'),
  )!.resolve('../test/fixtures/wycheproof/$name');
  final json =
      jsonDecode(File.fromUri(root).readAsStringSync()) as Map<String, Object?>;
  final vectors = [
    for (final group
        in (json['testGroups']! as List).cast<Map<String, Object?>>())
      for (final test in (group['tests']! as List).cast<Map<String, Object?>>())
        (
          file: name,
          tcId: test['tcId']! as int,
          comment: test['comment']! as String,
          flags: (test['flags']! as List).cast<String>(),
          result: test['result']! as String,
          group: group,
          test: test,
        ),
  ];
  if (vectors.length != json['numberOfTests']) {
    throw StateError('$name: ${vectors.length} cases, not numberOfTests');
  }
  return vectors;
}

/// The bytes of the hexadecimal [hex] (an even number of digits).
Uint8List hexBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// The non-negative number of the hexadecimal [hex], which may start with
/// the zero byte of a DER integer.
BigInt hexBigInt(String hex) => BigInt.parse(hex, radix: 16);

/// How many cases each result has, as `valid`, `invalid`, `acceptable`.
Map<String, int> tally(Iterable<Vector> vectors) {
  final counts = <String, int>{};
  for (final vector in vectors) {
    counts.update(vector.result, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// The message of a failed case: file, tcId, comment and flags.
String describe(Vector v) =>
    '${v.file} tcId ${v.tcId} (${v.comment}) ${v.flags} is ${v.result}';
