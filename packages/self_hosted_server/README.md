# Self-Hosted Shorebird Server

A self-hosted Shorebird CodePush API server built with [dart_frog](https://dartfrog.vgv.dev/).

## Features

- Full API compatibility with Shorebird CLI
- S3-compatible storage support (MinIO, AWS S3, etc.)
- Simple deployment and configuration

## Quick Start

### 1. Install dart_frog CLI

```bash
dart pub global activate dart_frog_cli
```

### 2. Configure Environment

Copy the example environment file and configure it:

```bash
cp .env.example .env
```

Edit `.env` with your settings:

```env
# Server Configuration
PORT=8080
HOST=0.0.0.0

# Database (implement your own adapter)
DATABASE_URL=postgresql://localhost:5432/shorebird

# S3 Storage Configuration
S3_ENDPOINT=localhost
S3_PORT=9000
S3_ACCESS_KEY=your_access_key
S3_SECRET_KEY=your_secret_key
S3_USE_SSL=false
S3_REGION=us-east-1
S3_BUCKET_RELEASES=shorebird-releases
S3_BUCKET_PATCHES=shorebird-patches

# JWT Secret for authentication
JWT_SECRET=your-secret-key-here
```

### 3. Start the Server

Development mode:
```bash
dart_frog dev
```

Production build:
```bash
dart_frog build
dart build/bin/server.dart
```

## API Endpoints

The server implements the Shorebird CodePush API:

### Users
- `GET /api/v1/users/me` - Get current user
- `POST /api/v1/users` - Create user

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
- `POST /api/v1/apps/:appId/releases/:releaseId/artifacts` - Create artifact

### Patches
- `GET /api/v1/apps/:appId/releases/:releaseId/patches` - List patches
- `POST /api/v1/apps/:appId/patches` - Create patch
- `POST /api/v1/apps/:appId/patches/:patchId/artifacts` - Create patch artifact
- `POST /api/v1/apps/:appId/patches/promote` - Promote patch

### Organizations
- `GET /api/v1/organizations` - List organizations

## Storage

The server uses S3-compatible storage for artifacts. You can use:

- **MinIO** (recommended for self-hosting)
- **AWS S3**
- **DigitalOcean Spaces**
- **Any S3-compatible provider**

### Setting up MinIO

```bash
docker run -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=admin \
  -e MINIO_ROOT_PASSWORD=password \
  minio/minio server /data --console-address ":9001"
```

## Docker Deployment

Build the Docker image:

```bash
docker build -t shorebird-server .
```

Run with Docker Compose:

```yaml
version: '3.8'
services:
  api:
    image: shorebird-server
    ports:
      - "8080:8080"
    environment:
      - S3_ENDPOINT=minio
      - S3_PORT=9000
      - S3_ACCESS_KEY=admin
      - S3_SECRET_KEY=password
    depends_on:
      - minio
      
  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      - MINIO_ROOT_USER=admin
      - MINIO_ROOT_PASSWORD=password
```

## License

This project is licensed under the MIT License.
