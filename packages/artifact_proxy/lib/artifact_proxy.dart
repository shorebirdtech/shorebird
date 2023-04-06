// ignore_for_file: avoid_print

import 'package:collection/collection.dart';
import 'package:shelf/shelf.dart';

/// A [Handler] that proxies artifact requests to the correct location.
/// This is determined based on the [config].
Handler artifactProxyHandler({required Map<dynamic, dynamic> config}) {
  final engineMappings = config['engine_mappings'] as Map;
  final shorebirdEngineRevisions = engineMappings.keys.cast<String>();

  return (Request request) {
    final path = request.url.path;
    final shorebirdEngineRevision = shorebirdEngineRevisions.firstWhereOrNull(
      path.contains,
    );

    final normalizedPath = shorebirdEngineRevision != null
        ? path.replaceAll(shorebirdEngineRevision, r'$engine')
        : path;

    if (shorebirdEngineRevision == null) {
      final location = getFlutterArtifactLocation(artifactPath: normalizedPath);
      print('No engine revision detected, forwarding to: $location');
      return Response.found(location);
    }

    final engineMapping = engineMappings[shorebirdEngineRevision] as Map;
    final shorebirdOverrides =
        engineMapping['shorebird_artifact_overrides'] as List;
    final flutterEngineRevision =
        engineMapping['flutter_engine_revision'] as String;
    final shorebirdStorageBucket =
        engineMapping['shorebird_storage_bucket'] as String;
    final shouldOverride = shorebirdOverrides.contains(normalizedPath);

    if (shouldOverride) {
      final location = getShorebirdArtifactLocation(
        artifactPath: normalizedPath,
        engine: shorebirdEngineRevision,
        bucket: shorebirdStorageBucket,
      );
      print('Shorebird artifact detected, forwarding to: $location');
      return Response.found(location);
    }

    final location = getFlutterArtifactLocation(
      artifactPath: normalizedPath,
      engine: flutterEngineRevision,
    );
    print('Flutter artifact detected, forwarding to: $location');
    return Response.found(location);
  };
}

/// Returns the location of the artifact at [artifactPath] using the
/// specified [engine] revision for original Flutter artifacts.
String getFlutterArtifactLocation({
  required String artifactPath,
  String? engine,
}) {
  final adjustedPath = engine != null
      ? artifactPath.replaceAll(r'$engine', engine)
      : artifactPath;

  final isChromeInfra = adjustedPath.contains('flutter_infra_release/cipd');

  /// TODO(felangel): remove this after 3.8 is released.
  if (isChromeInfra) {
    return adjustedPath.replaceAll(
      'flutter_infra_release/cipd',
      'https://chrome-infra-packages.appspot.com/dl',
    );
  }

  return 'https://storage.googleapis.com/$adjustedPath';
}

/// Returns the location of the artifact at [artifactPath] using the
/// specified [engine] revision for Shorebird artifacts.
String getShorebirdArtifactLocation({
  required String artifactPath,
  required String engine,
  required String bucket,
}) {
  final adjustedPath = artifactPath.replaceAll(r'$engine', engine);
  return 'https://storage.googleapis.com/$bucket/$adjustedPath';
}
