`assetutil --info` dumps of a compiled asset catalog containing an iOS 18
layered icon (`.icon`) bundle. These back the `sanitizeCarJson` tests.

Files:

- layered_icon_build_a.json and layered_icon_build_b.json are two compiles of
  the *same* icon, unchanged between runs. They differ only in `Timestamp`,
  `RenditionName` and `SHA1Digest`, all of which `actool` regenerates every
  build. Sanitizing both must produce the same string, otherwise Shorebird
  reports an asset change to a user who did not make one.

To regenerate, author a `.icon` bundle and compile it twice. Icon Composer
ships inside Xcode, but the bundle is a plain directory and can be written by
hand, which is how these were made:

```
MyIcon.icon/
  icon.json
  Assets/{back,front}.png    # any two 1024x1024 PNGs
```

```json
{
  "fill" : { "automatic-gradient" : "extended-srgb:0.1,0.36,0.72,1.0" },
  "groups" : [
    { "layers" : [ { "image-name" : "front.png" },
                   { "image-name" : "back.png" } ] }
  ],
  "supported-platforms" : { "circles" : [ "watchOS" ], "squares" : "shared" }
}
```

```sh
for n in a b; do
  xcrun actool --compile "out_$n" --platform iphoneos \
    --minimum-deployment-target 18.0 --app-icon MyIcon \
    --output-partial-info-plist "out_$n/partial.plist" \
    --include-all-app-icons MyIcon.icon
  assetutil --info "out_$n/Assets.car" -o "out_$n/assets.json"
done
```
