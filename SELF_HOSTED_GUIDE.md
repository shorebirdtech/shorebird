# Self-Hosted Shorebird Guide

This document describes how to set up a self-hosted Shorebird Code Push solution with a custom dart_frog server and S3-compatible storage.

## Architecture Overview

Shorebird consists of several key components:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLIENT SIDE                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  shorebird_cli          - Command-line tool for developers                   │
│  shorebird_code_push_client - Dart library to interact with CodePush API     │
│  Flutter SDK (patched)  - Custom Flutter SDK with code push support          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SERVER SIDE                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  API Server             - Main backend (needs to be implemented)             │
│  artifact_proxy         - Proxies Flutter artifact downloads                 │
│  Storage (GCS/S3)       - Stores release and patch artifacts                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Files for Customization

### 1. Host URL Configuration

The host URL can be configured in multiple ways:

#### a) Environment Variable (CLI)
```bash
export SHOREBIRD_HOSTED_URL="https://your-server.com"
```

**File:** `packages/shorebird_cli/lib/src/shorebird_env.dart` (lines 231-243)
```dart
Uri? get hostedUri {
  try {
    final baseUrl =
        platform.environment['SHOREBIRD_HOSTED_URL'] ??
        getShorebirdYaml()?.baseUrl;
    return baseUrl == null ? null : Uri.tryParse(baseUrl);
  } on Exception {
    return null;
  }
}
```

#### b) Project Configuration (shorebird.yaml)
```yaml
# shorebird.yaml
app_id: your-app-id
base_url: https://your-server.com  # Custom server URL
```

**File:** `packages/shorebird_cli/lib/src/config/shorebird_yaml.dart`
```dart
class ShorebirdYaml {
  const ShorebirdYaml({
    required this.appId,
    this.flavors,
    this.baseUrl,        // <-- Custom base URL field
    this.autoUpdate,
  });
  
  final String? baseUrl;
  // ...
}
```

### 2. Default API URL

**File:** `packages/shorebird_code_push_client/lib/src/code_push_client.dart` (line 98)
```dart
CodePushClient({
  http.Client? httpClient,
  Uri? hostedUri,
  Map<String, String>? customHeaders,
}) : _httpClient = _CodePushHttpClient(httpClient ?? http.Client(), {
       ...standardHeaders,
       ...?customHeaders,
     }),
     hostedUri = hostedUri ?? Uri.https('api.shorebird.dev'); // <-- Default URL
```

### 3. Artifact Proxy Configuration

**File:** `packages/artifact_proxy/lib/src/artifact_manifest_client.dart` (lines 30-34)
```dart
Future<ArtifactsManifest> _fetchManifest(String revision) async {
  final url = Uri.parse(
    'https://storage.googleapis.com/download.shorebird.dev/shorebird/$revision/artifacts_manifest.yaml',
  );
  // ...
}
```

**File:** `packages/artifact_proxy/lib/src/artifact_proxy.dart` (lines 113-133)
```dart
/// Standard Flutter artifacts location
String getFlutterArtifactLocation({
  required String artifactPath,
  String? engine,
}) {
  final adjustedPath = engine != null
      ? artifactPath.replaceAll(r'$engine', engine)
      : artifactPath;
  return 'https://storage.googleapis.com/$adjustedPath'; // <-- GCS URL
}

/// Shorebird-specific artifacts location  
String getShorebirdArtifactLocation({
  required String artifactPath,
  required String engine,
  required String bucket,
}) {
  final adjustedPath = artifactPath.replaceAll(r'$engine', engine);
  return 'https://storage.googleapis.com/$bucket/$adjustedPath'; // <-- GCS URL
}
```

## Implementation Steps

### Step 1: Create Self-Hosted Configuration

Create a new configuration file for self-hosted settings:

**File:** `packages/shorebird_cli/lib/src/config/self_hosted_config.dart`
```dart
import 'dart:io';
import 'package:json_annotation/json_annotation.dart';

part 'self_hosted_config.g.dart';

@JsonSerializable()
class SelfHostedConfig {
  const SelfHostedConfig({
    required this.apiUrl,
    this.artifactStorageUrl,
    this.artifactProxyUrl,
  });
  
  /// The URL of your self-hosted API server
  final String apiUrl;
  
  /// The URL of your S3-compatible storage (e.g., MinIO)
  final String? artifactStorageUrl;
  
  /// The URL of your artifact proxy server
  final String? artifactProxyUrl;
  
  factory SelfHostedConfig.fromJson(Map<String, dynamic> json) =>
      _$SelfHostedConfigFromJson(json);
  
  Map<String, dynamic> toJson() => _$SelfHostedConfigToJson(this);
  
  /// Load configuration from environment or config file
  static SelfHostedConfig? load() {
    // Priority: Environment variables > Config file
    final apiUrl = Platform.environment['SHOREBIRD_API_URL'];
    if (apiUrl != null) {
      return SelfHostedConfig(
        apiUrl: apiUrl,
        artifactStorageUrl: Platform.environment['SHOREBIRD_STORAGE_URL'],
        artifactProxyUrl: Platform.environment['SHOREBIRD_PROXY_URL'],
      );
    }
    return null;
  }
}
```

