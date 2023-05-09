# Cutler
A tool for managing our fork of Flutter

"Someone who makes or sells cutlery is a cutler." - Wikipedia

"Forks are considered cutlery, right?" - Me


## Usage

Typical usage:
```
dart run cutler --root=$HOME/Documents/GitHub --dry-run
```

If you're running `cutler` repeatedly, you might also use `--no-update` after
the first run to avoid waiting to try and update git repos.

You can also see what the current stable changes would look like applied to
another Flutter channel with `--flutter-channel`, e.g.:
```
dart run cutler --root=$HOME/Documents/GitHub --dry-run --flutter-channel=beta
```

`--dry-run` will show you the changes it plans to make.  Actually making the
changes might work, but hasn't been tested yet.

Example invocation, exploring porting a 3.7.12 based fork onto 3.10 (beta):
```
% dart run cutler --root=$HOME/Documents/GitHub --dry-run --no-update --flutter-channel=beta
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
Updating shorebird flutter version...
  Change flutter.version: new-flutter-hash from 83305b5088e6fe327fb3334a73ff190828d85713
```
