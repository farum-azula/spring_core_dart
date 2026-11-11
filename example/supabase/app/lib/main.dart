// The app of the Supabase example: sign-in and sign-up with an email and a
// password, a live list of the user's todos, an avatar in Storage and an
// Edge Function, all on one Supabase project and as the signed-in user.
// The README of ../ says how to start a project.
//
//   dart run build_runner build      # after changing beans
//   flutter run --dart-define=SUPABASE_ANON_KEY=...
//
// Its one screen is the @ScreenRoute of lib/src/app/home_page.dart; the
// app widget and its theme come from lib/resources/application.yml.
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:supabase_example_app/spring_gen/main.spring.dart';

@SpringBootApplication()
void main() =>
    runApp(SpringApplicationWidget(application: () => springApplication));
