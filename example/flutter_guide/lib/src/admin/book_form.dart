import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// Turns the Admin form's texts into a checked [NewBook], the Spring way:
/// a `DataBinder` binds the texts onto a `NewBook` (converting the price;
/// "abc" becomes a `typeMismatch` error), then the `BeanValidator` checks
/// the constraints of `NewBook`. The errors carry Spring's codes
/// (`NotBlank.newBook.title`, `NotBlank`, ...), which the messages files
/// translate.
@Component()
class BookForm {
  BookForm(this._validator, this._introspector);

  final BeanValidator _validator;
  final BeanIntrospector _introspector;

  /// The book, or the errors of [fields] (`isbn`, `title`, `author`,
  /// `price`).
  (NewBook?, BindingResult) bind(Map<String, String> fields) {
    final binder =
        DataBinder(
            NewBook(),
            objectName: 'newBook',
            introspector: _introspector,
          )
          ..validators.add(_validator)
          ..bind({
            for (final MapEntry(:key, :value) in fields.entries)
              key: value.trim(),
          })
          ..validate();
    final result = binder.bindingResult;
    return (result.hasErrors ? null : binder.target! as NewBook, result);
  }
}
