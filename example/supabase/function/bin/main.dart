// The Edge Function `api` of the Supabase example, written in Dart: the
// same kind of application as ../server, behind Supabase's Edge Runtime
// instead of a socket. The README of ../ says how to build and call it.
//
//   dart run build_runner build                      # after changing beans
//   dart run spring_boot_starter_edge:build \
//     --platform supabase --name api \
//     --output ../supabase/functions/api             # index.ts and main.js
//   dart run bin/main.dart                           # or as a server, port 8083
import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';

import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main() => runFetchApplication(() => springApplication);
