These are our old docs for our manual update process.

`cutler` replaces some of this, but not all of it. Keeping these until
`cutler` is fully functional.

## Keeping our fork up to date

1. Pick a version of Flutter to update to (e.g. 3.7.10) new_flutter
3.7.10 flutter = https://github.com/flutter/flutter/tree/3.7.10
https://github.com/flutter/flutter/commit/4b12645012342076800eb701bcdfe18f87da21cf

2. Find the engine version for new_flutter (e.g. 3.7.10) new_engine
3.7.10 engine = https://github.com/flutter/flutter/blob/3.7.10/bin/internal/engine.version
ec975089acb540fc60752606a3d3ba809dd1528b

3. Find the buildroot version for new_engine (e.g. 3.7.10) new_buildroot
https://github.com/flutter/engine/tree/3.7.10/
3.7.10 buildroot = https://github.com/flutter/engine/blob/3.7.10/DEPS#L239
8747bce41d0dc6d9dc45c4d1b46d2100bb9ee688

4. Find the version of Flutter we're based on (currently, incorrectly 3.7.9) old_flutter
https://github.com/shorebirdtech/flutter/tree/stable
https://github.com/shorebirdtech/flutter/commit/62bd79521d8d007524e351747471ba66696fc2d4

5. Find the engine version for old_flutter (e.g. 3.7.8) old_engine
https://github.com/shorebirdtech/engine/tree/stable_codepush
is based on 3.7.8 engine =
https://github.com/flutter/engine/tree/3.7.8
https://github.com/shorebirdtech/engine/commit/9aa7816315095c86410527932918c718cb35e7d6

6. Find the buildroot version for old_engine (e.g. 3.7.8) old_buildroot
https://github.com/shorebirdtech/buildroot/commits/stable_codepush
is based on:
https://github.com/shorebirdtech/buildroot/commit/8747bce41d0dc6d9dc45c4d1b46d2100bb9ee688


7. With that data, we now just go through and move the patches we made from
on top of old_* to be on top of new_*.  e.g.
`git rebase --onto new_flutter old_flutter stable_codepush`

In addition to doing the rebasing we also need to go through and update the version
numbers in the various places.  We can do both in a single pass.

8. buildroot: Based on the above, we don't need to do anything for buildroot this time,
but do need to rebase the engine and flutter repos.

9. engine: But we do need to move our engine fork:
`git rebase --onto 3.7.10 3.7.8 stable_codepush`
And save off that hash:
`git rev-parse stable_codepush`
978a56f2d97f9ce24a2b6bc22c9bbceaaba0343c

We do not need to update our engine fork commits at this time since it already
pointed to the (unchanged) forked buildroot in `DEPS`.

Because this kind of rebase is a non-fast-forward commit, we will need to
force push to our fork.  A better solution will be for us to tag or branch
each of these releases instead of keeping a single release branch.
```
git push origin --force
```

10. flutter: Then we need to move our flutter fork.
Our flutter fork currently uses the `stable` channel instead of stable_codepush
we should eventually standardize on across all the repos on something.

If we change this branch we also would need to change the branch in the
shorebird cli which controls updating the flutter version.

Since the only commit on our flutter
fork is one changing engine.version, we can just replace the commit:
```
git fetch upstream
git reset --hard 3.7.10
echo '978a56f2d97f9ce24a2b6bc22c9bbceaaba0343c' > bin/internal/engine.version
git add bin/internal/engine.version
git commit -a -m 'chore: Update engine version to shorebird-3.7.10'
```
Again we should save off our new hash:
`git rev-parse stable`
c2185f5f6cce5c6c47e7f71c682ecae1e3817d18

This will need a similar force push:
```
git push origin --force
```

11.  Finally we need to update the shorebird cli itself.  Currently located at:
https://github.com/shorebirdtech/shorebird/blob/main/packages/shorebird_cli/lib/src/engine_revision.dart

12. If there were changes to the `patch` binary in the `updater` library we
will need to trigger github actions before we can publish the new version of
the shorebird engine.

13. Before we can publish the new version of Shorebird, we need to build the
engine for all the platforms we support.  We do that by running the
`build_and_upload.sh` script in the build_engine repo.

```
./build_engine/build_engine/build_and_upload.sh ./engine 978a56f2d97f9ce24a2b6bc22c9bbceaaba0343c  
```

That script should be run in the cloud, but right now I've not figured that out
yet, so we run it locally on an arm64 Mac.

13. Once we've built all artifacts we need to teach the artifact_proxy how to
serve them.  We do that by adding entries to:
https://github.com/shorebirdtech/shorebird/blob/main/packages/artifact_proxy/lib/config.dart

Obviously all this needs to be made better/automated.