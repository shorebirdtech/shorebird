# Artifact Proxy

This is a tool for proxying Flutter artifacts from a derived Flutter engine
revision back to the base Flutter engine revision. This is useful for
when you need to modify _some_ of the Flutter artifacts but not all of them.

This is a development tool which map requests to Google
Storage (either Shorebird's bucket or the official Flutter buckets).

## Usage

Uses `config.dart` to configure the engine revisions and artifact overrides.

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

## Updating config.dart

If run into 404s when fetching artifacts, ensure that the expected manifest
exists at
https://storage.googleapis.com/download.shorebird.dev/shorebird/$engineRevision/artifacts_manifest.yaml.

If it does, you may need to update the artifact list in `config.dart` and, if
the artifact is one we're providing, add it in `tool/generate_manifest.sh`

To do so, you will need to determine the artifact URLs. Follow these steps:

- Point Shorebird at the local proxy by setting `SHOREBIRD_DOWNLOAD_URL`:

  ```bash
  export SHOREBIRD_DOWNLOAD_URL=http://localhost:8080
  ```

  The CLI passes it to Flutter as `FLUTTER_STORAGE_BASE_URL`, and so do
  `third_party/flutter/bin/internal/shared.sh` and `bin/shorebird.ps1` on the
  first run of a Flutter revision.

- Modify flutter_tool used by Shorebird to allow downloads from insecure URLs:
  - shorebird\bin\cache\flutter\packages\flutter_tools\gradle\flutter.gradle
    ```diff
    rootProject.allprojects {
        repositories {
            maven {
                url repository
    +           allowInsecureProtocol true
            }
        }
    }
    ```
- Remove the flutter_tools snapshot

  ```bash
  cd bin/cache/flutter/bin/cache
  rm flutter_tools.s*
  ```

- Run a shorebird command (`shorebird run` works well)
- For each artifact that 404s, add a line to `packages\artifact_proxy\lib\config.dart`, following the conventions for capturing engine revisions and escaping relevant characters.

## Generating an `artifact_manifest.yaml`

To generate a new `artifact_manifest.yaml` for a specific flutter_revision use the following command:

```
./tools/generate_manifest.sh <flutter_engine_revision> > artifact_manifest.yaml
```

Then upload the `artifact_manifest.yaml` to `download.shorebird.dev/shorebird/<shorebird_engine_revision>/artifacts_manifest.yaml`
