# Self-Hosted Shorebird Example

This example demonstrates how to configure a Flutter app to use a self-hosted Shorebird CodePush server.

## Setup

### 1. Start the Self-Hosted Server

First, start the self-hosted server with Docker:

```bash
cd packages/self_hosted_server
docker-compose up -d
```

Wait for services to start (check with `docker-compose logs -f`).

### 2. Get Authentication Token

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@localhost", "password": "admin123"}'
```

Save the returned token.

### 3. Create a Flutter App

```bash
flutter create my_app
cd my_app
```

### 4. Initialize Shorebird

Set environment variables and run shorebird init:

```bash
export SHOREBIRD_HOSTED_URL=http://localhost:8080
export SHOREBIRD_TOKEN=<your-token-from-step-2>

shorebird init
```

Or manually create `shorebird.yaml`:

```yaml
# shorebird.yaml
app_id: <your-app-id>
base_url: http://localhost:8080
```

### 5. Create a Release

```bash
export SHOREBIRD_HOSTED_URL=http://localhost:8080
export SHOREBIRD_TOKEN=<your-token>

shorebird release android
```

### 6. Push a Patch

Make changes to your app, then:

```bash
export SHOREBIRD_HOSTED_URL=http://localhost:8080
export SHOREBIRD_TOKEN=<your-token>

shorebird patch android
```

## Example shorebird.yaml

```yaml
# shorebird.yaml - Self-Hosted Configuration

# App ID (get this from your server or after running shorebird init)
app_id: <your-app-id>

# Your self-hosted server URL
base_url: http://localhost:8080

# Optional: Disable auto-updates and handle manually
# auto_update: false

# Optional: Multiple flavors
# flavors:
#   development: <dev-app-id>
#   production: <prod-app-id>
```

## Verifying the Setup

### Check API Health

```bash
curl http://localhost:8080/
```

Should return:
```json
{
  "name": "Shorebird Self-Hosted CodePush API",
  "version": "1.0.0"
}
```

### Check Authentication

```bash
curl -H "Authorization: Bearer <your-token>" \
  http://localhost:8080/api/v1/users/me
```

### List Your Apps

```bash
curl -H "Authorization: Bearer <your-token>" \
  http://localhost:8080/api/v1/apps
```

## MinIO Console

Access MinIO at http://localhost:9001 to view uploaded artifacts:
- Username: `minioadmin`
- Password: `minioadmin`

## Troubleshooting

### "Connection refused" error

Make sure services are running:
```bash
docker-compose ps
docker-compose logs api
```

### "Unauthorized" error

Check your token is valid:
```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@localhost", "password": "admin123"}'
```

### Bucket not found

MinIO buckets should be created automatically. Check:
```bash
docker-compose logs minio-setup
```

Manual creation:
```bash
docker run --rm -it --network host minio/mc \
  mc alias set local http://localhost:9000 minioadmin minioadmin
docker run --rm -it --network host minio/mc \
  mc mb local/shorebird-releases --ignore-existing
docker run --rm -it --network host minio/mc \
  mc mb local/shorebird-patches --ignore-existing
```

## Using shorebird_code_push Package

To manually control updates in your app:

```dart
import 'package:shorebird_code_push/shorebird_code_push.dart';

final codePush = ShorebirdCodePush();

// Check for updates
final isUpdateAvailable = await codePush.isNewPatchAvailableForDownload();

if (isUpdateAvailable) {
  await codePush.downloadUpdateIfAvailable();
  // Notify user to restart the app
}
```

## Production Considerations

1. **Use HTTPS**: Put a reverse proxy (nginx/Caddy) in front of the API
2. **Change default passwords**: Update JWT_SECRET and ADMIN_PASSWORD
3. **Use persistent volumes**: Ensure data survives container restarts
4. **Backup database**: The `data/database.json` file contains all metadata
5. **Monitor storage**: Keep an eye on MinIO disk usage
