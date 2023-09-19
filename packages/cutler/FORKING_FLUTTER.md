`cutler` intends to replaces some of this, but not all of it.
Keeping these docs until `cutler` is fully functional.

`dart run cutler versions` is able to print out all of the hashes in the forked
repos for a given Shorebird hash (including any Shorebird channel or release
tag).

Example:
```
 % dart run cutler versions
Building package executable... 
Built cutler:cutler.
Using /Users/eseidel/Documents/GitHub as checkouts root.
✓ Checkouts updated! (15.9s)
Shorebird @ origin/stable
  flutter   012153de178d4a51cd6f9adc792ad63ae3cfb1b3 (8 ahead)
  engine    5a1c263ce5313c8f5e93a11dd2a3af0e19d90262 (54 ahead)
  dart      37f38201922b071c5494e35fe09b56336f03a4f6 (13 ahead)
  buildroot 320eae0a60e36365e90b4380f5eb0b3fd4392f67 (1 ahead)

Upstream
  flutter   2524052335ec76bb03e04ede244b071f1b86d190 (3.13.3)
  engine    b8d35810e91ab8fc39ba5e7a41bff6f697e8e3a8 (3.13.3)
  dart      efd81da467c5cfeaa39652bd865ce91830a66ab7 (3.1.1)
  buildroot 6e71c38443c0bf9d8954c87bf69bb4e019f44f94
```

## Repository structure

We maintain forks of:
* flutter/flutter
* flutter/engine
* flutter/buildroot
* dart-lang/sdk

We keep our forked changes on the `shorebird/dev` branch of each repo which we
rebase periodically on top of the latest stable from the upstream repos.

When Flutter makes a release, we rebase our `shorebird/dev` branches onto
the branch points for Flutter's release branches.  We then create our own
release branches for the Shorebird release (e.g. flutter_release/3.7.10).

The only reason we need to create branches is to keep our forked commits alive.
You don't directly check out these branches (unless you plan to make a hotfix)
but instead Shorebird will pull them using its `flutter.version` file, etc.

We keep channel branches (e.g. `stable`) in the `shorebird` repo but
do not do so in the other repos.

The forked repos have branches corresponding to a Flutter release but do not
keep branches corresponding to Shorebird or Flutter channels.

For example, when updating to the Flutter 3.7.10 release, we created the
following branches:
* flutter/flutter: `flutter_release/3.7.10`
* flutter/engine: `flutter_release/3.7.10`
* flutter/buildroot: `flutter_release/3.7.10`
* dart-lang/sdk: `flutter_release/3.7.10`
* shorebird: no branch or tag, just a commit to the `main` branch which
  will eventually get pushed to the `stable` branch for Shorebird.

It's rare that we will ever need to add commits to one of these branches,
since changes to our fork are rare.  We currently do not try to back-port
any Shorebird changes to older Flutter revisions, rather we just update
to the latest Flutter release and include our new fixes there.
https://github.com/shorebirdtech/shorebird/issues/1100

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
which will result in an `engine` directory in the same directory as `_shorebird`.

Run `cutler` to get the git commands you need.

`cutler` has a set of fallback paths it will search to find your checkouts root
if you checked out `_shorebird` into the same directory as `engine`, it should
find it.


The steps to update our repos:

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

12. Sync our tags with the upstream (https://github.com/flutter/flutter):
```
git fetch --tags upstream
git push --tags
```

13. If there were changes to the `patch` binary in the `updater` library we
will need to trigger github actions before we can publish the new version of
the shorebird engine.

14. Before we can publish the new version of Shorebird, we need to build the
engine for all the platforms we support.  We do that by running the
`build_and_upload.sh` script in the build_engine repo.

```
./build_engine/build_engine/build_and_upload.sh ./engine 978a56f2d97f9ce24a2b6bc22c9bbceaaba0343c  
```

That script should be run in the cloud, but right now I've not figured that out
yet, so we run it locally on an arm64 Mac.

15. Once we've built all artifacts the final step is to push the new version
of shorebird to the appropriate branch.  e.g.
(untested)
```
cd $HOME/Documents/GitHub/_shorebird/shorebird
git tag -a -m "shorebird-3.10.0-1.5.pre" shorebird-3.10.0-1.5.pre $VERSION
git push origin shorebird-3.10.0-1.5.pre
git push origin/beta shorebird-3.10.0-1.5.pre
```
