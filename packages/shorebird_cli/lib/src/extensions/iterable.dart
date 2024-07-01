/// Provides the [containsAnyOf] method to all [Iterable]s.
extension ContainsAnyOf<T> on Iterable<T> {
  /// Returns `true` if any of the elements in [elements] are in this iterable.
  bool containsAnyOf(Iterable<T> elements) => elements.any(contains);
}
