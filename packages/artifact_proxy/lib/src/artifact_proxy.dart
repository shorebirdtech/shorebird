// ignore_for_file: avoid_print

import 'package:artifact_proxy/artifact_proxy.dart';
import 'package:artifact_proxy/config.dart';
import 'package:shelf/shelf.dart';

const String _explainerHtml = """
<html>
<head>
<title>Shorebird Artifact Proxy</title>
</head>
<body>
<p>
This server proxies requests for Flutter artifacts to the correct location,
depending on the engine revision.  Most artifacts are served from the standard
`download.flutter.io` location, but a few artifacts are served from Shorebird's
storage bucket to add support for code push.
</p>
<p>
See <a href='https://docs.shorebird.dev/architecture'>
https://docs.shorebird.dev/architecture</a> for more information.
</p>
<p>
Source code can be found here:
<a
href='https://github.com/shorebirdtech/shorebird/tree/main/packages/artifact_proxy'>
https://github.com/shorebirdtech/shorebird/tree/main/packages/artifact_proxy</a>
</p>
<p>
If you're seeing problems with your Shorebird install, or are interested in
replicating this proxy, please reach out to us over Discord.
<a href='https://shorebird.dev/contact'>https://shorebird.dev/contact</a>
</p>
</body>
</html>
""";

/// A [Handler] that proxies artifact requests to the correct location.
Handler artifactProxyHandler({required ArtifactManifestClient client}) {
  return (Request request) async {
    final path = request.url.path;
    if (path.isEmpty) {
      return Response.ok(
        _explainerHtml,
        headers: {'content-type': 'text/html'},
      );
    }

    RegExpMatch? engineArtifactMatch;
    for (final pattern in engineArtifactPatterns) {
      final match = RegExp(pattern).firstMatch(path);
      if (match != null && match.group(1) != null) {
        engineArtifactMatch = match;
        break;
      }
    }

    if (engineArtifactMatch != null) {
      final shorebirdEngineRevision = engineArtifactMatch.group(1)!;
      final ArtifactsManifest manifest;
      try {
        manifest = await client.getManifest(shorebirdEngineRevision);
      } catch (error) {
        return Response.notFound(
          'Failed to fetch manifest for $shorebirdEngineRevision\n$error',
        );
      }

      final normalizedPath = path.replaceAll(
        shorebirdEngineRevision,
        r'$engine',
      );

      final shouldOverride = manifest.artifactOverrides.contains(
        normalizedPath,
      );

      if (shouldOverride) {
        final location = getShorebirdArtifactLocation(
          artifactPath: normalizedPath,
          engine: shorebirdEngineRevision,
          bucket: manifest.storageBucket,
        );
        print('Shorebird engine artifact detected, forwarding to: $location');
        return Response.found(location);
      }

      final location = getFlutterArtifactLocation(
        artifactPath: normalizedPath,
        engine: manifest.flutterEngineRevision,
      );
      print('Flutter artifact detected, forwarding to: $location');
      return Response.found(location);
    }

    final isRecognizedFlutterArtifact = flutterArtifactPatterns.any(
      (pattern) => RegExp(pattern).hasMatch(path),
    );

    if (!isRecognizedFlutterArtifact) {
      return Response.notFound('Unrecognized artifact path: $path');
    }

    final location = getFlutterArtifactLocation(artifactPath: path);
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
