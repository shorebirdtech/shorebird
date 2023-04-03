# Artifact Proxy

This is a tool for proxying Flutter artifacts from a derived Flutter engine
revision back to the base Flutter engine revision. This is useful for
when you need to modify _some_ of the Flutter artifacts but not all of them.

This is a development tool which map requests to Google
Storage (either Shorebird's bucket or the official Flutter buckets).

## Status

Eventually we will need to support multiple mappings (presumably by generating
config files), right now this tool only supports mapping a single pair of
engine revisions.

## Usage

Uses `config.yaml` to configure the base and derived revisions. Eventually
this will also include a list of known artifacts to proxy, so we can be
explicit about what we're proxying.

```bash
# Run locally with hot-reload enabled.
dart --enable-vm-service run bin/server.dart --watch
```

You can also run it with `--record` to have it record the the artifact paths
it is proxying to the config.yaml file.

```bash
# Run locally with hot-reload and recordings enabled.
dart --enable-vm-service run bin/server.dart --watch --record
```

And then in a separate terminal:

```
FLUTTER_STORAGE_BASE_URL=http://localhost:8080 flutter precache -a
```

You should use a separate checkout of Flutter when running this, so you don't
poison the cache of your main Flutter checkout.
