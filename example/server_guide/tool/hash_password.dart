// Hashes a password for application.properties (or, in prod, for the
// environment), with the encoder the server checks logins with:
//
//   dart run tool/hash_password.dart ada-secret
//   {argon2}$argon2id$v=19$m=16384,t=2,p=1$...
//
// The users' passwords are never stored as they are; the hashes of
// `ada-secret` and `root-secret` in application.properties were made with
// this tool.

// A command line tool: the result goes to the console.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:spring_security_core/spring_security_core.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/hash_password.dart <password>');
    exitCode = 64;
    return;
  }
  print(
    PasswordEncoderFactories.createDelegatingPasswordEncoder().encode(
      args.single,
    ),
  );
}
