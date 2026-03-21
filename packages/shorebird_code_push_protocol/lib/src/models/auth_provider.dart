/// The authentication provider used to sign in the user.
enum AuthProvider {
  /// The user authenticated using their Google account with our GCP project.
  google('Google'),

  /// The user authenticated with their Azure/Entra account.
  microsoft('Microsoft'),

  /// The user authenticated via Shorebird's own auth service.
  shorebird('Shorebird');

  const AuthProvider(this.displayName);

  /// The user-friendly display name for the authentication provider.
  final String displayName;
}
