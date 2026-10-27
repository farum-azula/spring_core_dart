// Writes password hashes with the Dart encoders, for Spring Security to
// check (see tool/security_reference/README.md). In spring_security_core:
//
//   dart run test/vectors/write_password_hashes.dart <file>
import 'dart:convert';
import 'dart:io';

import 'package:spring_security_core/spring_security_core.dart';

void main(List<String> args) {
  final encoders = <String, PasswordEncoder>{
    'argon2': Argon2PasswordEncoder.defaultsForSpringSecurity(),
    'pbkdf2': Pbkdf2PasswordEncoder.defaultsForSpringSecurity(),
    'scrypt': SCryptPasswordEncoder.defaultsForSpringSecurity(),
    'delegating': PasswordEncoderFactories.createDelegatingPasswordEncoder(),
  };
  final vectors = [
    for (final password in ['password', '', 'pässwörd ✓', r'a:b\c"d'])
      for (final MapEntry(key: id, value: encoder) in encoders.entries)
        {'id': id, 'password': password, 'hash': encoder.encode(password)},
  ];
  File(args.single).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(vectors)}\n',
  );
}
