# Milestones

This is an attempt to sketch out some high-level milestones for discussion.

Currently we have a trusted tester program ongoing, where we've been targeting
getting 5 devs able to use Shorebird to push to small usage apps (e.g. 100 users).
https://github.com/shorebirdtech/shorebird/blob/main/TRUSTED_TESTERS.md


Milestones are roughly ordered how I expect us to approach them:

## 1k user apps & 10 devs using
Goal: make the current trusted tester builds more real-world usable.
https://github.com/orgs/shorebirdtech/projects/2/views/1
* Make it possible to ship new versions of shorebird to devs.
* Make updates smaller
* Validate hashes of updates on device.

## 10k user apps
Goal: Don't be afraid to ship updates to 10k users.
* Async updates / make updates only download on WiFi?
* Android ARM32 support

## 10 devs (in production)
Goal: Have devs using Shorebird in production.
* Not sure until we get closer.

## 100k user apps
* Some kind of promotion mechanism
* Some kind of analytics
* Dart access to updater API for control of updates?

## 1m user apps
* Anti-DDoS (some sort of update rate limiting)
* CDN for Updates

## 1000 devs
* CLI support for Windows (and Linux?)
* OAuth
* Publicly available sign-up flow (including billing)
