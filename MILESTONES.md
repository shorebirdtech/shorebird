# Milestones

This is an attempt to sketch out some high-level milestones for discussion.

Currently we have a trusted tester program ongoing, where we've been targeting
getting 5 devs able to use Shorebird to push to small usage apps (e.g. 100 users).
https://github.com/shorebirdtech/shorebird/blob/main/TRUSTED_TESTERS.md

## Where we are today

Right now we're trying to "find the product".  See if we can build something
that people want and will use and pay for.  We're not trying to "build it right"
yet, but we are trying to build things that are in the directions we think
they will need to grow in.

For example.  Right now we have a manual sign-up process.  We send folks an
email with a Stripe link, they fill it out, Zapier then notifies us in our
Discord channel, we manually create an API key, manually report that back to the
Discord channel, and manually email it to the user.  It's terrible.  But
importantly it lets us build in the direction we're going (of building a paid
product) even if we don't have anything resembling the final flow yet and as
terrible as it is, it's good enough to unblock us testing the rest of the
system.

We have lots of untested code (not because we don't like tests), but because
we're not sure if we'll have that code in a few weeks time.

Anyway, this doc is about figuring out what is the next thing we're questing
towards and then we will hack and slash our way there.

## Milestones

Milestones are roughly ordered how I expect us to approach them:

## 1k user apps & 10 devs using
Goal: make the current trusted tester builds more real-world usable.
https://github.com/orgs/shorebirdtech/projects/2/views/1
* Make it possible to ship new versions of shorebird to devs.
* Make updates smaller
* Validate hashes of updates on device.

## 10k user apps in production
Goal: Don't be afraid to ship updates to 10k users.
* Async updates / make updates only download on WiFi?
* Android ARM32 support

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
