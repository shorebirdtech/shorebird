Shorebird currently maintains patches to the Flutter Engine to integrate the Shorebird updater library.

Here are the steps to update those forks every time Flutter releases:

1. You need the release name / git id for the Flutter release.
1. Fetch flutter at that tag
1. Look at engine version https://github.com/flutter/flutter/blob/master/bin/internal/engine.version
1. Rebase our engine patches onto that engine version. https://github.com/shorebirdtech/engine/tree/stable_codepush
1. Should then also look at DEPS file in engine: https://github.com/flutter/engine/blob/main/DEPS
1. And then rebase the buildroot (src/) changes onto the buildroot version in that DEPS. https://github.com/shorebirdtech/buildroot/tree/stable_codepush
