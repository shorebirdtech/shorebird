
<div align=center>
 <img src= "https://raw.githubusercontent.com/shorebirdtech/brand/904722544742c13348f1854a5cc45f4ed223cd17/logo-wordmark/logo_wordmark.png" alt="Shorebird logo">
<h1>Code Push </h1>

[![Discord](https://img.shields.io/discord/1030243211995791380?style=for-the-badge&logo=discord&color=blue)](https://discord.gg/shorebird)

[![ci](https://github.com/shorebirdtech/updater/actions/workflows/main.yaml/badge.svg)](https://github.com/shorebirdtech/updater/actions/workflows/main.yaml)
[![codecov](https://codecov.io/gh/shorebirdtech/updater/branch/main/graph/badge.svg)](https://codecov.io/gh/shorebirdtech/updater)
[![License: MIT][license_badge]][license_link]

<p align=center> Instantly push updates to your Flutter app without lengthy app store review cycles. </p>

[Website](https://shorebird.dev?utm_source=pubdev) • [Docs](https://docs.shorebird.dev?utm_source=pubdev) • [X](https://x.com/shorebirddev)• [YouTube](https://www.youtube.com/@shorebird) 
 </div>

This Dart package communicates with the [Shorebird](https://shorebird.dev) Code Push Updater to:

- ✅ Get the currently installed patch version
- ✅ Check whether a new patch is available
- ✅ Download new patches

## Demo 
Explore this [interactive demo](https://docs.shorebird.dev/code-push/?utm_source=pubdev) to learn more

## Getting Started

If your Flutter app does not already use Shorebird, follow our
[Getting Started Guide]([https://docs.shorebird.dev/getting-started/?utm_source=pubdev]) to add code push to your
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

### Tracks

Shorebird supports publishing patches to different tracks, which can be
used to target different segments of your user base. See the [percentage based rollout 
guide](https://docs.shorebird.dev/code-push/guides/percentage-based-rollouts/) for implementation details.

You must first publish a patch to a specific track (patches are published to the
`stable` track by default). To publish a patch to a different track, update your
patch command to use the `--track` argument:

```sh
shorebird patch android --track beta
```

(We're just using Android for this example. Tracks are supported on all
platforms).

To check for updates on a given track, simply pass an `UpdateTrack` to
`checkForUpdate` and `update`. For example, this:

```dart
final status = await updater.checkForUpdate();
if (status == UpdateStatus.outdated) {
  await updater.update();
}
```

Becomes this:

```dart
final status = await updater.checkForUpdate(track: UpdateTrack.beta);
if (status == UpdateStatus.outdated) {
  await updater.update(track: UpdateTrack.beta);
}
```

You can also use custom track names. When creating a patch, specify a track name
like this:

```sh
shorebird patch android --track my-custom-track
```

And:

```dart
const track = UpdateTrack('my-custom-track');
final status = await updater.checkForUpdate(track: track);
if (status == UpdateStatus.outdated) {
  await updater.update(track: track);
}
```

## Join us on Discord!

We have an active [Discord server](https://discord.gg/shorebird) where you can
ask questions and get help.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
