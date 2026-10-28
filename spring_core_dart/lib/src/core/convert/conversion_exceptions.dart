/// The error a conversion service throws when a value cannot be turned
/// into the requested type.
///
/// Catch it where a value comes from outside and a bad one should not be
/// fatal, such as a query parameter or a line of an import file. When it
/// happens while beans are created (a bad `@Value`), the start fails.
/// It is sealed: every conversion error is either a
/// [ConversionFailedException] (a converter exists but the value is bad)
/// or a [ConverterNotFoundException] (nothing converts to that type).
///
/// ```dart
/// // A page size typed by a user: fall back instead of failing.
/// int pageSize(String input) {
///   try {
///     return conversionService.convert<int>(input);
///   } on ConversionException catch (error) {
///     log.warn(error.message);
///     return 20;
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   conversionService.convert("abc", Integer.class);
/// } catch (ConversionException ex) {
///   log.warn(ex.getMessage());
/// }
/// ```
sealed class ConversionException implements Exception {
  /// Creates the exception with its [message].
  const ConversionException(this.message);

  /// What failed, naming the value and the target type.
  final String message;

  @override
  // Subclasses show their own name.
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType: $message';
}

/// The conversion error for a value the converter could not handle, such
/// as `'12x'` for an `int`.
///
/// Also thrown when the converter, or the source itself, gives `null` for
/// a non-nullable target: `convert<int>('')` fails this way because a
/// blank string converts to `null`. The converter's own error is kept in
/// [cause].
///
/// ```dart
/// try {
///   DefaultConversionService().convert<int>('12x');
/// } on ConversionFailedException catch (error) {
///   log.warning(error.cause); // the FormatException thrown by the parser
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   new DefaultConversionService().convert("12x", Integer.class);
/// } catch (ConversionFailedException ex) {
///   Throwable cause = ex.getCause();
/// }
/// ```
final class ConversionFailedException extends ConversionException {
  /// Creates the exception for converting [value] to [targetType], with
  /// the converter's error as [cause] when there was one.
  ConversionFailedException(this.value, this.targetType, [this.cause])
    : super(
        "Failed to convert ${value.runtimeType} '$value' to $targetType"
        '${cause == null ? '' : ': $cause'}',
      );

  /// The source value that could not be converted.
  final Object? value;

  /// The requested target type.
  final Type targetType;

  /// The error the converter threw, such as a [FormatException]; `null`
  /// when the conversion failed because the result was `null`.
  final Object? cause;
}

/// The conversion error for a target type that nothing converts to, or a
/// source that no converter of that target accepts.
///
/// It usually means a type was never registered: an enum without
/// `addEnum`, a `List` of a type without `addCollectionConverters`, or a
/// class of the application without `addConverter`.
///
/// ```dart
/// try {
///   GenericConversionService().convert<Uri>(42);
/// } on ConverterNotFoundException catch (error) {
///   log.warning(error.sourceType); // int
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   new GenericConversionService().convert(42, URI.class);
/// } catch (ConverterNotFoundException ex) {
///   TypeDescriptor source = ex.getSourceType();
/// }
/// ```
final class ConverterNotFoundException extends ConversionException {
  /// Creates the exception for the missing conversion from [sourceType] to
  /// [targetType].
  ConverterNotFoundException(this.sourceType, this.targetType)
    : super('No converter found from $sourceType to $targetType');

  /// The run-time type of the value that was to be converted.
  final Type sourceType;

  /// The requested target type.
  final Type targetType;
}
