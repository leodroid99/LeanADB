$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $projectRoot 'dist\LeanADB-release.json'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-SelfUpdate-' + [guid]::NewGuid().ToString('N'))
$errorLogPath = Join-Path ([IO.Path]::GetTempPath()) 'LeanADB-install-error.log'
$errorLogExisted = Test-Path -LiteralPath $errorLogPath -PathType Leaf

try {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Build the release before running the self-update test.'
    }
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'locales') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'LeanADB.ps1') -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $projectRoot 'VERSION') -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $projectRoot 'locales\ko.json') -Destination (Join-Path $testRoot 'locales')
    [ordered]@{
        ProductId = 'LeanADB'
        Publisher = 'leodroid99'
        LeanADBVersion = '0.4.0-alpha'
        InstalledVersion = 'test'
        LastCheckUtc = [DateTime]::UtcNow.ToString('o')
        PathRegistered = $false
        ShortcutRegistered = $false
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testRoot 'state.json') -Encoding UTF8

    $manifestUri = ([Uri]$manifestPath).AbsoluteUri
    & (Join-Path $testRoot 'LeanADB.ps1') -Action SelfUpdate -InstallPath $testRoot -ProductManifestUrl $manifestUri -Quiet
    if ($LASTEXITCODE) { throw "Self-update exited with code $LASTEXITCODE" }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $state = Get-Content -LiteralPath (Join-Path $testRoot 'state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.LeanADBVersion -ne $manifest.Version) {
        throw 'Self-update did not record the new LeanADB version.'
    }
    foreach ($entry in $manifest.Files) {
        $target = Join-Path $testRoot ([string]$entry.Path).Replace('/', '\')
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne [string]$entry.Sha256) {
            throw "Self-updated file hash mismatch: $($entry.Path)"
        }
    }

    $beforeScriptHash = (Get-FileHash -LiteralPath (Join-Path $testRoot 'LeanADB.ps1') -Algorithm SHA256).Hash
    $busyManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $busyManifest.Version = '999.0.0-alpha'
    $artifactUri = ([Uri](Join-Path (Split-Path -Parent $manifestPath) ([string]$busyManifest.Package.FileName))).AbsoluteUri
    $busyManifest.Package | Add-Member -NotePropertyName Url -NotePropertyValue $artifactUri -Force
    $busyManifestPath = Join-Path $testRoot 'busy-manifest.json'
    $busyManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $busyManifestPath -Encoding UTF8
    $rootBytes = [Text.Encoding]::UTF8.GetBytes(([IO.Path]::GetFullPath($testRoot).TrimEnd('\')).ToLowerInvariant())
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { $lockId = ([BitConverter]::ToString($algorithm.ComputeHash($rootBytes))).Replace('-', '').Substring(0, 20) } finally { $algorithm.Dispose() }
    $testMutex = New-Object Threading.Mutex($false, "Local\LeanADB-$lockId")
    try {
        [void]$testMutex.WaitOne()
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testRoot 'LeanADB.ps1') `
            -Action SelfUpdate -InstallPath $testRoot -ProductManifestUrl (([Uri]$busyManifestPath).AbsoluteUri) -Quiet
        if ($LASTEXITCODE -eq 0) { throw 'A concurrent self-update unexpectedly acquired the update lock.' }
    }
    finally {
        $testMutex.ReleaseMutex()
        $testMutex.Dispose()
    }

    $badManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $badManifest.Version = '999.0.0-alpha'
    $badManifest.Files[1].Sha256 = ('0' * 64)
    $badManifest.Package | Add-Member -NotePropertyName Url -NotePropertyValue $artifactUri -Force
    $badManifestPath = Join-Path $testRoot 'bad-manifest.json'
    $badManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $badManifestPath -Encoding UTF8
    $badManifestUri = ([Uri]$badManifestPath).AbsoluteUri
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testRoot 'LeanADB.ps1') `
        -Action SelfUpdate -InstallPath $testRoot -ProductManifestUrl $badManifestUri -Quiet
    if ($LASTEXITCODE -eq 0) {
        throw 'A self-update with a damaged file hash unexpectedly succeeded.'
    }
    $afterFailureState = Get-Content -LiteralPath (Join-Path $testRoot 'state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $afterFailureHash = (Get-FileHash -LiteralPath (Join-Path $testRoot 'LeanADB.ps1') -Algorithm SHA256).Hash
    if ($afterFailureState.LeanADBVersion -ne $manifest.Version -or $afterFailureHash -ne $beforeScriptHash) {
        throw 'Self-update rollback did not restore files and state after verification failure.'
    }
    $global:LASTEXITCODE = 0
    Write-Host "LeanADB self-update test passed for $($manifest.Version)."
}
finally {
    if (-not $errorLogExisted -and (Test-Path -LiteralPath $errorLogPath -PathType Leaf)) {
        Remove-Item -LiteralPath $errorLogPath -Force
    }
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $resolved = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolved.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved).StartsWith('LeanADB-SelfUpdate-', [StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
