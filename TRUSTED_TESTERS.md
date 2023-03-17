# Trusted Testers

While this document is public, access to Shorebird services are not yet
generally available. We're running a trusted tester program with a limited
number of users to ensure that we're building the right thing and that it's
stable for general use.

If you'd like to be a part of the program, please join our mailing list
(linked from shorebird.dev), we will send out information there as we're ready.



## Welcome!

If you're joining the trusted tester program, welcome!  Thank you for your help
making Shorebird a reality.

You should have received an API key in the mail.  You will need it as part
of the login process for the `shorebird` command-line tool to work.

## Our goal

Our goal with this Trusted Tester program is to shake out bugs and ensure that
we are building things people want.  We *want* your feedback.  We *want* you to
break things.  We *want* you to tell us what you want to see next.  We're
already a default-public company, but we intend to be even more open with you
and will be shipping your regular updates during the program, responding to
your feedback.

Our guiding principle in creating v1 is "first, do no harm".  It should be the
case that using Shorebird is never worse than not using Shorebird.  We've worked
hard to find and remove breaking bugs.

It is still possible using Shorebird
may break your app in the wild.  Thankfully this is no worse than any other
change to your app, and you can always push a new version via the store should
Shorebird break users in the wild.

## What works today
You can build and deploy new (release) versions of your app to all Android arm64
users via Shorebird command line from a Mac computer.

All users will synchronously update to the new version on next launch
(no control over this behavior yet).

Basic access to the updater through package:dart_bindings (unpublished).

Shorebird command line can show a list of what apps and app versions you've
associated with your account and what patches you've pushed to those apps.

Updates are currently typically a few MBs in size and include all Dart code that
your app uses (we can make this much smaller, but haven't yet).

## What doesn't yet

Limited platform support:
* Only Arm64 platform, no non-Android or non-arm64 support.
* Windows, Linux

No support for:
* Flutter channels (only latest stable is supported)
* Rollbacks
* Channels
* Percentage based rollouts
* Async updates
* Analytics
* Web interface
* CI/CD (GitHub Actions, etc.)
* Patch signing
* OAuth (or associating with any other accounts)

## Getting started

The first thing you'll want to do is install the `shorebird` command-line tool.

// Insert instructions here.

Currently we assume you have `flutter` installed and working.  We also require
that `flutter` be set to the latest stable channel.  The `shorebird` tool should
enforce this (and show errors if your `flutter` is not set up as expected).


## What next?

The first use-case we're targeting is one of deploying updates to a small
set of users.  If you already have a Flutter app with a small install base, you
can convert it to Shorebird in a few steps:

1. Use `shorebird init` to add a `shorebird.yaml` file to your project.
`shorebird.yaml` contains the app_id for your app, which is just a unique
identifier the app will be able to send to Shorebird servers to identify which
application/developer to pull updates from.

`shorebird init` will also add the `shorebird.yaml` to the assets section of
your `pubspec.yaml` file, which will ensure that the file is included in your
app's assets.

You can go ahead and commit these changes, they will be innocuous even if you
don't end up using Shorebird with this application.

2.  Typical development usage will involve normal `flutter` commands.  Only
when you go to build the final release version of you app, do you need to use
the `shorebird` command-line tool.


// More here.


## Update behavior

The Shorebird updater is currently hard-coded to update synchronously on
launch.  This means that when you push a new version of your app, all users
will update on next launch.  This is not ideal, but it's the simplest thing to
do for now.

We expect to add more control over update behavior in the future, including
async updates and percentage based rollouts.  Please let us know if these
are important to you and we are happy to prioritize them!

The Shorebird updater is designed such that when the network is not available,
or the server is down or otherwise unreachable, the app will continue to run
as normal.  Should you ever chose to delete an update from our servers, all your
clients will continue to run as normal.

We have not yet added the ability to rollback patches, but it's on our todo
list and happy to prioritize it if it's important to you.  For now, the simplest
thing is to simply push a new patch that reverts the changes you want to undo.

## Releasing with Shorebird

Shorebird code push requires the Network permission to be added to your
`AndroidManifest.xml` file.  This is required for the app to be able to
communicate with the Shorebird servers.

```xml
<manifest ...>
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    ...
</manifest>
```

## Play Store

Although Shorebird connects to the network, it does not send any personally
identifiable information.  Including Shorebird should not affect your
declarations for the Play Store.

Requests sent from the app to Shorebird servers include:
* app_id (specified `shorebird.yaml`)
* channel (optional in `shorebird.yaml`)
* release_version (versionName from AndroidManifest.xml)
* patch_number (generated as part of `shorebird publish`)
* arch (e.g. 'aarch64', needed to send down the right patch)
* platform (e.g. 'android', needed to send down the right patch)
That's it.  The code for this is in `updater/library/src/network.rs`


## Play Store Guidelines

Shorebird is designed to be compatible with the Play Store guidelines. However
Shorebird is a tool, and as with any tool, can be abused.  Deliberately abusing
Shorebird to violate Play Store guidelines is in violation of the Shorebird
[Terms of Service](shorebird.dev/terms.html) and can result in termination of
your account.

Examples of guidelines you should be aware of, include "Deceptive Behavior" and
"Unwanted Software".  Please be clear with your users about what you are
providing with your application and do not violate their expectations with
significant behavioral changes through the use of Shorebird.

Code push services are widely used in the industry (all of the large apps
I'm aware of use them) and there are multiple other code push services
publicly available (e.g. expo.dev & appcenter.ms).  This is a well trodden path.


## Disabling Shorebird

_First, do no harm_

Shorebird is designed to be a drop-in replacement for the stock Flutter engine,
and can be disabled at any time with no affect on your users.

Building with `shorebird build` will include Shorebird code push in your app.
Building with `flutter build --release` will not include Shorebird in your app.
At any time you can simply drop back to `flutter build` and things will work
as they did before.

We have not yet added the ability to delete your account from Shorebird from
the command line, however reach out to us via Discord or email and we are
happy to help you immediately delete your account and disable all updates
for your app(s) deployed with Shorebird.  We anticipate adding this ability
to the command line in the near future.
