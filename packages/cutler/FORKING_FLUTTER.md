These are our old docs for our manual update process.

`cutler` replaces some of this, but not all of it. Keeping these until
`cutler` is fully functional.

## Repository structure

We maintain forks of:
* flutter/flutter
* flutter/engine
* flutter/buildroot

We keep our forked changes on the `main` branch of each repo which we rebase
periodically on top of `main` from the upstream repo.

When Flutter makes a release, we make a branch in each repo for the Flutter
release and rebase necessary changes from main onto that branch.

We keep channel branches (e.g. `beta`, `stable`) in the `shorebird` repo but
do not do so in the other repos.

The forked repos have branches corresponding to a Flutter release but do not
keep branches corresponding to Shorebird or Flutter channels.

`cutler print-versions` is able to print out all of the hashes in the forked
repos for a given Shorebird hash (including any Shorebird channel or release
tag).

## Keeping our fork up to date

You need checkouts of all the various repos in the same directory.

Currently the tool assumes you're using our internal repository `_shorebird`
to check out `shorebird`.  Example:
```
cd $HOME/Documents/GitHub
git clone https://github.com/shorebirdtech/_shorebird
```
To check out the engine, you should follow:
https://github.com/shorebirdtech/updater/blob/main/BUILDING_ENGINE.md
it will result in an `engine` directory in the same directory as `_shorebird`.

Run `cutler` to get the git commands you need.

For a stable update:
```
dart run cutler --dry-run --root=$HOME/Documents/GitHub
```

For a beta update:
```
dart run cutler --dry-run --root=$HOME/Documents/GitHub --flutter-channel=beta
```

Eventually we'll automate stable, beta and master updates in the cloud.

Example output from updating 3.7.10 to 3.10.0:

```
dart run cutler --no-update --root=$HOME/Documents/GitHub --flutter-channel=beta --dry-run
Building package executable... 
Built cutler:cutler.
Shorebird stable:
  flutter   83305b5088e6fe327fb3334a73ff190828d85713
  engine    c415419390e4751ddfa3110e0808e7abb3d45a18
  buildroot 7383548fa2306b5d53979ac5e9d176b35258811b
Forkpoints:
  flutter   4d9e56e694b656610ab87fcf2efbcd226e0ed8cf (3.7.12)
  engine    1a65d409c7a1438a34d21b60bf30a6fd5db59314 (3.7.12)
  buildroot 8747bce41d0dc6d9dc45c4d1b46d2100bb9ee688
Upstream beta:
  flutter   b1c77b7ed32346fe829c0ca97bd85d19290d54ae (3.10.0-1.5.pre)
  engine    50e509c2bd0d7788feb675e38321cc5711c8d2d6 (3.10.0-1.5.pre)
  buildroot f24f62fa5381c0e415b6ca2000600fc0600c11c8
Rebasing buildroot...
git rebase --onto f24f62fa5381c0e415b6ca2000600fc0600c11c8 8747bce41d0dc6d9dc45c4d1b46d2100bb9ee688 7383548fa2306b5d53979ac5e9d176b35258811b
Rebasing engine...
git rebase --onto 3.10.0-1.5.pre 3.7.12 c415419390e4751ddfa3110e0808e7abb3d45a18
Rebasing flutter...
git rebase --onto 3.10.0-1.5.pre 3.7.12 83305b5088e6fe327fb3334a73ff190828d85713
Updating engine DEPS...
Would have changed DEPS lines:
(  'src': 'https://github.com/shorebirdtech/buildroot.git' + '@' + 'new-buildroot-hash',)
Updating flutter engine version...
  Change engine.version: b426644a712b0cfd32c896d947ddd1a1245eb713 from c415419390e4751ddfa3110e0808e7abb3d45a18
Updating shorebird flutter version...
  Change flutter.version: f0f67059dfa254be219b07d6d784eebec89c4fae from 83305b5088e6fe327fb3334a73ff190828d85713
```


