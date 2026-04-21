## Shorebird CodePush Protocol

The Shorebird CodePush Protocol is a Dart library which contains common interfaces used by Shorebird CodePush.

### Regenerating from the OpenAPI spec

Everything under `lib/src/` is generated from the public Shorebird
CodePush OpenAPI spec at [api.shorebird.dev/openapi.json](https://api.shorebird.dev/openapi.json)
(also served as [openapi.yaml](https://api.shorebird.dev/openapi.yaml)
for easier human review) by
[space_gen](https://github.com/eseidel/space_gen). To regenerate
against the latest published spec:

```sh
dart run packages/shorebird_code_push_protocol/tool/gen.dart \
  -i https://api.shorebird.dev/openapi.json \
  -o packages/shorebird_code_push_protocol
```

Hand-written files (`lib/extensions/`, `lib/shorebird_code_push_protocol.dart`)
are left untouched by the generator. The version of space_gen in use is
pinned in `pubspec.yaml`.