### Step 2: Modify the CodePush Client

Update the client to support custom storage URLs:

**File:** `packages/shorebird_code_push_client/lib/src/code_push_client.dart`
```dart
class CodePushClient {
  CodePushClient({
    http.Client? httpClient,
    Uri? hostedUri,
    Uri? storageUri,  // <-- Add storage URL parameter
    Map<String, String>? customHeaders,
  }) : _httpClient = _CodePushHttpClient(httpClient ?? http.Client(), {
         ...standardHeaders,
         ...?customHeaders,
       }),
       hostedUri = hostedUri ?? Uri.https('api.shorebird.dev'),
       storageUri = storageUri ?? Uri.https('storage.googleapis.com');
  
  final Uri storageUri;  // <-- Add storage URL field
  // ...
}
```

### Step 3: Create dart_frog Server Template

Create a template for the self-hosted API server:

**Directory:** `packages/self_hosted_server/`

The server needs to implement these API endpoints (from `shorebird_code_push_protocol`):

```
GET  /api/v1/users/me                              - Get current user
POST /api/v1/users                                 - Create user
GET  /api/v1/apps                                  - List apps
POST /api/v1/apps                                  - Create app
DELETE /api/v1/apps/:appId                         - Delete app
GET  /api/v1/apps/:appId/channels                  - List channels
POST /api/v1/apps/:appId/channels                  - Create channel
GET  /api/v1/apps/:appId/releases                  - List releases
POST /api/v1/apps/:appId/releases                  - Create release
PATCH /api/v1/apps/:appId/releases/:releaseId      - Update release status
GET  /api/v1/apps/:appId/releases/:releaseId/artifacts - Get release artifacts
POST /api/v1/apps/:appId/releases/:releaseId/artifacts - Create release artifact
GET  /api/v1/apps/:appId/releases/:releaseId/patches   - Get patches
POST /api/v1/apps/:appId/patches                   - Create patch
POST /api/v1/apps/:appId/patches/:patchId/artifacts    - Create patch artifact
POST /api/v1/apps/:appId/patches/promote           - Promote patch
GET  /api/v1/organizations                         - List organizations
GET  /api/v1/diagnostics/gcp_upload                - Get upload test URL
GET  /api/v1/diagnostics/gcp_download              - Get download test URL
```

### Step 4: S3 Storage Abstraction

Create storage abstraction for artifact uploads:

**File:** `packages/self_hosted_server/lib/src/storage/storage_provider.dart`
```dart
abstract class StorageProvider {
  /// Upload a file and return the public URL
  Future<String> uploadArtifact({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
  });
  
  /// Generate a signed upload URL for direct client uploads
  Future<String> getSignedUploadUrl({
    required String bucket,
    required String path,
    Duration expiry = const Duration(hours: 1),
  });
  
  /// Generate a signed download URL
  Future<String> getSignedDownloadUrl({
    required String bucket,
    required String path,
    Duration expiry = const Duration(hours: 1),
  });
  
  /// Delete an artifact
  Future<void> deleteArtifact({
    required String bucket,
    required String path,
  });
}
```

**File:** `packages/self_hosted_server/lib/src/storage/s3_storage_provider.dart`
```dart
import 'package:minio/minio.dart';

class S3StorageProvider implements StorageProvider {
  S3StorageProvider({
    required String endpoint,
    required String accessKey,
    required String secretKey,
    this.useSSL = true,
    this.region = 'us-east-1',
  }) : _minio = Minio(
         endPoint: endpoint,
         accessKey: accessKey,
         secretKey: secretKey,
         useSSL: useSSL,
         region: region,
       );
  
  final Minio _minio;
  final bool useSSL;
  final String region;
  
  @override
  Future<String> uploadArtifact({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
  }) async {
    await _minio.putObject(
      bucket,
      path,
      Stream.value(bytes),
      size: bytes.length,
    );
    return getPublicUrl(bucket, path);
  }
  
  @override
  Future<String> getSignedUploadUrl({
    required String bucket,
    required String path,
    Duration expiry = const Duration(hours: 1),
  }) async {
    return await _minio.presignedPutObject(bucket, path, expires: expiry.inSeconds);
  }
  
  @override
  Future<String> getSignedDownloadUrl({
    required String bucket,
    required String path,
    Duration expiry = const Duration(hours: 1),
  }) async {
    return await _minio.presignedGetObject(bucket, path, expires: expiry.inSeconds);
  }
  
  String getPublicUrl(String bucket, String path) {
    final protocol = useSSL ? 'https' : 'http';
    return '$protocol://${_minio.endPoint}/$bucket/$path';
  }
  
  @override
  Future<void> deleteArtifact({
    required String bucket,
    required String path,
  }) async {
    await _minio.removeObject(bucket, path);
  }
}
```