1. Rebase buildroot on top of the new buildroot hash, e.g.
```
git rebase --onto f24f62fa5381c0e415b6ca2000600fc0600c11c8 8747bce41d0dc6d9dc45c4d1b46d2100bb9ee688 7383548fa2306b5d53979ac5e9d176b35258811b
```
2. Save the commit id from that rebase -- you'll need it to edit the DEPS file in
the engine repo.  In this example it was "d6c410f19de5947de40ce110c1e768c887870072".

3. Rebase the engine on top of the new engine hash, e.g.
```
git rebase --onto 3.10.0-1.5.pre 3.7.12 c415419390e4751ddfa3110e0808e7abb3d45a18
```
If there are conflicts, you'll need to resolve them.  If the conflict
is in the DEPS file, you can take it as an opportunity to insert the new
buildroot hash.

4. Save the commit id from that rebase -- you'll need it to edit the engine.version
file in the flutter repo.  In this example it was "94bc1218b84cc0199068f8788cda96e3128784a0".

5. Rebase the flutter repo on top of the new flutter hash, e.g.
```
git rebase --onto 3.10.0-1.5.pre 3.7.12 83305b5088e6fe327fb3334a73ff190828d85713
```
This might have conflicts, if so you'll need to resolve them.  If the conflict
is in the DEPS file, you can take it as an opportunity to insert the new
engine hash.

6. Save the commit id from that rebase -- you'll need it to edit the flutter.version
file in the shorebird repo.  In this example it was "f498c3913890e7a022596029c7f07f467b0889da".

7. Update the flutter.version file in the shorebird repo to the new flutter
hash, e.g.
```
echo 'f498c3913890e7a022596029c7f07f467b0889da' > bin/internal/flutter.version
commit -a -m "Update flutter version to 3.10.0-1.5.pre"
```

8. Now that we've prepared these versions it should be possible to build the
   engine and test our work!
   `gclient sync` is only needed if buildroot (`src`) changed.
```
cd $HOME/Documents/GitHub
cd engine
gclient sync
cd ..
./build_engine/build_engine/build.sh $HOME/Documents/GitHub/engine
```
build.sh currently requires an absolute path to the engine directory or it fails
with a cryptic error message crashing in `cargo ndk build`.

Building will take up to 45 mins on a M2 machine (it builds the engine 3 times)
if it's a clean build.

We don't currently have any integration tests, but we can test manually with an
app:
```
shorebird run --local-engine-src-path=$HOME/Documents/GitHub/engine/src --local-engine android_release_arm64
```

If things look good now we need to tag and push our changes to the git repos
we touched earlier.

9. Tag the buildroot repo with the new buildroot hash, e.g.
```
cd $HOME/Documents/GitHub/engine/src
git tag -a -m "shorebird-3.10.0-1.5.pre" shorebird-3.10.0-1.5.pre d6c410f19de5947de40ce110c1e768c887870072
git push origin shorebird-3.10.0-1.5.pre
```

10. Tag the engine repo with the new engine hash, e.g.
```
cd $HOME/Documents/GitHub/engine/src/flutter
git tag -a -m "shorebird-3.10.0-1.5.pre" shorebird-3.10.0-1.5.pre 94bc1218b84cc0199068f8788cda96e3128784a0
git push origin shorebird-3.10.0-1.5.pre
```

11. Tag the flutter repo with the new flutter hash, e.g.
```
cd $HOME/Documents/GitHub/flutter
git tag -a -m "shorebird-3.10.0-1.5.pre" shorebird-3.10.0-1.5.pre f498c3913890e7a022596029c7f07f467b0889da
git push origin shorebird-3.10.0-1.5.pre
```

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

14. Once we've built all artifacts the final step is to push the new version
of shorebird to the appropriate branch.  e.g.
(untested)
```
cd $HOME/Documents/GitHub/_shorebird/shorebird
git tag -a -m "shorebird-3.10.0-1.5.pre" shorebird-3.10.0-1.5.pre $VERSION
git push origin shorebird-3.10.0-1.5.pre
git push origin/beta shorebird-3.10.0-1.5.pre
```