$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'LeanADB.ps1'
$unicodeWord = -join @([char]0xD68C, [char]0xADC0)
$testPrefix = 'Lean ADB ' + $unicodeWord + ' & bang! [space]-'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ($testPrefix + [guid]::NewGuid().ToString('N'))
$testFilesRoot = $testRoot + '-Files'
$pathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\LeanADB'
$uninstallLocationBefore = if (Test-Path -LiteralPath $uninstallKey) { [string](Get-ItemProperty -LiteralPath $uninstallKey).InstallLocation } else { '' }

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

try {
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
        -Action Status -InstallPath $env:LOCALAPPDATA -Quiet *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'LeanADB accepted LocalAppData itself as an unsafe installation root.'

    & $scriptPath -Action Install -AcceptSdkLicense -InstallPath $testRoot -NoPath -NoShortcut -Quiet

    $statePath = Join-Path $testRoot 'state.json'
    Assert-True (Test-Path -LiteralPath $statePath -PathType Leaf) 'state.json was not created.'
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-True ($state.ProductId -eq 'LeanADB') 'Unexpected product ID.'
    Assert-True ($state.Publisher -eq 'leodroid99') 'Unexpected publisher.'
    Assert-True ($state.LeanADBVersion -eq (Get-Content (Join-Path $projectRoot 'VERSION') -Raw).Trim()) 'LeanADB version was not recorded.'
    Assert-True ($state.LayoutVersion -eq 1) 'Unexpected installation layout.'
    Assert-True ($state.LicenseUrl -eq 'https://developer.android.com/studio/terms') 'SDK license URL was not recorded.'
    Assert-True ([bool]$state.LicenseAcceptedUtc) 'SDK license acceptance time was not recorded.'
    Assert-True (Test-Path -LiteralPath (Join-Path $testRoot 'VERSION') -PathType Leaf) 'Installed VERSION file is missing.'
    Assert-True (-not [bool]$state.PathRegistered) 'Portable test unexpectedly registered PATH.'
    Assert-True (-not [bool]$state.ShortcutRegistered) 'Portable test unexpectedly registered a shortcut.'
    New-Item -ItemType Directory -Path $testFilesRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $testFilesRoot 'keep.txt') -Value 'user file' -Encoding ASCII

    $requiredFiles = @(
        'adb.exe', 'fastboot.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll',
        'libwinpthread-1.dll', 'mke2fs.exe', 'mke2fs.conf',
        'make_f2fs.exe', 'make_f2fs_casefold.exe', 'NOTICE.txt', 'source.properties'
    )
    $binPath = Join-Path $testRoot 'bin'
    foreach ($name in $requiredFiles) {
        Assert-True (Test-Path -LiteralPath (Join-Path $binPath $name) -PathType Leaf) "Missing installed file: $name"
    }

    $menuLauncher = Join-Path $testRoot 'Open LeanADB.cmd'
    Assert-True (Test-Path -LiteralPath $menuLauncher -PathType Leaf) 'Easy-menu launcher was not created.'
    $menuLauncherText = Get-Content -LiteralPath $menuLauncher -Raw
    Assert-True ($menuLauncherText -match '-Action Menu') 'Easy-menu launcher does not start the Menu action.'
    Assert-True ($menuLauncherText -match '-Action AutoUpdate') 'Easy-menu launcher does not check for updates.'

    & (Join-Path $testRoot 'LeanADB.ps1') -Action Status -InstallPath $testRoot -Quiet | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'LeanADB status and PATH-resolution diagnostics failed.'

    foreach ($name in @('adb.exe', 'fastboot.exe')) {
        $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $binPath $name)
        Assert-True ($signature.Status -eq 'Valid') "$name has an invalid signature."
        Assert-True ($signature.SignerCertificate.Subject -match '(^|,\s*)O=Google LLC(,|$)') "$name was not signed by Google LLC."
    }

    $adb = Join-Path $binPath 'adb.exe'
    $fastboot = Join-Path $binPath 'fastboot.exe'
    $adbVersion = (& $adb version 2>&1 | Out-String)
    $fastbootVersion = (& $fastboot --version 2>&1 | Out-String)
    Assert-True ($adbVersion -match [regex]::Escape([string]$state.InstalledVersion)) 'ADB version mismatch.'
    Assert-True ($fastbootVersion -match [regex]::Escape([string]$state.InstalledVersion)) 'Fastboot version mismatch.'

    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    & $adb start-server 2>&1 | Out-Null
    $startServerExit = $LASTEXITCODE
    & $adb devices 2>&1 | Out-Null
    $devicesExit = $LASTEXITCODE
    & $adb kill-server 2>&1 | Out-Null
    $ErrorActionPreference = $savedPreference
    Assert-True ($startServerExit -eq 0) 'ADB server failed to start.'
    Assert-True ($devicesExit -eq 0) 'adb devices failed.'

    & (Join-Path $testRoot 'LeanADB.ps1') -Action Devices -InstallPath $testRoot -Quiet
    Assert-True ($LASTEXITCODE -eq 0) 'LeanADB device discovery failed after a clean ADB server start.'

    $updateLauncher = Join-Path $testRoot 'Update LeanADB.cmd'
    & $updateLauncher
    $updateExitCode = $LASTEXITCODE
    Assert-True ($updateExitCode -eq 0) "Generated update launcher failed with exit code $updateExitCode."

    & (Join-Path $testRoot 'LeanADB.ps1') -Action AutoUpdate -InstallPath ($testRoot + '\') -Quiet
    Assert-True ($LASTEXITCODE -eq 0) 'AutoUpdate rejected a trailing-slash installation path.'

    $pathAfterOperations = [Environment]::GetEnvironmentVariable('Path', 'User')
    Assert-True ($pathAfterOperations -eq $pathBefore) 'Portable operations changed the user PATH.'
    $uninstallLocationAfter = if (Test-Path -LiteralPath $uninstallKey) { [string](Get-ItemProperty -LiteralPath $uninstallKey).InstallLocation } else { '' }
    Assert-True ($uninstallLocationAfter -eq $uninstallLocationBefore) 'Portable operations changed another installation uninstall registration.'

    $uninstallLauncher = Join-Path $testRoot 'Uninstall LeanADB.cmd'
    & $uninstallLauncher /quiet
    $uninstallExitCode = $LASTEXITCODE
    Assert-True ($uninstallExitCode -eq 0) "Generated uninstaller failed with exit code $uninstallExitCode."
    for ($attempt = 0; $attempt -lt 20 -and (Test-Path -LiteralPath $testRoot); $attempt++) {
        Start-Sleep -Milliseconds 250
    }
    Assert-True (-not (Test-Path -LiteralPath $testRoot)) 'Generated uninstaller left the installation directory behind.'
    Assert-True (Test-Path -LiteralPath (Join-Path $testFilesRoot 'keep.txt') -PathType Leaf) 'Portable uninstall removed saved user files.'
    $uninstallLocationFinal = if (Test-Path -LiteralPath $uninstallKey) { [string](Get-ItemProperty -LiteralPath $uninstallKey).InstallLocation } else { '' }
    Assert-True ($uninstallLocationFinal -eq $uninstallLocationBefore) 'Portable uninstall removed another installation registration.'

    Write-Host "LeanADB regression test passed for Platform-Tools $($state.InstalledVersion)."
}
finally {
    [Environment]::SetEnvironmentVariable('Path', $pathBefore, 'User')
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolvedTestRoot.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Path]::GetFileName($resolvedTestRoot).StartsWith($testPrefix, [StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $resolvedTestRoot) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
        }
    }
    $resolvedFilesRoot = [System.IO.Path]::GetFullPath($testFilesRoot).TrimEnd('\')
    if ($resolvedFilesRoot.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Path]::GetFileName($resolvedFilesRoot).StartsWith($testPrefix, [StringComparison]::Ordinal) -and
        $resolvedFilesRoot.EndsWith('-Files', [StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $resolvedFilesRoot) {
            Remove-Item -LiteralPath $resolvedFilesRoot -Recurse -Force
        }
    }
}
