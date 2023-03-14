# FAQ

Maintained by @eseidel

If you have questions not answered here, please ask (either by filing an issue
or asking on [Discord](https://discord.gg/9hKJcWGcaB)).

### What is "code push"?

Code push, also referred to as "over the air updates" (OTA) is a cloud service
we are building to enable Flutter developers to deploy updates directly to
devices anywhere they have shipped Flutter.  We've currently shown demos using
Android, but since it's built with Flutter/Dart (and Rust) it will work anywhere
Flutter works.

The easiest way to see is to watch the [demo
video](https://www.youtube.com/watch?v=mmKvs0_Zu14&ab_channel=Shorebird).

Code push is a working title.  We'll probably come up with some name to help
differentiate it.  "Code Push" is a reference to the name of a deploy feature
used by the React Native community from [Microsoft](https://appcenter.ms) and
[Expo](https://expo.dev), neither of which support Flutter.

### What is the status of code push?

As of March 13th, 2023 we have a basic serving architecture in production and
built out enough to service multiple simultaneous customers.  We've also
validated basic on-device support.  We're working towards issuing our first
API keys by March 20th as part of a trusted-tester program.  We have an ~80%
confidence on that date.
You can watch our [March 13th demo](https://www.youtube.com/watch?v=oZ9fa-kob_U).

As of March 4th, 2023 we've built [a
demo](https://www.youtube.com/watch?v=mmKvs0_Zu14&ab_channel=Shorebird) and have
the prototype working on multiple machines and Android phones.

### What is the roadmap?

First we're trying to get something working into user's hands.  You can follow
our day-to-day progress on our project board:
https://github.com/orgs/shorebirdtech/projects/1/views/1

Eric intends to send out a survey to the mailing list on March 17th from which
we will select the first participants in our trusted tester program beginning
March 20th.  You can sign-up at [shorebird.dev](https://shorebird.dev) -- and
[Discord](https://discord.gg/9hKJcWGcaB).

### How does this relate to Firebase Remote Config or Launch Darkly?

Code push allows adding new code / replacing code on the device.  Firebase
Remote Config and Launch Darkly are both configuration systems.  They allow you
to change the configuration of your app without having to ship a new version.
They are not intended to replace code.

### How big of a dependency footprint does this add?

We don't know yet.  We expect the code push library to add less than one
megabyte to Flutter apps.


### How does this relate to Flutter Hot Reload?

Flutter's Hot reload is a development-time-only feature.  Code push is for
production.

Hot reload is a feature of Flutter that allows you to change code on the device
during development.  It requires building the Flutter engine with a debug-mode
Dart VM which includes a just-in-time (JIT) Dart compiler.

Code push is a feature that allows you to change code on the device in
production.  We will use a variety of different techniques to make this possible
depending on the platform.  Current demos execute ahead-of-time compiled Dart
code and do not require a JIT Dart compiler.

### Does this support Flutter Web?

Code push isn't needed for Flutter web as the web already works this way.  When
a user opens a web app it downloads the latest version from the server if
needed.

If you have a use case for code push with Fluter web, we'd love to know!

### Will this work on iOS, Android, Mac, Windows, Linux, etc?

Yes.

So far we've been using Android for our demos, but code push will eventually
work everywhere Flutter works. We're focusing on building out the infrastructure
needed to provide code push reliably, safely first before targeting any specific
platform.

There are different technical restrictions on some platforms (e.g. iOS) relative
to Android, but we have several approaches we can use to solve them (Dart is an
incredibly flexible language).

### How does this relate to the App/Play Store review process or policies?

Developers are bound by their agreements with store providers when they choose
to use those stores.  Code push is designed to allow developers to update their
apps and still comply with store policies on iOS and Android.  Similar to the
variety of commercial products available to do so with React Native (e.g.
[Microsoft](https://appcenter.ms), [Expo](https://expo.dev)).

We will include more instructions and guidelines about how to both use code push
and comply with store guidelines as we get closer to a public launch.

### Does code push require the internet to work?

Yes.  One could imagine running a server to distribute the updates separately
from the general internet, but some form of network connectivity is required to
transport updates to the devices.


### What happens if a user doesn't update for a long time and misses an update?

Our current designs for code push send the current app version & code signature
as part of the update request.  Thus the update server could be written to
respond with either the next incremental version or the latest version depending
on your application's needs.  The current demo always sends the latest version
but this logic would not be hard to add.

### Why are some parts of the code push library written in Rust?

Parts of the code push ("updater") system are written in Rust:
1. Avoids starting two Dart VMs (one for the updater and one for the app).
2. Allows accessing the updater code from multiple languages (e.g. both the C++ engine as well as a Dart/Flutter application, or even Kotlin/Swift "native" code if needed)

See our [Languages Philosophy](https://github.com/shorebirdtech/handbook/blob/main/engineering.md#languages) for more information as to why we chose Rust.
