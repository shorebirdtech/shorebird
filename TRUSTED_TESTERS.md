# Trusted Testers

While this document is public, access to Shorebird services are not yet
generally available. We're running a trusted tester program with a limited
number of users to ensure that we're building the right thing and that it's
stable for general use.

If you'd like to be a part of the program, please fill out this form:
https://forms.gle/T7x5h5bb6bMBB7hUA

## Welcome!

If you're joining the trusted tester program, welcome! Thank you for your help
making Shorebird a reality.

You should have received an API key in the mail. You will need it as part
of the login process for the `shorebird` command-line tool to work.

## Our goal

Our goal with this Trusted Tester program is to shake out bugs and ensure that
we are building things people want. We _want_ your feedback. We _want_ you to
break things. We _want_ you to tell us what you want to see next. We're
already a default-public company, but we intend to be even more open with you
and will be shipping your regular updates during the program, responding to
your feedback.

Filing [issues](https://github.com/shorebirdtech/shorebird/issues) is a good way
to provide feedback. Feedback via Discord is also welcome.

Our guiding principle in creating this first release has been "first, do no harm".
It should be the case that using Shorebird is never worse than not using Shorebird.
It is still possible using this early version of Shorebird could break your app in
the wild. If you believe that's the case, please reach out, we're here to help.

## What works today

You can build and deploy new (release) versions of your app to all Android arm64
users ([issue](https://github.com/shorebirdtech/shorebird/issues/119)) via
`shorebird` command line from an arm64 Mac (M1 or M2,
[issue](https://github.com/shorebirdtech/shorebird/issues/37))
computer.

All users will synchronously update to the new version on next launch
(no control over this behavior yet,
[issue](https://github.com/shorebirdtech/shorebird/issues/127)).

Basic access to the updater through package:dart_bindings (unpublished).
https://github.com/shorebirdtech/shorebird/tree/main/updater/dart_bindings

Shorebird command line can show a list of what apps and app versions you've
associated with your account and what patches you've pushed to those apps.
https://github.com/shorebirdtech/shorebird/tree/main/packages/shorebird_cli

## What doesn't yet

Limited platform support:

- Only Arm64 platform, no non-Android or non-arm64 support.
- Windows, Linux ([issue](https://github.com/shorebirdtech/shorebird/issues/37))

No support for:

- Flutter channels (only latest stable is supported)
- Rollbacks ([issue](https://github.com/shorebirdtech/shorebird/issues/126))
- Shorebird channels (staged rollouts of patches) [issue](https://github.com/shorebirdtech/shorebird/issues/110)
- Percentage based rollouts
- Async updates / downloads [issue](https://github.com/shorebirdtech/shorebird/issues/123)
- Analytics
- Web interface
- CI/CD (GitHub Actions, etc.) integration
- Patch signing [issue](https://github.com/shorebirdtech/shorebird/issues/112)
- Sign-in via something other than an API key (e.g. OAuth) [issue](https://github.com/shorebirdtech/shorebird/issues/133)

## Installing Shorebird command line

These instructions assume you already have Flutter installed on the machine
and `flutter` and `dart` in your path:
https://docs.flutter.dev/get-started/install

Shorebird also currently only works with the latest Flutter stable version:

```
flutter channel stable
flutter upgrade
```

Once you have Flutter installed, the next is to install the `shorebird` command-line tool.

```bash
curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh -sSf | sh
```

More information: https://github.com/shorebirdtech/install/blob/main/README.md

## Using Shorebird code push

The first use-case we're targeting is one of deploying updates to a small
set of users. If you already have a Flutter app with a small install base, you
can convert it to Shorebird in a few steps:

1. The first step to using Shorebird is to login. `shorebird login` will prompt
   for your API key, which you should have recieved in email. Many `shorebird`
   commands do not require login, but it's best to just do it first to avoid
   unexpected errors later. Your login credentials are stored in
   `~/Library/Application Support/shorebird/shorebird-session.json`.

2. Once you're logged in, you can use `shorebird init`. This needs to be run
   within the directory of your Flutter app, it reads and writes your `pubspec.yaml`
   and will write out a new `shorebird.yaml` file.

`shorebird init` does three things:

1. Tells Shorebird that your app exists (e.g. so it can hold patches to it
   and vend them to devices when asked).
2. Creates a `shorebird.yaml` file to your project. `shorebird.yaml` contains
   the app_id for your app, which is the unique identifier the app will send to
   Shorebird servers to identify which application to pull updates for.
3. Finally, `shorebird init` also adds the `shorebird.yaml` to the assets
   section of your `pubspec.yaml` file, ensuring `shorebird.yaml` is bundled
   into your app's assets.

You can go ahead and commit these changes, they will be innocuous even if you
don't end up using Shorebird with this application.

If you don't want to try this on your main application yet, any Flutter app,
including the default Flutter counter works too, e.g.

```
flutter create shorebird_test
cd shorebird_test
% shorebird init
? How should we refer to this app? (shorebird_test) shorebird_test
✓ Initialized Shorebird (38ms)

🐦 Shorebird initialized successfully!

✅ A shorebird app has been created.
✅ A "shorebird.yaml" has been created.
✅ The "pubspec.yaml" has been updated to include "shorebird.yaml" as an asset.

Reference the following commands to get started:

🚙 To run your project use: "shorebird run".
📦 To build your project use: "shorebird build".
🚀 To push an update use: "shorebird patch".

For more information about Shorebird, visit https://shorebird.dev
```

3.  Typical development usage will involve normal `flutter` commands. Only
    when you go to build the final release version of your app, do you need to use
    the `shorebird` command-line tool.

## Permissions needed for Shorebird

Shorebird code push requires the Network permission to be added to your
`AndroidManifest.xml` file. (Which in Flutter is located in
`android/app/src/main/AndroidManifest.xml`.) This is required for the
app to be able to communicate with the Shorebird servers to pull new patches.

```xml
<manifest ...>
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    ...
</manifest>
```

## Running your Shorebird-built app

You can use `shorebird run` to build and run your app on a connected
Android device. This is similar to `flutter run --release` just with
Shorebird's fork of the Flutter engine that includes the Shorebird updater.

`shorebird run` wraps `flutter run` and can take any argument `flutter run` can.
To pass arguments to the underlying `flutter run` use a `--` separator. For example:
`shorebird run -- -d my_device` will run on a specific device.

During this trusted tester period, you will likely see several logs from the
shorebird updater. These are for debugging in case you have trouble
and will be removed/silenced in future iterations.

Note: The first time you run `shorebird run` it will need to download the Shorebird
engine into `Library/Application Support/shorebird/engines` directory within your project. This is about ~200mb in download (we can make it much smaller, just haven't yet) and can take several seconds depending on your internet connection.

Example:

```
eseidel@erics-mbp test_counter % shorebird run
Running app...
Using hardware rendering with device sdk gphone64 arm64. If you notice graphics artifacts, consider enabling software rendering with "--enable-software-rendering".

Launching lib/main.dart on sdk gphone64 arm64 in release mode...

Running Gradle task 'assembleRelease'...
   17.6s

✓  Built build/app/outputs/flutter-apk/app-release.apk (8.5MB).

Installing build/app/outputs/flutter-apk/app-release.apk...
   375ms



Flutter run key commands.

h List all available interactive commands.

c Clear the screen

q Quit (terminate the application on the device).

W/FlutterJNI( 7283): shorebird.yaml: app_id: 4f636c95-f859-4de3-a730-dde1c099cd53

D/flutter ( 7283): updater::logging: Logging initialized

I/flutter ( 7283): updater::config: Updater configured with: ResolvedConfig { is_initialized: true, cache_dir: "/data/user/0/com.example.test_counter/code_cache/shorebird_updater", download_dir: "/data/user/0/com.example.test_counter/code_cache/shorebird_updater/downloads", channel: "stable", app_id: "4f636c95-f859-4de3-a730-dde1c099cd53", release_version: "1.0.0", original_libapp_path: "libapp.so", vm_path: "libflutter.so", base_url: "https://api.shorebird.dev" }

I/flutter ( 7283): [INFO:flutter_main.cc(108)] Starting Shorebird update
W/flutter ( 7283): updater::cache: Failed to load updater state: No such file or directory (os error 2)

I/flutter ( 7283): updater::network: Sending patch check request: PatchCheckRequest { app_id: "4f636c95-f859-4de3-a730-dde1c099cd53", channel: "stable", release_version: "1.0.0", patch_number: None, platform: "android", arch: "aarch64" }
D/flutter ( 7283): reqwest::connect: starting new connection: https://api.shorebird.dev/

E/flutter ( 7283): updater::updater: Problem updating: error sending request for url (https://api.shorebird.dev/api/v1/patches/check): error trying to connect: dns error: failed to lookup address information: No address associated with hostname

E/flutter ( 7283): updater::updater: disabled backtrace
W/flutter ( 7283): updater::cache: Failed to load updater state: No such file or directory (os error 2)
E/flutter ( 7283): [ERROR:flutter/shell/platform/android/flutter_main.cc(127)] Shorebird updater: no active path.
```

If you see messages like

```
E/flutter ( 7283): updater::updater: Problem updating: error sending request for url (https://api.shorebird.dev/api/v1/patches/check): error trying to connect: dns error: failed to lookup address information: No address associated with hostname
```

That indicates you have not yet added the network permissions (see above)
to your app, as I had forgotten when running my example above.

## Creating a release

Before you can start uploading patches, you will need to create a release. Creating a release builds and submits your app to Shorebird. Shorebird saves the compiled Dart code from your application in order to make patches smaller in size.

Example:

```
shorebird release
✓ Building release (17.9s)
✓ Fetching apps (0.1s)

What is the version of this release? (0.1.0) 0.1.0

🚀 Ready to create a new release!

📱 App: shorebird_test (4f636c95-f859-4de3-a730-dde1c099cd53)
📦 Release Version: 0.1.0
⚙️  Architecture: aarch64
🕹️  Platform: android
#️⃣  Hash: cfe26dddf8aff17131042f9dfad409c83eb130c5a9f2fd6f77325b2388062265

Your next step is to upload the release artifact to the Play Store.
./build/app/outputs/bundle/release/app-release.aab

See the following link for more information:
https://support.google.com/googleplay/android-developer/answer/9859152?hl=en

Would you like to continue? (y/N) Yes
✓ Fetching releases (55ms)
✓ Creating release (45ms)
✓ Creating artifact (1.8s)

✅ Published Release!
```

## Publishing patches to your app

To publish a patch to your app, use `shorebird patch`. It should look like:

```
shorebird patch
✓ Building patch (16.2s)
✓ Fetching apps (0.1s)

Which release is this patch for? (0.1.0) 0.1.0

🚀 Ready to publish a new patch!

📱 App: shorebird_test (4f636c95-f859-4de3-a730-dde1c099cd53)
📦 Release Version: 0.1.0
⚙️ Architecture: aarch64
🕹️ Platform: android
📺 Channel: stable
#️⃣ Hash: cfe26dddf8aff17131042f9dfad409c83eb130c5a9f2fd6f77325b2388062265

Would you like to continue? (y/N) Yes
✓ Fetching releases (41ms)
✓ Fetching release artifact (43ms)
✓ Downloading release artifact (0.2s)
✓ Creating diff (0.1s)
✓ Creating patch (64ms)
✓ Creating artifact (0.3s)
✓ Fetching channels (40ms)
✓ Publishing patch (43ms)

✅ Published Patch!
```

This will generate a new patch for your app and upload it to the Shorebird servers for distribution to all other copies of your app. For example, you could try `shorebird run` to run and install your app, and then stop it. Make edits and `shorebird patch` and then run the app again directly (by clicking on it, without using `shorebird run`) and you should notice that it updates to the latest built and published version rather than using the previously installed version.

The current `shorebird patch` flow is not how we envision Shorebird being used longer term (e.g one might push a git hash to a CI/CD system, which would then publish it to Shorebird). However, it's the simplest thing to do for now.

Note that you can only publish a patch to an app that you have already told
shorebird about. This is normally done by `shorebird init` + `shorebird release`. If needed you can also create an app via `shorebird apps create` and modify the `shorebird.yaml` directly yourself, see: https://github.com/shorebirdtech/shorebird/tree/main/packages/shorebird_cli#create-app

Your applications in the wild will query for updates with their `app_id` (which comes from `shorebird.yaml`) and their release version (which comes from AndroidManifest.xml, which in turn is generated from pubspec.yaml).

## Building a release version of your app

You can use `shorebird build` to build a release version of your app including the Shorebird updater.

`shorebird build` wraps `flutter build` and can take any argument `flutter build`
can. To pass arguments to the underlying `flutter build` you need
to put `flutter build` arguments _after_ a `--` separator. For example:
`shorebird build -- --dart-define="foo=bar"` will define the "foo" environment
variable inside Dart as you might have done with `flutter build` directly.

Success should look like this:

```
% shorebird build
✓ Building shorebird engine (8.0s)
✓ Building release  (6.4s)
```

## Update behavior

The Shorebird updater is currently hard-coded to update synchronously on
launch. This means that when you push a new version of your app, all users
will update on next launch.

We expect to add more control over update behavior in the future, including
async updates and percentage based rollouts. Please let us know if these
are important to you and we are happy to prioritize them!

The Shorebird updater is designed such that when the network is not available,
or the server is down or otherwise unreachable, the app will continue to run
as normal. Should you ever choose to delete an update from our servers, all your
clients will continue to run as normal.

We have not yet added the ability to rollback patches, but it's on our todo
list and happy to prioritize it if it's important to you. For now, the simplest
thing is to simply push a new patch that reverts the changes you want to undo.

## Play Store

Although Shorebird connects to the network, it does not send any personally
identifiable information. Including Shorebird should not affect your
declarations for the Play Store.

Requests sent from the app to Shorebird servers include:

- app_id (specified `shorebird.yaml`)
- channel (optional in `shorebird.yaml`)
- release_version (versionName from AndroidManifest.xml)
- patch_number (generated as part of `shorebird patch`)
- arch (e.g. 'aarch64', needed to send down the right patch)
- platform (e.g. 'android', needed to send down the right patch)
  That's it. The code for this is in `updater/library/src/network.rs`

## Play Store Guidelines

Shorebird is designed to be compatible with the Play Store guidelines. However
Shorebird is a tool, and as with any tool, can be abused. Deliberately abusing
Shorebird to violate Play Store guidelines is in violation of the Shorebird
[Terms of Service](shorebird.dev/terms.html) and can result in termination of
your account.

Examples of guidelines you should be aware of, include "Deceptive Behavior" and
"Unwanted Software". Please be clear with your users about what you are
providing with your application and do not violate their expectations with
significant behavioral changes through the use of Shorebird.

Code push services are widely used in the industry (all of the large apps
I'm aware of use them) and there are multiple other code push services
publicly available (e.g. expo.dev & appcenter.ms). This is a well trodden path.

## Disabling Shorebird

_First, do no harm_

Shorebird is designed to be a drop-in replacement for the stock Flutter engine,
and can be disabled at any time with no effect on your users.

Building with `shorebird build` will include Shorebird code push in your app.
Building with `flutter build --release` will not include Shorebird in your app.
At any time you can simply drop back to `flutter build` and things will work
as they did before.

We have not yet added the ability to delete your account from Shorebird from
the command line, however reach out to us via Discord or email and we are
happy to help you immediately delete your account and disable all updates
for your app(s) deployed with Shorebird. We anticipate adding this ability
to the command line in the near future.

You can remove `shorebird` from your path by removing it from your `.bashrc` or `.zshrc` and deleting the `.shorebird` directory located in `~/.shorebird`.
