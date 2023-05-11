# Code push Notes

Just place to keep running notes about our development of codepush for Flutter.

## Server push vs. code push

Dynamically changing the application a user experiences (even just to show
their login name or shopping cart balance, etc) is necessary in any modern
server-associated application.  This is trivial on the web (where users always
fetch the latest version of your application from your servers), but not for
installed applications, like we use on mobile phones.

One approach is sending new configuration data to clients.  This works for
changing layouts, showing profile information, etc.  However, it does not work
for changing the application logic (fixing bugs, etc).  For the purposes of this
doc I'm referring to data-only delivery as "server push" and code+data delivery
as "code push".

Every single large application on mobile phones that I'm aware of uses code push
in some form.  One reason for this is update frequency.  It is not uncommon for
a mobile application to have a new release every week or two, yet users
sometimes lag months (or years) in their app updates.  This means that if an
application has a server component which might be tied to a specific version of
an application, that server component must be able to handle multiple versions
of the application going back years.  This is a huge burden for developers and
eventually results in a worse end user experience than if the an application
required less developer effort to maintain.

## Code push approaches

Many approaches one could take:
1. Compile Release Flutter with DartVM in JIT mode
   Implementation Difficulty: Medium
   Application Performance: Unreliable (due to JIT compiles), but good once warmed up.
   Platform Restrictions: Some restrict executing dynamically compiled code (either technically or by store agreement)
1. Replace libapp.so with new libapp.so
   Implementation Difficulty: Simple
   Application Performance: Great (AOT level performance)
   Platform Restrictions: Some restrict loading dynamic libraries (either technically or by store agreement)
   Developer Experience: OK (need to recompile for each platform)
   Notes:
    * A naive implementation has large update sizes (can be mitigated)
1. Flutter Web (JS or WASM) + C++ Engine
   Implementation Difficulty: Hard (no known implementations)
   Application Performance: Unknown, likely good? (JS JIT level performance)
   Platform Restrictions: None known.
   Notes:
    * No per-platform work for developers.
    * Possible developer headaches due to Dart -> JS compilation quirks.
1. Flutter Web (JS or WASM) in a WebView
    Implementation Difficulty: Medium
    Application Performance: Poor (untested)
    Platform Restrictions: None known.
1. (Custom) Dart Interpreter (for some or all application code)
    Implementation Difficulty: Hard
    Application Performance: Unknown
    Developer Experience: Unknown
    Platform Restrictions: None known.
    Pros:
     * There have been several implementations of this approach, I'm not aware
       of any being publicly available/supported at this time.
     * Defining a boundary between AOT and Interpreter code is very hard.

Shorebird takes the approach of building the correct developer experience and
underlying infrastructure first, with plans to (likely dynamically) provide
multiple code push implementations to customers, depending on their needs and
the needs/restrictions of their target platforms.  We will likely implement
several of the above approaches for code push.

## Other known over-the-air update implementations

* https://github.com/microsoft/code-push
* https://github.com/Tencent/tinker
* https://github.com/expo/expo/tree/main/packages/expo-updates
* https://github.com/hydro-sdk/hydro-sdk
* https://pub.dev/packages/rfw
* https://pub.dev/packages/flutter_eval
* https://github.com/google/omaha
* http://code.google.com/p/update-engine/
* https://sparkle-project.org/
* https://learn.microsoft.com/en-us/windows/msix/overview
* https://hydraulic.software/

Did we forget some?  Patches welcome!
