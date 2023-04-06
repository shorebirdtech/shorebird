/// A map of shorebird engine revision to the corresponding [EngineMapping].
typedef EngineMappings = Map<String, EngineMapping>;

/// {@template proxy_config}
/// Contains all the information needed to proxy requests.
/// {@endtemplate}
class ProxyConfig {
  /// {@macro proxy_config}
  const ProxyConfig({required this.engineMappings});

  /// The registered engine mappings.
  final EngineMappings engineMappings;
}

/// {@template engine_mapping}
/// Contains all the information needed to proxy requests for a specific
/// shorebird engine revision.
/// {@endtemplate}
class EngineMapping {
  /// {@macro engine_mapping}
  const EngineMapping({
    required this.flutterEngineRevision,
    required this.shorebirdStorageBucket,
    required this.shorebirdArtifactOverrides,
  });

  /// The flutter engine revision that this engine mapping is based on.
  final String flutterEngineRevision;

  /// The storage bucket that contains the shorebird artifacts.
  final String shorebirdStorageBucket;

  /// The list of shorebird artifacts that should be overridden.
  final Set<String> shorebirdArtifactOverrides;
}
