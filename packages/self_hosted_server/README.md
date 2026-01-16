# Self-Hosted Shorebird CodePush Server

A self-hosted Shorebird CodePush API server built with [dart_frog](https://dartfrog.vgv.dev/).

## Features

- ✅ Full API compatibility with Shorebird CLI
- ✅ S3-compatible storage support (MinIO, AWS S3, etc.)
- ✅ JWT-based authentication
- ✅ JSON file database (production-ready PostgreSQL coming soon)
- ✅ Docker Compose setup for easy deployment

## Quick Start with Docker

### 1. Clone and Navigate

```bash
cd packages/self_hosted_server
```

### 2. Start Services

```bash
docker-compose up -d
```

This starts:
- **API Server** on port 8080
- **MinIO** (S3-compatible storage) on ports 9000 (API) and 9001 (Console)

### 3. Default Credentials

**API Server:**
- Email: `admin@localhost`
- Password: `admin123`

**MinIO Console** (http://localhost:9001):
- Username: `minioadmin`
- Password: `minioadmin`

## Development Setup

### 1. Install dart_frog CLI

```bash
dart pub global activate dart_frog_cli
```

### 2. Start MinIO (for storage)

```bash
docker run -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio server /data --console-address ":9001"
```

### 3. Configure Environment

```bash
cp .env.example .env
# Edit .env with your settings
```

### 4. Run the Server

```bash
dart_frog dev
```

## Using with Shorebird CLI

### 1. Get Authentication Token

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@localhost", "password": "admin123"}'
```

Response:
```json
{
  "token": "your-jwt-token",
  "user": {"id": 1, "email": "admin@localhost", "display_name": "Admin"}
}
```

### 2. Configure Your Flutter Project

Add to `shorebird.yaml`:
```yaml
app_id: your-app-id
base_url: http://localhost:8080
```

Or set environment variable:
```bash
export SHOREBIRD_HOSTED_URL=http://localhost:8080
```

### 3. Use Shorebird CLI

```bash
# Set the API token (JWT from login response)
export SHOREBIRD_API_TOKEN=your-jwt-token

# Set the host URL
export SHOREBIRD_HOSTED_URL=http://localhost:8080

# Initialize app
shorebird init

# Create release
shorebird release android

# Push patch
shorebird patch android
```

**Note:** Use `SHOREBIRD_API_TOKEN` (not `SHOREBIRD_TOKEN`) for self-hosted deployments. This bypasses OAuth and uses your JWT directly.

## API Endpoints

### Authentication
- `POST /api/v1/auth/register` - Register new user
- `POST /api/v1/auth/login` - Login and get JWT token

### Users
- `GET /api/v1/users/me` - Get current user
- `POST /api/v1/users` - Update user

### Organizations
- `GET /api/v1/organizations` - List organizations

### Apps
- `GET /api/v1/apps` - List apps
- `POST /api/v1/apps` - Create app
- `DELETE /api/v1/apps/:appId` - Delete app

### Channels
- `GET /api/v1/apps/:appId/channels` - List channels
- `POST /api/v1/apps/:appId/channels` - Create channel

### Releases
- `GET /api/v1/apps/:appId/releases` - List releases
- `POST /api/v1/apps/:appId/releases` - Create release
- `PATCH /api/v1/apps/:appId/releases/:releaseId` - Update release

### Artifacts
- `GET /api/v1/apps/:appId/releases/:releaseId/artifacts` - List artifacts
- `POST /api/v1/apps/:appId/releases/:releaseId/artifacts` - Upload artifact

### Patches
- `GET /api/v1/apps/:appId/releases/:releaseId/patches` - List patches
- `POST /api/v1/apps/:appId/patches` - Create patch
- `POST /api/v1/apps/:appId/patches/:patchId/artifacts` - Upload patch artifact
- `POST /api/v1/apps/:appId/patches/promote` - Promote patch to channel

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PORT` | No | `8080` | Server port |
| `HOST` | No | `0.0.0.0` | Server host |
| `JWT_SECRET` | **Yes** | - | Secret for JWT tokens |
| `S3_ENDPOINT` | **Yes** | - | S3 endpoint hostname |
| `S3_PORT` | No | `9000` | S3 port |
| `S3_ACCESS_KEY` | **Yes** | - | S3 access key |
| `S3_SECRET_KEY` | **Yes** | - | S3 secret key |
| `S3_USE_SSL` | No | `false` | Use SSL for S3 |
| `S3_REGION` | No | `us-east-1` | S3 region |
| `S3_BUCKET_RELEASES` | No | `shorebird-releases` | Bucket for releases |
| `S3_BUCKET_PATCHES` | No | `shorebird-patches` | Bucket for patches |
| `ADMIN_EMAIL` | No | `admin@localhost` | Default admin email |
| `ADMIN_PASSWORD` | No | `admin123` | Default admin password |

## Production Deployment

### 1. Generate Secure Secrets

```bash
# Generate JWT secret
openssl rand -hex 32
```

### 2. Update docker-compose.yml

```yaml
environment:
  - JWT_SECRET=<your-generated-secret>
  - ADMIN_PASSWORD=<strong-password>
  - S3_ACCESS_KEY=<s3-access-key>
  - S3_SECRET_KEY=<s3-secret-key>
```

### 3. Use External S3 (Optional)

For AWS S3:
```yaml
environment:
  - S3_ENDPOINT=s3.amazonaws.com
  - S3_PORT=443
  - S3_USE_SSL=true
  - S3_REGION=us-east-1
  - S3_ACCESS_KEY=<aws-access-key>
  - S3_SECRET_KEY=<aws-secret-key>
```

### 4. Add Reverse Proxy (Recommended)

Use nginx or Caddy for HTTPS termination.

## Data Storage

- **Database**: JSON file stored in `data/database.json`
- **Artifacts**: Stored in S3-compatible storage

## License

MIT License
