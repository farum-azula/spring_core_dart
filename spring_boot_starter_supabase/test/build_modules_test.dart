// The modules kept to servers, as the generator lists them in the
// example's application: under dart.library.io without dart.library.ui, so
// a Flutter app and a browser build have none of their code.
@Tags(['supabase'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  final code = File(
    Isolate.resolvePackageUriSync(
      Uri.parse(
        'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart',
      ),
    )!.resolve('../example/spring_gen/example.spring.dart').toFilePath(),
  ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');

  for (final module in [
    'springBootStarterSupabaseAdminAutoConfiguration',
    'springBootStarterSupabaseServerAutoConfiguration',
  ]) {
    test('$module: only on a server', () {
      expect(
        code,
        matches(
          RegExp(
            r"if\(\(\(constbool\.fromEnvironment\('dart\.library\.io'\)&&"
            r"!constbool\.fromEnvironment\('dart\.library\.ui'\)\)\|\|"
            r"constbool\.fromEnvironment\('SPRING_ALL_PLATFORMS'\)\)\)"
            '_i\\d+\\.$module,',
          ),
        ),
      );
    });
  }

  test('the rest of the starter is on every platform', () {
    expect(
      code,
      matches(RegExp(r',_i\d+\.springBootStarterSupabaseAutoConfiguration,')),
    );
  });
}
