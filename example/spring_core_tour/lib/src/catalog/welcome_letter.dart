// Classpath resources: files of lib/resources/ injected with @Value.
//
// Spring (Java): @Value("classpath:templates/welcome.txt") Resource template.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/catalog/catalog.dart';

@Component()
class WelcomeLetter {
  WelcomeLetter(
    this.books,
    @Value('classpath:templates/welcome.txt') this.template,
    @Value('classpath:logo.png') this.logo,
  );

  final BookRepository books;
  final Resource template;
  final Resource logo;

  String compose() => MessageFormat.format(template.readAsStringSync().trim(), [
    books.findAll().length,
  ]);

  int get logoSize => logo.readAsBytesSync().length;
}
