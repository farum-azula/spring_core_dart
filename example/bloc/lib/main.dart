// Bloc Showcase: Bloc and Cubit in a Spring Boot Flutter app, with no
// starter for them. A bloc is a class, so it is a bean: its dependencies
// come by injection, its lifetime is its scope (the app's, a screen's),
// and a widget takes it from the context. Run it with `flutter run`.
//
// - a Cubit for the whole app (lib/src/blocs/counter_cubit.dart);
// - a Bloc with events, states and an injected service
//   (lib/src/blocs/books_bloc.dart);
// - a Cubit that lives as long as one screen (lib/src/blocs/draft_cubit.dart);
// - every bloc's events and state changes as application events, heard
//   with @EventListener (lib/src/events/, lib/src/journal.dart).
import 'package:bloc_showcase/spring_gen/main.spring.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

// No home: the screens of the navigation make the app.
@SpringBootApplication()
void main() =>
    runApp(SpringApplicationWidget(application: () => springApplication));
