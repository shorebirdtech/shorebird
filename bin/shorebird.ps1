# This is the windows equivalent of the `third_party/flutter/bin/internal/shared.sh` script
# compiles `shorebird_cli/bin/shorebird_cli.dart` to `bin/cache/shorebird.shapshot`

# We are running from $shorebirdRootDir\bin
$shorebirdBinDir = (Get-Item $PSScriptRoot).FullName
$shorebirdRootDir = (Get-Item $shorebirdBinDir\..\).FullName
$shorebirdCacheDir = [IO.Path]::Combine($shorebirdRootDir, "bin", "cache")
$shorebirdCliDir = [IO.Path]::Combine($shorebirdRootDir, "packages", "shorebird_cli")
$snapshotPath = [IO.Path]::Combine($shorebirdCacheDir, "shorebird.snapshot")
$stampPath = [IO.Path]::Combine($shorebirdCacheDir, "shorebird.stamp")
$flutterPath = [IO.Path]::Combine($shorebirdCacheDir, "flutter")
$flutter = [IO.Path]::Combine($shorebirdCacheDir, "flutter", "bin", "flutter.bat")
$shorebirdScript = [IO.Path]::Combine($shorebirdCliDir, "bin", "shorebird.dart")
$dart = [IO.Path]::Combine($flutterPath, "bin", "cache", "dart-sdk", "bin", "dart.exe")

function Update-Flutter {
    if (!(Test-Path $flutterPath)) {
        Write-Output "Cloning flutter, this may take a bit..."
        git clone --filter=tree:0 https://github.com/shorebirdtech/flutter.git --no-checkout "$flutterPath" *> $null
    }
    else {
        git -C "$flutterPath" fetch *> $null
    }

    $flutterVersion = Get-Content "$shorebirdBinDir\internal\flutter.version"

    # -c to avoid printing a warning about being in a detached head state.
    git -C "$flutterPath" -c advice.detachedHead=false checkout "$flutterVersion" *> $null

    # Set FLUTTER_STORAGE_BASE_URL=https://download.shorebird.dev and execute
    # a `flutter` command to trigger a download of Dart, etc.
    $env:FLUTTER_STORAGE_BASE_URL = 'https://download.shorebird.dev';
    & $flutter --version
    Remove-Item Env:\FLUTTER_STORAGE_BASE_URL
}

function Update-Shorebird {
    # Invalidate cache if:
    #  * snapshotFile is not a file, or
    #  * stampFile is not a file, or
    #  * stampFile is an empty file, or
    #  * Contents of stampFile contains a different git hash than HEAD, or
    #  * pubspec.yaml last modified after pubspec.lock
    $snapshotFile = [System.IO.FileInfo] $snapshotPath
    $stampFile = [System.IO.FileInfo] $stampPath
    $pubspecFile = [System.IO.FileInfo] "$shorebirdCliDir\pubspec.yaml"
    $pubspecLockFile = [System.IO.FileInfo] "$shorebirdCliDir\pubspec.lock"
    
    $gitDir = [IO.Path]::Combine($shorebirdRootDir, ".git")
    # This git command prints the git-dir and then the hash of HEAD. We only want the hash of HEAD.
    $compileKey = (& { git rev-parse --git-dir=$gitDir HEAD } -split)[-1]
    
    Write-Debug "Checking whether shorebird needs to be rebuilt"

    Write-Debug "compileKey is $compileKey"
    Write-Debug "Snapshot file exists: $($snapshotFile.Exists)"
    Write-Debug "Stamp file: $($stampFile)"
    Write-Debug "Stamp file exists: $($stampFile.Exists)"
    Write-Debug "pubspec.yaml file exists: $($pubspecFile.Exists)"
    Write-Debug "pubspec.lock file exists: $($pubspecLockFile.Exists)"
    if ($stampFile.Exists) {
        Write-Debug "contents of stamp file: $(Get-Content $stampFile)"
    }
    
    $invalidateCache = !$snapshotFile.Exists -or `
        !$stampFile.Exists -or `
        $stampFile.Length -eq 0 -or `
        (Get-Content $stampFile) -ne $compilekey -or `
        $pubspecFile.LastWriteTime -gt $pubspecLockFile.LastWriteTime
    
    Write-Debug "Invalidate cache: $invalidateCache"

    if ($invalidateCache) {
        Update-Flutter

        Write-Output "Compiling shorebird..."

        & $dart --verbosity=error --disable-dart-dev --snapshot="$snapshotPath" `
            --snapshot-kind="app-jit" --packages="$shorebirdCliDir/.dart_tool/package_config.json" `
            --no-enable-mirrors "$shorebirdScript" > $null

        Write-Debug "writing $compileKey to $stampPath"
        Set-Content -Path $stampPath -Value $compileKey
    } else {
        Write-Debug "Shorebird is up-to-date"
    }
}

Update-Shorebird

& $dart --disable-dart-dev --packages="$shorebirdCliDir\.dart_tool\package_config.json" "$snapshotPath" $args
