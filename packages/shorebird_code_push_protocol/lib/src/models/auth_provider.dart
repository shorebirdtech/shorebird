/// The authentication provider used to sign in the user.
enum AuthProvider {
  /// The user authenticated using their Google account with our GCP project.
  google,

  /// The user authenticated with their Azure/Entra account.
  microsoft,
}
