# cspell:words LASTEXITCODE
# This is the windows equivalent of the `third_party/flutter/bin/internal/shared.sh` script
# compiles `shorebird_cli/bin/shorebird_cli.dart` to `bin/cache/shorebird.snapshot`

$ErrorActionPreference = "Stop"

# We are running from $shorebirdRootDir\bin
$shorebirdBinDir = (Get-Item $PSScriptRoot).FullName
$shorebirdRootDir = (Get-Item $shorebirdBinDir\..\).FullName
$flutterVersion = Get-Content "$shorebirdBinDir\internal\flutter.version"
$shorebirdCacheDir = [IO.Path]::Combine($shorebirdRootDir, "bin", "cache")
$shorebirdCliDir = [IO.Path]::Combine($shorebirdRootDir, "packages", "shorebird_cli")
# shorebird.bat builds the same dart and snapshot paths; keep them in sync.
$snapshotPath = [IO.Path]::Combine($shorebirdCacheDir, "shorebird.snapshot")
$stampPath = [IO.Path]::Combine($shorebirdCacheDir, "shorebird.stamp")
$flutterPath = [IO.Path]::Combine($shorebirdCacheDir, "flutter", $flutterVersion)
$flutter = [IO.Path]::Combine($shorebirdCacheDir, "flutter", $flutterVersion, "bin", "flutter.bat")
$shorebirdScript = [IO.Path]::Combine($shorebirdCliDir, "bin", "shorebird.dart")
$dart = [IO.Path]::Combine($flutterPath, "bin", "cache", "dart-sdk", "bin", "dart.exe")

# Executes $command and redirects as much output to $null as possible.
#
# This is a workaround for old versions of Powershell treating any write to
# the Error stream with $ErrorActionPreference = "Stop" as a terminating error.
# This is fixed in Powershell 7.1.
# 
# See https://github.com/PowerShell/PowerShell/issues/4002 for more info.
function Invoke-SilentlyIfNeeded($command) {
    $psVersion = $PSVersionTable.PSVersion
    $isErrorStreamIssueFixed = $psVersion.Major -ge 7 -and $psVersion.Minor -ge 1
    if ($isErrorStreamIssueFixed) {
        # Execute the command with no redirection.
        & $command
    }
    else {
        # Otherwise redirect everything _but_ the Error stream to $null. See
        # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_output_streams?view=powershell-7.3#long-description
        # for a description of these streams.
        & $command  1> $null 3> $null 4> $null 5> $null 6> $null
    }
}

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
    $pubspecLockFile = [System.IO.FileInfo] "$shorebirdRootDir\pubspec.lock"

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
        # Keep the default in sync with defaultFlutterGitUrl in
        # shorebird_env.dart.
        $flutterGitUrl = 'https://github.com/shorebirdtech/flutter.git'
        if ($env:SHOREBIRD_FLUTTER_GIT_URL) {
            $flutterGitUrl = $env:SHOREBIRD_FLUTTER_GIT_URL
        }
        # Flutter has paths over Windows' 260-character limit. Setting
        # core.longpaths in the clone's own config lets the checkout write
        # them without a machine-wide (admin) git setting.
        Invoke-SilentlyIfNeeded {
            git clone --filter=tree:0 --config core.longpaths=true "$flutterGitUrl" --no-checkout "$flutterPath"
        }
    }
    else {
        Invoke-SilentlyIfNeeded {
            git -C "$flutterPath" fetch
        }
    }

    Invoke-SilentlyIfNeeded {
        # -c to avoid printing a warning about being in a detached head state.
        git -C "$flutterPath" -c advice.detachedHead=false checkout "$flutterVersion"
    }

    # Set FLUTTER_STORAGE_BASE_URL to Shorebird's download host and execute a
    # `flutter` command to trigger a download of Dart, etc. Keep the default and
    # the trailing slash handling in sync with ShorebirdEnv.downloadUrl.
    if ($env:SHOREBIRD_DOWNLOAD_URL) {
        $env:FLUTTER_STORAGE_BASE_URL = $env:SHOREBIRD_DOWNLOAD_URL.TrimEnd('/');
    }
    else {
        $env:FLUTTER_STORAGE_BASE_URL = 'https://download.shorebird.dev';
    }
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
    & $dart pub get
    Pop-Location
    # pub get may not update pubspec.lock's mtime if dependencies are unchanged,
    # which would cause the pubspec.yaml -gt pubspec.lock check to keep
    # triggering a rebuild on every invocation.
    (Get-Item "$shorebirdRootDir/pubspec.lock").LastWriteTime = Get-Date

    Write-Output "Compiling shorebird..."

    # Compile our snapshot
    # We invoke `$SNAPSHOT_PATH completion` to trigger the "completion" command, which
    # avoids executing as much of our code as possible. We do this because running
    # the script here (instead of from the compiled snapshot) invalidates a lot of
    # assumptions we make about the cwd in the shorebird_cli tool.
    & $dart --verbosity=error --disable-dart-dev --snapshot="$snapshotPath" `
        --snapshot-kind="app-jit" --packages="$shorebirdRootDir/.dart_tool/package_config.json" `
        --no-enable-mirrors "$shorebirdScript" completion > $null

    Write-Debug "writing $compileKey to $stampPath"
    Set-Content -Path $stampPath -Value $compileKey
}

