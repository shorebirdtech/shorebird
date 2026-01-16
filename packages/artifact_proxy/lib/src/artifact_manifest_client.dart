import 'dart:io';

import 'package:artifact_proxy/artifact_proxy.dart';
import 'package:artifact_proxy/config.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:http/http.dart' as http;
import 'package:quiver/collection.dart';

/// {@template artifact_manifest_client}
/// A client that fetches [ArtifactsManifest]s from the shorebird storage bucket
/// and caches them in memory.
///
/// For self-hosted deployments, provide a custom [config] to point to your
/// own storage infrastructure.
/// {@endtemplate}
class ArtifactManifestClient {
  /// {@macro artifact_manifest_client}
  ArtifactManifestClient({
    http.Client? httpClient,
    ArtifactProxyConfig? config,
  }) : _httpClient = httpClient ?? http.Client(),
       _config = config ?? ArtifactProxyConfig.fromEnvironment();

  final http.Client _httpClient;
  final ArtifactProxyConfig _config;

  final _cache = LruMap<String, ArtifactsManifest>(maximumSize: 1000);

  /// Fetches the [ArtifactsManifest] for the provided [revision] from the
  /// shorebird storage bucket.
  Future<ArtifactsManifest> getManifest(String revision) async {
    if (_cache.containsKey(revision)) return _cache[revision]!;
    final manifest = await _fetchManifest(revision);
    _cache[revision] = manifest;
    return manifest;
  }

  Future<ArtifactsManifest> _fetchManifest(String revision) async {
    final url = Uri.parse(_config.getManifestUrl(revision));
    final response = await _httpClient.get(url);
    if (response.statusCode != HttpStatus.ok) {
      throw Exception('''
Failed to fetch artifacts manifest for revision $revision.
URL: $url
${response.statusCode} ${response.reasonPhrase}''');
    }

    return checkedYamlDecode(
      response.body,
      (m) => ArtifactsManifest.fromJson(m!),
    );
  }
}
