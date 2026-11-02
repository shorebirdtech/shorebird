import 'package:meta/meta.dart';

/// An exception thrown by the API client.
///
/// This is a wrapper around the underlying network exceptions.
/// This is used to provide a standard exception type for clients to handle.
///
/// The generic `T` is the parsed body of the error response, as declared by
/// the operation's `default:` (or error) response in the OpenAPI spec. For
/// operations that do not declare a typed error body, `T` is `dynamic` and
/// [body] is always null.
@immutable
class ApiException<T> implements Exception {
  const ApiException(this.code, this.message, {this.body})
    : innerException = null,
      stackTrace = null;

  const ApiException.unhandled(this.code)
    : message = 'Unhandled response',
      body = null,
      innerException = null,
      stackTrace = null;

  const ApiException.withInner(
    this.code,
    this.message,
    this.innerException,
    this.stackTrace,
  ) : body = null;

  final int code;
  final String? message;

  /// The parsed error body, if the operation's `default:` response declared
  /// a schema. Null otherwise.
  final T? body;
  final Exception? innerException;
  final StackTrace? stackTrace;

  @override
  String toString() {
    if (message == null) {
      return 'ApiException';
    }
    if (innerException == null) {
      return 'ApiException $code: $message';
    }
    return 'ApiException $code: $message '
        '(Inner exception: $innerException)\n\n$stackTrace';
  }
}

/// Validates a number against the constraints a schema declares for it.
///
/// [validate] is the sugar the generator emits: one call carrying every bound
/// the schema sets, each argument omitted when it doesn't. It just forwards to
/// the single-rule methods below, which are equally usable on their own.
extension ValidateNumber on num {
  void validate({
    num? min,
    num? max,
    num? exclusiveMin,
    num? exclusiveMax,
    num? multipleOf,
  }) {
    if (min != null) validateMinimum(min);
    if (max != null) validateMaximum(max);
    if (exclusiveMin != null) validateExclusiveMinimum(exclusiveMin);
    if (exclusiveMax != null) validateExclusiveMaximum(exclusiveMax);
    if (multipleOf != null) validateMultipleOf(multipleOf);
  }

  /// Validates that the value is one of [enumValues] — the members of a
  /// nameless integer `enum`, which is generated as a newtype over `int`.
  /// This is its own call rather than a [validate] argument: an int enum
  /// never also carries range bounds, so membership is the only rule. Unlike
  /// the range checks, an out-of-set value is a parse failure (the wire
  /// carried a value the type does not name), so it throws [FormatException]
  /// to match how a generated `fromJson` reports malformed input.
  void validateEnumValues(List<num> enumValues) {
    if (!enumValues.contains(this)) {
      throw FormatException('$this is not one of $enumValues');
    }
  }

  void validateMinimum(num minimum) {
    if (this < minimum) {
      throw Exception('must be greater than or equal to $minimum');
    }
  }

  void validateMaximum(num maximum) {
    if (this > maximum) {
      throw Exception('must be less than or equal to $maximum');
    }
  }

  void validateExclusiveMinimum(num minimum) {
    if (this <= minimum) {
      throw Exception('must be greater than $minimum');
    }
  }

  void validateExclusiveMaximum(num maximum) {
    if (this >= maximum) {
      throw Exception('must be less than $maximum');
    }
  }

  void validateMultipleOf(num multiple) {
    if (this % multiple != 0) {
      throw Exception('must be a multiple of $multiple');
    }
  }
}

/// Validates a string against the constraints a schema declares for it.
///
/// See [ValidateNumber] — [validate] is sugar over the single-rule methods.
extension ValidateString on String {
  void validate({int? minLength, int? maxLength, String? pattern}) {
    if (minLength != null) validateMinimumLength(minLength);
    if (maxLength != null) validateMaximumLength(maxLength);
    if (pattern != null) validatePattern(pattern);
  }

  void validateMinimumLength(int minimum) {
    if (length < minimum) {
      throw Exception('must be at least $minimum characters long');
    }
  }

  void validateMaximumLength(int maximum) {
    if (length > maximum) {
      throw Exception('must be at most $maximum characters long');
    }
  }

  void validatePattern(String pattern) {
    if (!RegExp(pattern).hasMatch(this)) {
      throw Exception('must match the pattern $pattern');
    }
  }
}

/// Validates a list against the constraints a schema declares for it.
///
/// See [ValidateNumber] — [validate] is sugar over the single-rule methods.
extension ValidateArray<T> on List<T> {
  void validate({int? minItems, int? maxItems, bool unique = false}) {
    if (minItems != null) validateMinimumItems(minItems);
    if (maxItems != null) validateMaximumItems(maxItems);
    if (unique) validateUniqueItems();
  }

  void validateMinimumItems(int minimum) {
    if (length < minimum) {
      throw Exception('must be at least $minimum items long');
    }
  }

  void validateMaximumItems(int maximum) {
    if (length > maximum) {
      throw Exception('must be at most $maximum items long');
    }
  }

  void validateUniqueItems() {
    if (toSet().length != length) {
      throw Exception('must contain unique items');
    }
  }
}
