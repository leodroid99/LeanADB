$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'LeanADB.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('LeanADB-Smoke-' + [guid]::NewGuid().ToString('N'))

try {
    & $scriptPath -Action Install -AcceptSdkLicense -InstallPath $testRoot -NoPath -NoShortcut -Quiet
    if ($LASTEXITCODE) {
        throw "Installer exited with code $LASTEXITCODE"
    }

    $state = Get-Content -LiteralPath (Join-Path $testRoot 'state.json') -Raw | ConvertFrom-Json
    if ($state.ProductId -ne 'LeanADB' -or -not $state.InstalledVersion) {
        throw 'Installed state is invalid.'
    }

    $adb = Join-Path $testRoot 'bin\adb.exe'
    $fastboot = Join-Path $testRoot 'bin\fastboot.exe'
    $adbOutput = (& $adb version 2>&1 | Out-String)
    $fastbootOutput = (& $fastboot --version 2>&1 | Out-String)
    if ($adbOutput -notmatch [regex]::Escape($state.InstalledVersion)) {
        throw 'ADB version does not match installed state.'
    }
    if ($fastbootOutput -notmatch [regex]::Escape($state.InstalledVersion)) {
        throw 'Fastboot version does not match installed state.'
    }

    & $scriptPath -Action AutoUpdate -InstallPath $testRoot -NoPath -NoShortcut -Quiet
    & $scriptPath -Action AutoUpdate -InstallPath $testRoot -Force -Quiet
    $updatedState = Get-Content -LiteralPath (Join-Path $testRoot 'state.json') -Raw | ConvertFrom-Json
    if ($updatedState.PathRegistered -or $updatedState.ShortcutRegistered) {
        throw 'A portable update unexpectedly enabled PATH or shortcut integration.'
    }
    $installedScript = Join-Path $testRoot 'LeanADB.ps1'
    & $installedScript -Action Uninstall -InstallPath $testRoot -NoPath -NoShortcut -Quiet
    for ($attempt = 0; $attempt -lt 20 -and (Test-Path -LiteralPath $testRoot); $attempt++) {
        Start-Sleep -Milliseconds 250
    }
    if (Test-Path -LiteralPath $testRoot) {
        throw 'Uninstall did not remove the test installation.'
    }

    Write-Host "LeanADB smoke test passed for Platform-Tools $($state.InstalledVersion)."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
