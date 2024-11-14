# Shorebird Code Push

[![Discord](https://dcbadge.vercel.app/api/server/shorebird)](https://discord.gg/shorebird)

[![ci](https://github.com/shorebirdtech/updater/actions/workflows/main.yaml/badge.svg)](https://github.com/shorebirdtech/updater/actions/workflows/main.yaml)
[![codecov](https://codecov.io/gh/shorebirdtech/updater/branch/main/graph/badge.svg)](https://codecov.io/gh/shorebirdtech/updater)
[![License: MIT][license_badge]][license_link]

A Dart package for communicating with the [Shorebird](https://shorebird.dev)
Code Push Updater. Use this in your Shorebird app to:

- ✅ Get the currently installed patch version
- ✅ Check whether a new patch is available
- ✅ Download new patches

## Getting Started

If your Flutter app does not already use Shorebird, follow our
[Getting Started Guide](https://docs.shorebird.dev/) to add code push to your
app.

## Installation

```sh
flutter pub add shorebird_code_push
```

## Usage

After adding the package to your `pubspec.yaml`, you can use it in your app like
this:

```dart
// Import the library
import 'package:shorebird_code_push/shorebird_code_push.dart';

// Launch your app
void main() => runApp(const MyApp());

// [Other code here]

class _MyHomePageState extends State<MyHomePage> {
  // Create an instance of the updater class
  final updater = ShorebirdUpdater();

  @override
  void initState() {
    super.initState();

    // Get the current patch number and print it to the console.
    // It will be `null` if no patches are installed.
    updater.readCurrentPatch().then((currentPatch) {
      print('The current patch number is: ${currentPatch?.number}');
    });
  }

  Future<void> _checkForUpdates() async {
    // Check whether a new update is available.
    final status = await updater.checkForUpdate();

    if (status == UpdateStatus.outdated) {
      try {
        // Perform the update
        await updater.update();
      } on UpdateException catch (error) {
        // Handle any errors that occur while updating.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // [Other code here]
      ElevatedButton(
        child: Text('Check for update'),
        onPressed: _checkForUpdates,
      )
      // [Other code here]
    );
  }
}
```

See the example for a complete working app.

## Join us on Discord!

We have an active [Discord server](https://discord.gg/shorebird) where you can
ask questions and get help.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
