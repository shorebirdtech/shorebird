## A reminder why

- We're here to make multi-platform the default.
- We believe Flutter is that default, but has missing pieces for enterprises.
- The first hole we're filling is the ability to push updates to Flutter apps.

## Shipping to users (first, do no harm)

- Need a way to know if the update failed (and both report it and roll back?)
- Need to not send updates to incompatible devices or base versions.
- Do we need to worry about different chipsets?
- How do we educate users/developers about data storage updates (e.g. updating a database schema locally) and how that affects version compatibility / ability to roll back?
- How does the Dart code know that it's running a patched version?

## Later

- Way to see what builds have been published so far.
- See what % of devices are running what builds.
- Make package:updater API work from Dart
- Example of using Dart API from Dart/Flutter.
- Ability to roll back to past push.
- Build update from source (in the cloud).
- GitHub integration / action trigger.
- Quantify update download sizes.
- Be able to create an account / API key.
- Web interface to see pushes?
- Security (signing, 2FA, 2-person approval, etc.)
- Quantify how much bandwidth a push will use.
- What % of device population has taken push.