# PowerShell drops the first `--` from a script's arguments: in
# `shorebird release android -- --dart-define=FOO=bar`, $args holds `release`,
# `android` and `--dart-define=FOO=bar`. shorebird needs the `--` to tell its
# own options from the ones it passes to Flutter, so put it back, at the place
# the command's source text shows. Arguments after `--` are all positional, so
# each element of the source after it is one argument, counted from the end.
#
# `powershell -File` keeps `--` and has no source text (shorebird.bat runs dart
# itself and doesn't come through here); anything this can't match to its
# source (a splat, a line continued onto the next line in Windows PowerShell)
# is passed on as it came.
function Restore-EndOfOptions($arguments, $invocation) {
    # Statement holds the whole statement (PowerShell 7.4+); Line, only the
    # first line of it. Read Statement through PSObject: older versions don't
    # have it, and under Set-StrictMode reading a missing property throws.
    $source = $null
    $statement = $invocation.PSObject.Properties['Statement']
    if ($statement) { $source = $statement.Value }
    if (!$source) { $source = $invocation.Line }
    if (!$source -or $source.TrimEnd().EndsWith('`')) { return $arguments }

    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) { return $arguments }

    # Find this command in the statement: by name, or by the call operator
    # (`& $path`) when that's how it was run.
    $commands = @($ast.FindAll({
                param($node)
                if ($node -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
                if ($invocation.InvocationName -in '&', '.') {
                    return $node.InvocationOperator -ne [System.Management.Automation.Language.TokenKind]::Unknown
                }
                return $node.CommandElements[0].Extent.Text -eq $invocation.InvocationName
            }, $true))
    if ($commands.Count -ne 1) { return $arguments }

    $elements = $commands[0].CommandElements
    $separator = -1
    for ($i = 1; $i -lt $elements.Count; $i++) {
        if ($elements[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and $elements[$i].Extent.Text -eq '--') {
            $separator = $i
            break
        }
    }
    if ($separator -lt 0) { return $arguments }

    $after = @($elements | Select-Object -Skip ($separator + 1))
    if ($after.Count -gt $arguments.Count) { return $arguments }
    $at = $arguments.Count - $after.Count
    for ($i = 0; $i -lt $after.Count; $i++) {
        $element = $after[$i]
        if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) {
            return $arguments
        }
        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $element.Value -cne $arguments[$at + $i]) {
            return $arguments
        }
    }
    # Insert by index: the pipeline (Select-Object) would drop $null arguments
    # and shift where `--` goes.
    $restored = [System.Collections.ArrayList]::new($arguments)
    $restored.Insert($at, '--')
    return $restored.ToArray()
}

Test-GitInstalled

$shorebirdArgs = @(Restore-EndOfOptions $args $MyInvocation)

if (Test-ShorebirdNeedsUpdate) {
    Update-Shorebird
}

# shorebird.bat runs the snapshot itself, so cmd's arguments reach dart as typed.
if ($env:SHOREBIRD_SETUP_ONLY) {
    exit 0
}

& $dart --disable-dart-dev --packages="$shorebirdRootDir\.dart_tool\package_config.json" "$snapshotPath" $shorebirdArgs
# Exit with the CLI's exit code; otherwise powershell -File exits 0.
exit $LASTEXITCODE
