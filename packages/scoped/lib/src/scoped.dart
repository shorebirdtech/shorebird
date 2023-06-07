import 'dart:async';

import 'package:meta/meta.dart';

/// {@template scoped_ref}
/// A reference to a scoped value.
/// {@endtemplate}
@immutable
class ScopedRef<T> {
  /// {@macro scoped_ref}
  ScopedRef(this._create) : _key = Object();

  ScopedRef._(T Function() create, Object key)
      : _create = create,
        _key = key;

  final T Function() _create;
  final Object _key;
  late final T _value = _create();

  /// Overrides the value of the current [ScopedRef]
  /// with the provided [create].
  ScopedRef<T> overrideWith(T Function() create) {
    return ScopedRef<T>._(create, _key);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    if (other is ScopedRef<T>) return _key == other._key;
    return false;
  }

  @override
  int get hashCode => _key.hashCode;
}

/// Creates a [ScopedRef] which can later be used to access the
/// value, [T] returned by [create].
ScopedRef<T> create<T>(T Function() create) => ScopedRef<T>(create);

/// Attempts to retrieve the value for the [ref].
/// If [read] is called with a [ref] which is not available
/// in the current scope, a [StateError] will be thrown.
T read<T>(ScopedRef<T> ref) {
  final value = (Zone.current[ref._key] as ScopedRef<T>?)?._value;
  if (value == null) {
    throw StateError(
      '''
read(...) was called in a scope which does not contain a corresponding value for the provided ref.
Did you forget to call: runScoped(() {...}, values: {value})?''',
    );
  }
  return value;
}

/// Runs [body] within a scope which has access to the set of refs in [values].
R runScoped<R>(
  R Function() body, {
  Set<ScopedRef<dynamic>> values = const {},
}) {
  return runZoned(
    body,
    zoneValues: {for (final value in values) value._key: value},
  );
}

/// Runs [body] within a scope which has access to the set of refs in [values].
R? runScopedGuarded<R>(
  R Function() body, {
  required void Function(Object error, StackTrace stack) onError,
  Set<ScopedRef<dynamic>> values = const {},
}) {
  return runZonedGuarded(
    body,
    onError,
    zoneValues: {for (final value in values) value._key: value},
  );
}
