/// The deployment track to use when deploying to Shorebird's servers
extension type const DeploymentTrack(String value) {
  /// An internal track for validating changes.
  static const staging = DeploymentTrack('staging');

  /// A public track for publishing changes to a limited audience.
  static const beta = DeploymentTrack('beta');

  /// A public track for publishing changes to production.
  static const stable = DeploymentTrack('stable');

  /// The name of the channel associated with the track.
  String get channel => value;
}
