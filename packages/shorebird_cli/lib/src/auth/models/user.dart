/// {@template user}
/// A shorebird user account.
/// {@endtemplate}
class User {
  /// {@macro user}
  const User({required this.email});

  /// The user's email address.
  final String email;
}
