## Shorebird CodePush API Client

The Shorebird CodePush API Client is a Dart library which allows Dart applications to interact with the ShoreBird CodePush API.

### Installing

To get started, add the library to your `pubspec.yaml`:

```yaml
dependencies:
  shorebird_code_push_api_client:
    git:
      url: https://github.com/shorebirdtech/shorebird
      path: packages/shorebird_code_push_api_client
```

### Usage

```dart
void main() async {
    // Create an instance of the client.
    final client = ShorebirdCodePushApiClient();

    // Publish a new release.
    await client.createRelease('path/to/release');
}
```
