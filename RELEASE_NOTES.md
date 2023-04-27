# Release Notes

This section contains past updates we've sent to current Trusted Testers.

## Announcement for 0.0.8

We've just released Shorebird CLI v0.0.8 🎉

What's new:
* Updated to Flutter 3.7.12.
* Updated Shorebird to use a specific revision of Flutter (rather than
  "latest stable in our fork", making it possible to check out a specific
  version of Shorebird from git and expect it to be able to build binaries
  even months in the future).
* Added (partial) support for Android build numbers.
* Added `shorebird account create` and `shorebird account subscribe` to
  automate our onboarding process for new trusted testers.
* Improved the way we proxy Flutter artifacts (via download.shorebird.dev) to
  greatly improve our speed of releasing new versions of Shorebird.

Let us know if you see any issues!

## Announcement for 0.0.7

We've just released Shorebird CLI v0.0.7 🎉 

What's new:
* Fixed our backend to not error for large app releases.
* `shorebird build` is now split into two subcommands:
  * `shorebird build apk` (new)
  * `shorebird build appbundle` (previously `shorebird build`)

Changelog: https://github.com/shorebirdtech/shorebird/releases/tag/v0.0.7 


## Announcement for 0.0.6

We're happy to announce Shorebird 0.0.6!

Shorebird should be ready for production apps < 10k users.

You should be able to get test latest via `shorebird upgrade`

What's new:
* Fixed updates to apply when app installed with apk splits (as the Play
  Store does by default). This was our last known production blocking issue.
* `shorebird subscription cancel` now is able to cancel your monthly
  Shorebird subscription.  Your Shorebird account will keep working until
  the end of your billing period.  After expiration, your apps will continue
  to function normally, just will no longer pull updates from Shorebird.
* `shorebird cache clean` (Thanks @TypicalEgg!) will now clear Shorebird
  caches.
* Install script now pulls down artifacts as part of install.
* Continued improvements to our account handling in preparation for supporting
  self-sign-up.

Known issues:
* Shorebird is still using Flutter 3.7.10.  We will update to 3.7.11 right
  after this release:
  https://github.com/shorebirdtech/shorebird/issues/305
* Shorebird does not yet support Android versionCode, only versionName.
  https://github.com/shorebirdtech/shorebird/issues/291

Please try shorebird in production and let us know how we can help!

Eric


## Announcement for 0.0.5

We're happy to announce Shorebird 0.0.5!

TL;DR: Shorebird should be ready for use in production for apps < 10k users.

You should be able to get the latest via `shorebird upgrade`.

What's new:
* Updates should now apply consistently (previously sometimes failed).
https://github.com/shorebirdtech/shorebird/issues/235.  This was our
last-known production-blocking issue.
* `shorebird doctor` and other commands now are a bit more robust in
their checks.
* We did a ton of backend work (which shouldn't be visible), mostly
in terms of testing to make sure we're ready for production.  We also
integrated our backend with Stripe (to make subscription management
possible).

Known issues:
* Shorebird is still using Flutter 3.7.10.  We will update to 3.7.11
in the next couple days.  We've done the previous Flutter updates
manually, but we're working on automating updates so that Shorebird
can track Flutter versions as soon as minutes after they are released.
https://github.com/shorebirdtech/shorebird/issues/236

You can see what we're tracking for 0.0.6 here:
https://github.com/orgs/shorebirdtech/projects/6/views/1

We've also wired up Stripe integration on the backend and will have some
subscription management (including ability to cancel) in our next release.

We expect you all will have requests as you try Shorebird in production
please don't hesitate to let us know!  We're standing by to fix/add what
you need to help you be successful.

Please try shorebird in production and let us know how we can help!

Eric



## Announcement for 0.0.4

I'm happy to announce shorebird 0.0.4!

This one's a big one.  Unfortunately it's also breaking.

You will both need to re-install shorebird and re-login to shorebird:

```bash
rm -rf ~/.shorebird
curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh -sSf | sh
```

Then you'll want to `shorebird login` and follow the prompts to authenticate
with a Google account.

We believe we've updated our database to mark all trusted testers as paid
accounts after the auth migration, but if you see any issues, please let us
know, and we'll be happy to fix your account right away.

What's new:
* `shorebird` supports Android 32-bit and 64-bit devices!
* `shorebird` works on Linux and Mac-Intel hosts!
* `shorebird login` uses Google OAuth instead of API keys.
* `shorebird doctor` does some basic validation.
* `shorebird account` shows your login status.
* Updated to Flutter 3.7.10.
* We also automated our builds of the Shorebird engine.
  While that won't affect your usage, it did make this release
  possible and will allow us to keep up to date with Flutter more easily as
  well as removing a source of human error in our processes.

As part of adding support for Android arm32 devices as well as Linux and
Mac-Intel hosts, we've changed how `shorebird` uses Flutter.  Previously it used
the Flutter SDK already installed on your machine.  Now it brings its own copy
of `flutter`.  This is due to the fact that our previous method of replacing the
Flutter engine binaries on Android went in through a (hacky) development-only
path, which only supported only a single architecture at a time (hence us
previously limiting `shorebird` only 64-bit Android devices).

Now we use a fork of Flutter.  The only change in our fork is the engine version
it tries to fetch.  When `shorebird` runs our forked `flutter`, we also tell it
to fetch its engine artifacts from our server (download.shorebird.dev) instead
of Google's (download.flutter.io).  download.shorebird.dev knows how to replace
a few Android artifacts with Shorebird enabled ones and proxy all other requests
to Google's servers.  This is how we now support all platforms Flutter does
since it's using the same host binaries as an unmodified Flutter SDK.

https://github.com/shorebirdtech/shorebird/blob/main/FORKING_FLUTTER.md has more
information on how we forked Flutter if you're curious.

Known issues:
* We have had reports of patches sometimes failing to apply.  We expect to have
  a fix for this early next week.
  https://github.com/shorebirdtech/shorebird/issues/235
* Shorebird itself should work on Windows, but we haven't updated our installer
  script to support it yet.  https://github.com/shorebirdtech/install/issues/10

Please try out the new platforms and new auth flow and let us know what you
think.
