/// The deployment track to use when deploying to Shorebird's servers
enum DeploymentTrack {
  /// An internal track for validating changes.
  staging('staging'),

  /// A public track for publishing changes to production.
  production('stable');

  const DeploymentTrack(this.channel);

  /// The name of the channel associated with the track.
  final String channel;
}
