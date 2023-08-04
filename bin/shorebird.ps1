# This is the windows equivalent of the `third_party/flutter/bin/internal/shared.sh` script
# compiles `shorebird_cli/bin/shorebird_cli.dart` to `bin/cache/shorebird.shapshot`

# We are running from $shorebirdRootDir\bin
$shorebirdBinDir = (Get-Item $PSScriptRoot).FullName
$shorebirdRootDir = (Get-Item $shorebirdBinDir\..\).FullName
$flutterVersion = Get-Content "$shorebirdBinDir\internal\flutter.version"
$shorebirdCacheDir = [IO.Path]::Combine($shorebirdRootDir, "bin", "cache")
$shorebirdCliDir = [IO.Path]::Combine($shorebirdRootDir, "packages", "shorebird_cli")
$snapshotPath = [IO.Path]::Combine($shorebirdCacheDir, "shorebird.snapshot")
$stampPath = [IO.Path]::Combine($shorebirdCacheDir, "shorebird.stamp")
$flutterPath = [IO.Path]::Combine($shorebirdCacheDir, "flutter", $flutterVersion)
$flutter = [IO.Path]::Combine($shorebirdCacheDir, "flutter", $flutterVersion, "bin", "flutter.bat")
$shorebirdScript = [IO.Path]::Combine($shorebirdCliDir, "bin", "shorebird.dart")
$dart = [IO.Path]::Combine($flutterPath, "bin", "cache", "dart-sdk", "bin", "dart.exe")

function Test-GitInstalled {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Debug "Git is installed."
    }
    else {
        Write-Output "No git installation detected. Git is required to use shorebird."
        exit 1
    }
}

function Test-ShorebirdNeedsUpdate {
    Write-Debug "Checking whether shorebird needs to be rebuilt"

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

    Push-Location $shorebirdRootDir
    $compileKey = & { git rev-parse HEAD } -split
    Pop-Location

    if (!$snapshotFile.Exists) {
        Write-Debug "snapshot file does not exist, shorebird needs update"
        return $true
    }

    if (!$stampFile.Exists) {
        Write-Debug "stamp file does not exist at $($stampFile), shorebird needs update"
        return $true
    }

    if ($stampFile.Length -eq 0) {
        Write-Debug "stamp file is empty, shorebird needs update"
        return $true
    }

    $stampFileContents = Get-Content $stampFile
    if ($stampFileContents -ne $compileKey) {
        Write-Debug "contents of stamp file do not match compile key ($($stampFileContents) vs $($compileKey)), shorebird needs update"
        return $true
    }

    if ($pubspecFile.LastWriteTime -gt $pubspecLockFile.LastWriteTime) {
        Write-Debug "pubspec.yaml updated more recently than pubspec.lock, shorebird needs update"
        return $true
    }

    Write-Debug "shorebird does not need update"
    return $false
}

function Update-Flutter {
    Write-Output "Updating Flutter..."

    if (!(Test-Path $flutterPath)) {
        Write-Output "Cloning flutter, this may take a bit..."
        git clone --filter=tree:0 https://github.com/shorebirdtech/flutter.git --no-checkout "$flutterPath" *> $null
    }
    else {
        git -C "$flutterPath" fetch *> $null
    }

    # -c to avoid printing a warning about being in a detached head state.
    git -C "$flutterPath" -c advice.detachedHead=false checkout "$flutterVersion" *> $null

    # Set FLUTTER_STORAGE_BASE_URL=https://download.shorebird.dev and execute
    # a `flutter` command to trigger a download of Dart, etc.
    $env:FLUTTER_STORAGE_BASE_URL = 'https://download.shorebird.dev';
    & $flutter --version
    Remove-Item Env:\FLUTTER_STORAGE_BASE_URL
}

function Update-Shorebird {
    Push-Location $shorebirdRootDir
    $compileKey = & { git rev-parse HEAD } -split
    Pop-Location
 
    Write-Output "Rebuilding shorebird..."

    Update-Flutter

    Push-Location $shorebirdCliDir
    & $dart pub upgrade
    Pop-Location

    Write-Output "Compiling shorebird..."

    & $dart --verbosity=error --disable-dart-dev --snapshot="$snapshotPath" `
        --snapshot-kind="app-jit" --packages="$shorebirdCliDir/.dart_tool/package_config.json" `
        --no-enable-mirrors "$shorebirdScript" > $null

    Write-Debug "writing $compileKey to $stampPath"
    Set-Content -Path $stampPath -Value $compileKey
}

Test-GitInstalled

if (Test-ShorebirdNeedsUpdate) {
    Update-Shorebird
}

& $dart --disable-dart-dev --packages="$shorebirdCliDir\.dart_tool\package_config.json" "$snapshotPath" $args
