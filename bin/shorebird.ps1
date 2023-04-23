# This is the windows equivalent of the `shorebird` script
# compiles `shorebird_cli/bin/shorebird_cli.dart` to `bin/cache/shorebird.shapshot`

# Set a variable fo shorebird_cli_dir
$bin_dir = (Get-Item $PSScriptRoot).FullName
$root_dir = (Get-Item $bin_dir\..\).FullName
$shorebird_cli_dir = "$root_dir\packages\shorebird_cli"
$cache_dir = "$bin_dir\cache"
$snapshot_path = "$cache_dir\shorebird.snapshot"
$flutter_path = "$cache_dir\flutter"
$flutter = "$cache_dir\flutter\bin\flutter.bat"
$dart = "$cache_dir\flutter\bin\cache\dart-sdk\bin\dart.exe"

# Read internal/flutter.version into a variable
$flutter_version = Get-Content "$shorebird_cli_dir\internal\flutter.version"

# Check if flutter_path exists
if (!(Test-Path $flutter_path)) {
    # If not, download it
    git clone --filter=tree:0 https://github.com/shorebirdtech/flutter.git --no-checkout "$flutter_path"
} else {
    # If it does, update it
    git -C "$flutter_path" fetch
}
# -c to avoid printing a warning about being in a detached head state.
git -C "$flutter_path" -c advice.detachedHead=false checkout "$flutter_version"

# Set FLUTTER_STORAGE_BASE_URL=https://download.shorebird.dev
# and call `flutter`
$env:FLUTTER_STORAGE_BASE_URL = 'https://download.shorebird.dev';
& $flutter --version
Remove-Item Env:\FLUTTER_STORAGE_BASE_URL

& $dart --disable-dart-dev --packages="%shorebird_cli_dir%\.dart_tool\package_config.json" "%snapshot_path%"