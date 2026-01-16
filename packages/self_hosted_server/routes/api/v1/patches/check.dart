import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final request = PatchCheckRequest.fromJson(body);

    // 1. Find App
    // Note: The 'apps' table uses the UUID string as the primary key 'id'.
    // The request.appId contains this UUID.
    final apps = database.select('apps', where: {'id': request.appId});
    if (apps.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'message': 'App not found'},
      );
    }
    final app = apps.first;

    // 2. Find Release
    // Releases link to app via 'app_id', which stores the UUID string.
    final releases = database.select(
      'releases',
      where: {'app_id': app['id'], 'version': request.releaseVersion},
    );
    if (releases.isEmpty) {
      return Response.json(
        body: const PatchCheckResponse(patchAvailable: false).toJson(),
      );
    }
    final release = releases.first;

    // 3. Find Channel
    final channels = database.select(
      'channels',
      where: {'app_id': app['id'], 'name': request.channel},
    );
    if (channels.isEmpty) {
      return Response.json(
        body: const PatchCheckResponse(patchAvailable: false).toJson(),
      );
    }
    final channel = channels.first;

    // 4. Find all patches for this release that are promoted to this channel
    // and have number > request.patchNumber
    final patches = database.select(
      'patches',
      where: {'release_id': release['id']},
    );
    final channelPatches = database.select(
      'channel_patches',
      where: {'channel_id': channel['id']},
    );

    // Set of patch IDs in this channel
    final channelPatchIds = channelPatches.map((cp) => cp['patch_id']).toSet();

    // Filter patches
    final availablePatches = patches.where((p) {
      final patchNumber = p['number'] as int;
      return channelPatchIds.contains(p['id']) &&
          patchNumber > (request.patchNumber ?? 0);
    }).toList();

    if (availablePatches.isEmpty) {
      return Response.json(
        body: const PatchCheckResponse(patchAvailable: false).toJson(),
      );
    }

    // Sort descending by number
    availablePatches.sort(
      (a, b) => (b['number'] as int).compareTo(a['number'] as int),
    );
    final latestPatch = availablePatches.first;

    // 5. Get Artifact
    final artifacts = database.select(
      'patch_artifacts',
      where: {'patch_id': latestPatch['id']},
    );

    // Filter by platform and arch
    final platformName = request.platform.name;

    Map<String, dynamic>? artifact;
    for (final a in artifacts) {
      if (a['platform'] == platformName && a['arch'] == request.arch) {
        artifact = a;
        break;
      }
    }

    if (artifact == null) {
      return Response.json(
        body: const PatchCheckResponse(patchAvailable: false).toJson(),
      );
    }

    // 6. Generate Download URL
    // Use the proxy download URL to avoid S3 signature issues
    var downloadUrl = artifact['url'] as String;
    if (artifact['storage_path'] != null) {
        final storagePath = artifact['storage_path'] as String;
        // Construct URL pointing to our own API
        // Format: /api/v1/artifacts/{bucket}/{path}
        final protocol = config.s3UseSSL ? 'https' : 'http';
        final host =config.host == '0.0.0.0' ? config.s3PublicEndpoint : config.host; // Use public endpoint IP for API construction if host is binding to all interfaces
        final port = config.port;
        
        // Actually, we should just use the same base URL as the current request, 
        // but since we are behind a potential reverse proxy or docker networking, 
        // let's construct it from known public config.
        
        // Using s3PublicEndpoint (which is the computer IP) and server PORT (8080)
        // ensures the client stays on the same verified network path.
        // We MUST encode the storagePath because it contains slashes, and we want
        // it to be treated as a single path segment by the artifacts route.
        downloadUrl = 'http://${config.s3PublicEndpoint}:${config.port}/api/v1/artifacts/${config.s3BucketPatches}/${Uri.encodeComponent(storagePath)}';
    }

    return Response.json(
      body: PatchCheckResponse(
        patchAvailable: true,
        patch: PatchCheckMetadata(
          number: latestPatch['number'] as int,
          downloadUrl: downloadUrl,
          hash: artifact['hash'] as String,
          hashSignature:
              null, // Optional signature, not yet implemented in self-hosted
        ),
      ).toJson(),
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'Invalid request: $e'},
    );
  }
}
