# Quick Reference: Self-Hosted Shorebird Configuration

## Environment Variables

### CLI Configuration
```bash
# Required: Your self-hosted API server URL
export SHOREBIRD_HOSTED_URL="https://your-api-server.com"

# Required for self-hosted: JWT token from your server's login endpoint
# Note: Use SHOREBIRD_API_TOKEN (not SHOREBIRD_TOKEN) for self-hosted deployments
export SHOREBIRD_API_TOKEN="your-jwt-token-from-login"
```

### Artifact Proxy Configuration
```bash
# Artifact manifest location
export ARTIFACT_MANIFEST_BASE_URL="https://your-storage.com/download.shorebird.dev"

# Flutter artifacts storage
export FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com"

# Shorebird artifacts storage
export SHOREBIRD_STORAGE_BASE_URL="https://your-storage.com"
```

### Server Configuration
```bash
# Required
export JWT_SECRET="your-secure-secret"
export S3_ACCESS_KEY="your-access-key"
export S3_SECRET_KEY="your-secret-key"

# Optional
export S3_ENDPOINT="localhost"
export S3_PORT="9000"
export S3_USE_SSL="false"
export S3_REGION="us-east-1"
export S3_BUCKET_RELEASES="shorebird-releases"
export S3_BUCKET_PATCHES="shorebird-patches"
```

## Project Configuration (shorebird.yaml)

```yaml
# App identifier
app_id: your-app-id

# Self-hosted API URL (overridden by SHOREBIRD_HOSTED_URL env var)
base_url: https://your-api-server.com

# Disable auto-updates (optional)
# auto_update: false

# Multiple flavors (optional)
# flavors:
#   development: dev-app-id
#   production: prod-app-id
```

## Configuration Priority

1. **Environment variables** (highest priority)
2. **shorebird.yaml** file
3. **Default values** (lowest priority)

## Quick Start Commands

```bash
# 1. Set up environment
export SHOREBIRD_HOSTED_URL="https://your-api-server.com"

# 2. Get authentication token from your server
TOKEN=$(curl -s -X POST https://your-api-server.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@localhost", "password": "admin123"}' | jq -r '.token')

# 3. Set the API token (use SHOREBIRD_API_TOKEN for self-hosted)
export SHOREBIRD_API_TOKEN="$TOKEN"

# 4. Initialize project
shorebird init

# 5. Create release
shorebird release android

# 6. Push update
shorebird patch android
```

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Shorebird     │────▶│   Your API      │────▶│   S3 Storage    │
│      CLI        │     │   Server        │     │   (MinIO/AWS)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│   Flutter App   │────▶│ Artifact Proxy  │
│  (with updater) │     │    Server       │
└─────────────────┘     └─────────────────┘
```

## See Also

- [SELF_HOSTED_GUIDE.md](./SELF_HOSTED_GUIDE.md) - Full documentation
- [packages/self_hosted_server](./packages/self_hosted_server) - Server template
