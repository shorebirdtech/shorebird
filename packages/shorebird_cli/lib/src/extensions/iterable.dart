/// Provides the [containsAnyOf] method to all [Iterable]s.
extension ContainsAnyOf<T> on Iterable<T> {
  /// Returns `true` if any of the elements in [elements] are in this iterable.
  bool containsAnyOf(Iterable<T> elements) {
    for (final element in elements) {
      if (contains(element)) {
        return true;
      }
    }
    return false;
  }
}
