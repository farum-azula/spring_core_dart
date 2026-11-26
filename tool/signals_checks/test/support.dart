import 'dart:io';

import 'package:signals_checks/main.dart';
import 'package:signals_checks/spring_gen/main.spring.dart';
import 'package:spring_security_core/spring_security_core.dart';

export 'package:signals_checks/main.dart';

int _db = 0;

/// The application on a store of its own; [arguments] are properties.
Future<ConfigurableApplicationContext> startApp([
  List<String> arguments = const [],
]) async {
  trace.clear();
  final dir = Directory.systemTemp.createTempSync('signals_checks');
  return springApplication.runAsync([
    '--spring.datasource.url=jdbc:sqlite:file:${dir.path}/app${_db++}.db',
    ...arguments,
  ]);
}

/// What was assigned so far has been told.
Future<void> told() => Future<void>.delayed(Duration.zero);

SecurityContext ctx(String name, List<String> roles) {
  final user = User.withUsername(name).password(null).roles(roles).build();
  return SecurityContextImpl(
    UsernamePasswordAuthenticationToken.authenticated(
      user,
      null,
      user.authorities,
    ),
  );
}

R asAda<R>(R Function() body) =>
    SecurityContextHolder.runWithContext(body, ctx('ada', ['USER']));
R asBob<R>(R Function() body) =>
    SecurityContextHolder.runWithContext(body, ctx('bob', ['USER']));
R asRoot<R>(R Function() body) =>
    SecurityContextHolder.runWithContext(body, ctx('root', ['ADMIN']));
R asNobody<R>(R Function() body) => SecurityContextHolder.runWithContext(body);
