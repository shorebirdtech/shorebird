# cspell:words ARCHITEW LASTEXITCODE nologo
#
# Pester tests of Install-PrebuiltCli (bin/shorebird.ps1), the Windows twin of
# tool/prebuilt_cli_test.sh: how bin/shorebird.ps1 installs the CLI
# publish_cli.yaml built for a stable commit, against a throwaway Shorebird
# root and a local HTTP server holding a fake CLI. publish_cli.yaml checks the
# real binary; this checks the install around it.
#
# Windows only: the fake CLI is compiled with the .NET Framework's csc.exe,
# and the install runs curl.exe. Needs Pester 5, git and python.
# Usage: Invoke-Pester tool/prebuilt_cli.Tests.ps1 -Output Detailed

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot\..").Path

    # bin/shorebird.ps1 runs as soon as it's loaded, so define only the
    # functions under test, from its source.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        "$repoRoot\bin\shorebird.ps1", [ref]$null, [ref]$null)
    $functions = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -in 'Install-PrebuiltCli', 'Test-PrebuiltIsCurrent'
        }, $false)
    if (@($functions).Count -ne 2) { throw "bin/shorebird.ps1 no longer defines both functions." }
    foreach ($function in $functions) {
        . ([scriptblock]::Create($function.Extent.Text))
    }

    $tmpRoot = Join-Path ([IO.Path]::GetTempPath()) "prebuilt_cli_$([guid]::NewGuid())"
    $www = Join-Path $tmpRoot www
    New-Item -ItemType Directory -Path $www -Force | Out-Null

    # Fake CLIs: each prints a version and exits with a code.
    $csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    function New-FakeCli($version, $code = 0) {
        $dir = Join-Path $tmpRoot "cli-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content "$dir\main.cs" "class P { static int Main() { System.Console.WriteLine(`"Shorebird $version`"); return $code; } }"
        & $csc /nologo "/out:$dir\shorebird.exe" "$dir\main.cs" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "csc failed." }
        return "$dir\shorebird.exe"
    }

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $server = Start-Process python -ArgumentList '-m', 'http.server', $port, '--bind', '127.0.0.1', '--directory', $www `
        -PassThru -WindowStyle Hidden
    $ready = $false
    for ($i = 0; $i -lt 100 -and !$ready; $i++) {
        try {
            Invoke-WebRequest "http://127.0.0.1:$port/" -UseBasicParsing | Out-Null
            $ready = $true
        }
        catch { Start-Sleep -Milliseconds 100 }
    }
    if (!$ready) { throw "The HTTP server didn't start." }
    $savedDownloadUrl = $env:SHOREBIRD_DOWNLOAD_URL
    $env:SHOREBIRD_DOWNLOAD_URL = "http://127.0.0.1:$port/"

    # A fresh Shorebird root, a git repo with one commit holding what the
    # install checks for local changes, with nothing published for it. Sets
    # the paths bin/shorebird.ps1 sets, where its functions read them.
    function New-Root {
        Get-ChildItem $www | Remove-Item -Recurse -Force
        $root = Join-Path $tmpRoot "root-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path "$root\bin\cache", "$root\packages" -Force | Out-Null
        Set-Content "$root\bin\shorebird.ps1" '# shorebird'
        Set-Content "$root\packages\pubspec.yaml" 'name: x'
        Set-Content "$root\.gitignore" 'bin/cache/'
        git -C $root init -q
        git -C $root add -A
        git -C $root -c user.name=t -c user.email=t@example.com commit -q -m init
        # Ends in a backslash, as Get-Item's FullName does in bin/shorebird.ps1.
        $global:shorebirdRootDir = "$root\"
        $global:shorebirdCacheDir = "$root\bin\cache"
        $global:stampPath = "$root\bin\cache\shorebird.stamp"
        $global:prebuiltPath = "$root\bin\cache\shorebird.exe"
        $global:prebuiltStampPath = "$root\bin\cache\shorebird-cli.stamp"
        return (git -C $root rev-parse HEAD).Trim()
    }

    # Publishes $zip for $revision as publish_cli.yaml does: the zip and its
    # checksum ($sha, default the zip's own).
    function Publish($revision, $zip, $sha = $null) {
        $dir = Join-Path $www "shorebird-cli\$revision"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Copy-Item $zip "$dir\shorebird-windows-x64.zip"
        if (!$sha) { $sha = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower() }
        Set-Content "$dir\shorebird-windows-x64.zip.sha256" "$sha  shorebird-windows-x64.zip"
    }

    function Publish-Cli($revision, $version, $code = 0) {
        $exe = New-FakeCli $version $code
        $zip = "$exe.zip"
        Compress-Archive -Path $exe -DestinationPath $zip
        Publish $revision $zip
    }

    function Assert-Installed($revision, $version, $result) {
        $result | Should -BeTrue
        (Get-Content $prebuiltStampPath -Raw).Trim() | Should -Be $revision
        (& $prebuiltPath --version) | Should -Be "Shorebird $version"
        Test-Path $stampPath | Should -BeFalse
        Get-ChildItem $shorebirdCacheDir -Filter 'shorebird-cli.*.tmp' | Should -BeNullOrEmpty
        Get-ChildItem $shorebirdCacheDir -Filter 'shorebird.exe.*.old' | Should -BeNullOrEmpty
        Test-PrebuiltIsCurrent $revision | Should -BeTrue
    }

    # A fallback: $false, and nothing that makes shorebird.ps1 run a binary.
    function Assert-Fallback($revision, $result) {
        $result | Should -BeFalse
        Test-Path $prebuiltStampPath | Should -BeFalse
        Test-Path $prebuiltPath | Should -BeFalse
        Get-ChildItem $shorebirdCacheDir -Filter 'shorebird-cli.*.tmp' | Should -BeNullOrEmpty
        Test-PrebuiltIsCurrent $revision | Should -BeFalse
    }
}

AfterAll {
    if ($server) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    $env:SHOREBIRD_DOWNLOAD_URL = $savedDownloadUrl
    Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Install-PrebuiltCli' {
    It 'installs the published CLI' {
        $revision = New-Root
        Publish-Cli $revision 1.2.3
        Assert-Installed $revision 1.2.3 (Install-PrebuiltCli $revision)
    }

    It 'falls back on a 404' {
        $revision = New-Root
        Assert-Fallback $revision (Install-PrebuiltCli $revision)
    }

    It 'falls back on a checksum mismatch' {
        $revision = New-Root
        $exe = New-FakeCli 1.2.3
        Compress-Archive -Path $exe -DestinationPath "$exe.zip"
        Publish $revision "$exe.zip" ('0' * 64)
        Assert-Fallback $revision (Install-PrebuiltCli $revision)
    }

    It 'falls back on a corrupt zip' {
        $revision = New-Root
        $zip = Join-Path $tmpRoot "corrupt-$([guid]::NewGuid()).zip"
        Set-Content $zip 'not a zip'
        Publish $revision $zip
        Assert-Fallback $revision (Install-PrebuiltCli $revision)
    }

    It 'falls back when the binary fails --version' {
        $revision = New-Root
        Publish-Cli $revision 1.2.3 1
        Assert-Fallback $revision (Install-PrebuiltCli $revision)
    }

    It 'falls back with local changes under <_>' -ForEach @(
        'bin\shorebird.ps1', 'packages\pubspec.yaml', 'third_party\new_file'
    ) {
        $revision = New-Root
        Publish-Cli $revision 1.2.3
        $path = Join-Path $shorebirdRootDir $_
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        Add-Content $path 'changed'
        Assert-Fallback $revision (Install-PrebuiltCli $revision)
    }

    It 'falls back on a platform with no binary' {
        $revision = New-Root
        Publish-Cli $revision 1.2.3
        $saved = $env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432
        try {
            $env:PROCESSOR_ARCHITECTURE = 'ARM64'
            $env:PROCESSOR_ARCHITEW6432 = $null
            $result = Install-PrebuiltCli $revision
        }
        finally {
            $env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432 = $saved
        }
        Assert-Fallback $revision $result
    }

    It 'upgrades a source-built install' {
        $revision = New-Root
        # What a source build of an earlier commit and an earlier binary leave.
        Set-Content $stampPath ('0' * 40)
        Copy-Item (New-FakeCli 1.0.0) $prebuiltPath
        Publish-Cli $revision 1.2.3
        Assert-Installed $revision 1.2.3 (Install-PrebuiltCli $revision)
    }
}
