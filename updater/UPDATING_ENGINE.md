Shorebird currently maintains patches to the Flutter Engine to integrate the Shorebird updater library.

We have changes to both flutter/engine and flutter/buildroot.  We need to make sure those changes are applied to the correct version of each, to be compatible with a given `flutter/flutter` version.

* flutter/flutter version is whatever is the latest `stable` in flutter/flutter.
* From that you can get the `flutter/engine` version in `bin/internal/engine.version` in flutter/flutter.
* From that you can get the `flutter/buildroot` version in `DEPS` in `flutter/engine`

Working from a `flutter/engine` checkout can be confusing because the layout is:
src/ <- `flutter/buildroot`
src/flutter <- `flutter/engine`

`gclient` uses the file in `src/flutter/DEPS` to control the whole checkout, as directed by your `.gclient` file in the parent directory of `src`.

Here are the steps to update those forks every time Flutter releases:

1. You need the release name / git id for the Flutter release. e.g. 3.7.7
1. Fetch flutter at that tag
1. Look at engine version https://github.com/flutter/flutter/blob/3.7.7/bin/internal/engine.version
See that is 1837b5be5f0f1376a1ccf383950e83a80177fb4e.
1. Rebase our engine patches onto that engine version. https://github.com/shorebirdtech/engine/tree/stable_codepush
If the engine is tagged correctly (it isn't always) it's as simple as:
`git rebase --onto 3.7.7 3.7.6
1. Should then also look at DEPS file in engine: https://github.com/flutter/engine/blob/3.7.7/DEPS
Where we are looking for the buildroot hash: https://github.com/flutter/engine/blob/3.7.7/DEPS#L239
1. We now need to rebase the buildroot (src/) changes onto the buildroot version in that DEPS. https://github.com/shorebirdtech/buildroot/tree/stable_codepush
e.g. `git rebase --onto 8747bce41d0dc6d9dc45c4d1b46d2100bb9ee688 93f7f85422a8604bdc44ef76c3f105ead65e8c1c`
Where as that should be `--onto new_base_revision previous_base_revision`.  The base revision is the git id *before* we started making changes.
1. Once you've successfully rebased the buildroot, you then need to change the buildroot id in our fork of the engine (so that when others use `gclient sync` it pulls our modified buildroot rather than an unmodified one.