### Step 5: Modify Artifact Proxy for Self-Hosted

Update the artifact proxy to support custom storage URLs:

**File:** `packages/artifact_proxy/lib/config.dart` (add at the end)
```dart
/// Configuration for self-hosted artifact storage
class ArtifactProxyConfig {
  const ArtifactProxyConfig({
    this.manifestBaseUrl = 'https://storage.googleapis.com/download.shorebird.dev',
    this.flutterStorageBaseUrl = 'https://storage.googleapis.com',
    this.shorebirdStorageBaseUrl = 'https://storage.googleapis.com',
  });
  
  final String manifestBaseUrl;
  final String flutterStorageBaseUrl;
  final String shorebirdStorageBaseUrl;
  
  factory ArtifactProxyConfig.fromEnvironment() {
    return ArtifactProxyConfig(
      manifestBaseUrl: Platform.environment['ARTIFACT_MANIFEST_BASE_URL'] 
          ?? 'https://storage.googleapis.com/download.shorebird.dev',
      flutterStorageBaseUrl: Platform.environment['FLUTTER_STORAGE_BASE_URL']
          ?? 'https://storage.googleapis.com',
      shorebirdStorageBaseUrl: Platform.environment['SHOREBIRD_STORAGE_BASE_URL']
          ?? 'https://storage.googleapis.com',
    );
  }
}
```

## Environment Variables Summary

| Variable | Description | Default |
|----------|-------------|---------|
| `SHOREBIRD_HOSTED_URL` | Main API server URL | `https://api.shorebird.dev` |
| `SHOREBIRD_API_URL` | Alternative API URL config | - |
| `SHOREBIRD_STORAGE_URL` | S3-compatible storage URL | - |
| `SHOREBIRD_PROXY_URL` | Artifact proxy URL | - |
| `ARTIFACT_MANIFEST_BASE_URL` | Manifest download URL | GCS URL |
| `FLUTTER_STORAGE_BASE_URL` | Flutter artifacts storage | GCS URL |
| `SHOREBIRD_STORAGE_BASE_URL` | Shorebird artifacts storage | GCS URL |

## Quick Start for Self-Hosted Setup

### 1. Configure the CLI

```bash
# Set environment variables
export SHOREBIRD_HOSTED_URL="https://your-api-server.com"

# Or add to shorebird.yaml in your project
echo "base_url: https://your-api-server.com" >> shorebird.yaml
```

### 2. Deploy the Server

```bash
# Clone the repository
cd packages/self_hosted_server

# Configure environment
cp .env.example .env
# Edit .env with your settings

# Run with dart_frog
dart_frog dev
```

### 3. Configure S3 Storage (MinIO example)

```bash
# Run MinIO
docker run -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=admin \
  -e MINIO_ROOT_PASSWORD=password \
  minio/minio server /data --console-address ":9001"

# Create buckets
mc alias set local http://localhost:9000 admin password
mc mb local/shorebird-releases
mc mb local/shorebird-patches
```

### 4. Configure Artifact Proxy

```bash
export SHOREBIRD_STORAGE_BASE_URL="http://localhost:9000"
cd packages/artifact_proxy
dart run bin/main.dart
```

## Authentication

The original Shorebird uses Google OAuth for authentication. For self-hosted, you have options:

1. **Use existing OAuth providers** - Keep Google/Microsoft OAuth
2. **Custom authentication** - Implement your own auth in the dart_frog server
3. **API tokens** - Use simple API key authentication

Modify `packages/shorebird_cli/lib/src/auth/auth.dart` to support custom authentication.

## Database Schema

Your self-hosted server will need a database with tables for:

- `users` - User accounts
- `organizations` - Organization groupings
- `organization_memberships` - User-organization relationships
- `apps` - Application records
- `channels` - Deployment channels
- `releases` - Release versions
- `release_artifacts` - Release artifact metadata
- `patches` - Patch records
- `patch_artifacts` - Patch artifact metadata

See `packages/shorebird_code_push_protocol/lib/src/models/` for model definitions.

## Next Steps

1. Fork this repository
2. Implement the dart_frog server using the protocol models
3. Configure S3-compatible storage (MinIO, AWS S3, etc.)
4. Update artifact proxy configuration
5. Test the full workflow: init → release → patch
