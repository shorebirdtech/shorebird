# Artifact Proxy

This is a tool for proxying Flutter artifacts from a derived Flutter engine
revision back to the base Flutter engine revision. This is useful for
when you need to modify _some_ of the Flutter artifacts but not all of them.

This is a development tool which map requests to Google
Storage (either Shorebird's bucket or the official Flutter buckets).

## Usage

Uses `config.yaml` to configure the engine revisions and artifact overrides.

```bash
# Run locally with hot-reload enabled.
DEV=true dart --enable-vm-service run bin/server.dart
```

And then in a separate terminal:

```
FLUTTER_STORAGE_BASE_URL=http://localhost:8080 flutter precache -a
```

You should use a separate checkout of Flutter when running this, so you don't
poison the cache of your main Flutter checkout.
