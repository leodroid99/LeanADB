$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot 'LeanADB.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-offline-test-' + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $testRoot 'installed'
$zipPath = Join-Path $testRoot 'official.zip'
$originalErrorLog = Join-Path ([IO.Path]::GetTempPath()) 'LeanADB-install-error.log'
$hadErrorLog = Test-Path -LiteralPath $originalErrorLog -PathType Leaf
$savedErrorLog = if ($hadErrorLog) { [IO.File]::ReadAllBytes($originalErrorLog) } else { $null }

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' `
        -OutFile $zipPath -UseBasicParsing -TimeoutSec 180

    & $scriptPath -Action Install -AcceptSdkLicense -InstallPath $installRoot -NoPath -NoShortcut -OfflineZipPath $zipPath -Quiet
    Assert-True ($LASTEXITCODE -eq 0) 'Offline installation failed.'
    $statePath = Join-Path $installRoot 'state.json'
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($state.LastCheckStatus -eq 'Offline') 'Offline installation claimed an online version comparison.'
    Assert-True (-not $state.PathRegistered -and -not $state.ShortcutRegistered) 'Offline installation changed user integration settings.'
    Assert-True ((Test-Path -LiteralPath (Join-Path $installRoot 'bin\adb.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $installRoot 'bin\fastboot.exe') -PathType Leaf)) 'Offline package missed ADB or Fastboot.'

    $outputFolder = Join-Path $testRoot 'saved-files'
    $state | Add-Member -NotePropertyName OutputFolder -NotePropertyValue $outputFolder -Force
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
    & $scriptPath -Action Update -InstallPath $installRoot -OfflineZipPath $zipPath -Quiet
    Assert-True ($LASTEXITCODE -eq 0) 'Offline update failed.'
    $updated = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($updated.OutputFolder -eq $outputFolder) 'Update erased the selected file save location.'
    Assert-True ($updated.LastCheckStatus -eq 'Offline') 'Offline update claimed online freshness.'

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $badZip = Join-Path $testRoot 'traversal.zip'
    $archive = [IO.Compression.ZipFile]::Open($badZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $archive.CreateEntry('platform-tools/../outside.txt')
        $writer = New-Object IO.StreamWriter($entry.Open())
        try { $writer.Write('unsafe') } finally { $writer.Dispose() }
    }
    finally { $archive.Dispose() }
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-ArchiveSafety' }, $true)
    if ($null -eq $definition) { throw 'Archive safety function was not found.' }
    . ([scriptblock]::Create($definition.Extent.Text))
    $rejected = $false
    try { Assert-ArchiveSafety -ZipPath $badZip } catch { $rejected = $true }
    Assert-True $rejected 'Path traversal in a local ZIP was accepted.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $testRoot 'outside.txt'))) 'A traversal ZIP escaped the test directory.'

    & (Join-Path $installRoot 'LeanADB.ps1') -Action Uninstall -InstallPath $installRoot -Quiet
    Assert-True ($LASTEXITCODE -eq 0) 'Offline test uninstall failed.'
    Write-Host "LeanADB offline install/update test passed for Platform-Tools $($updated.InstalledVersion)."
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $resolved = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolved.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved).StartsWith('LeanADB-offline-test-', [StringComparison]::Ordinal) -and
        (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    if ($hadErrorLog) { [IO.File]::WriteAllBytes($originalErrorLog, $savedErrorLog) }
    elseif (Test-Path -LiteralPath $originalErrorLog) { Remove-Item -LiteralPath $originalErrorLog -Force }
}
