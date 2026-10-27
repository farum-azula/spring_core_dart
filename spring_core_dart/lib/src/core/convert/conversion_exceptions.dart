/// Base class of conversion errors, like Spring's `ConversionException`.
///
/// Sealed: every conversion error is either a [ConversionFailedException]
/// or a [ConverterNotFoundException].
///
/// ```dart
/// try {
///   conversionService.convert<int>('abc');
/// } on ConversionException catch (error) {
///   print(error.message);
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
  /// Creates an exception with a human-readable [message].
  const ConversionException(this.message);

  /// Human-readable description of the failure.
  final String message;

  @override
  // Subclasses show their own name.
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType: $message';
}

/// A converter exists but failed (or produced `null` for a non-nullable
/// target).
///
/// ```dart
/// try {
///   DefaultConversionService().convert<int>('12x');
/// } on ConversionFailedException catch (error) {
///   print(error.cause); // the FormatException thrown by the parser
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
  /// the optional underlying [cause].
  ConversionFailedException(this.value, this.targetType, [this.cause])
    : super(
        "Failed to convert ${value.runtimeType} '$value' to $targetType"
        '${cause == null ? '' : ': $cause'}',
      );

  /// The source value that could not be converted.
  final Object? value;

  /// The requested target type.
  final Type targetType;

  /// The error thrown by the converter, if any.
  final Object? cause;
}

/// No converter can turn the value into the target type.
///
/// ```dart
/// try {
///   GenericConversionService().convert<Uri>(42);
/// } on ConverterNotFoundException catch (error) {
///   print(error.sourceType); // int
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
  /// Creates the exception for the missing [sourceType] → [targetType]
  /// conversion.
  ConverterNotFoundException(this.sourceType, this.targetType)
    : super('No converter found from $sourceType to $targetType');

  /// Runtime type of the source value.
  final Type sourceType;

  /// The requested target type.
  final Type targetType;
}
