$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
$artifact = Join-Path $projectRoot "dist\LeanADB-bootstrap-v$version.zip"
$checksumFile = "$artifact.sha256"
$manifestFile = Join-Path $projectRoot 'dist\LeanADB-release.json'
$extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('LeanADB-Release-Test-' + [guid]::NewGuid().ToString('N'))

try {
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
        throw "Release artifact not found: $artifact"
    }
    if (-not (Test-Path -LiteralPath $checksumFile -PathType Leaf)) {
        throw "Release checksum not found: $checksumFile"
    }
    if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
        throw "Release manifest not found: $manifestFile"
    }

    $expectedHash = ((Get-Content -LiteralPath $checksumFile -Raw).Trim() -split '\s+')[0]
    $actualHash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw 'Release SHA-256 does not match its checksum file.'
    }
    $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.ProductId -ne 'LeanADB' -or $manifest.Version -ne $version -or
        $manifest.Package.FileName -ne [IO.Path]::GetFileName($artifact) -or
        $manifest.Package.Sha256 -ne $actualHash) {
        throw 'Release update manifest metadata is invalid.'
    }

    Expand-Archive -LiteralPath $artifact -DestinationPath $extractRoot
    $packageRoot = Join-Path $extractRoot 'LeanADB'
    $expectedFiles = @('CHANGELOG.md', 'Install.cmd', 'LeanADB.ps1', 'LICENSE', 'README.md', 'VERSION')
    if (Test-Path -LiteralPath (Join-Path $projectRoot 'UPDATE_URL') -PathType Leaf) {
        $expectedFiles += 'UPDATE_URL'
    }
    $actualFiles = @(Get-ChildItem -LiteralPath $packageRoot -File | Select-Object -ExpandProperty Name | Sort-Object)
    $expectedSorted = @($expectedFiles | Sort-Object)
    if (($actualFiles -join '|') -ne ($expectedSorted -join '|')) {
        throw "Unexpected release contents: $($actualFiles -join ', ')"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'locales\ko.json') -PathType Leaf)) {
        throw 'Korean localization file is missing from the release.'
    }
    if (Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Where-Object { $_.Extension -in @('.exe', '.dll') }) {
        throw 'Bootstrap release unexpectedly contains Google binaries.'
    }
    foreach ($entry in $manifest.Files) {
        $manifestPath = Join-Path $packageRoot ([string]$entry.Path).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Manifest file is missing from package: $($entry.Path)"
        }
        $entryHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($entryHash -ne [string]$entry.Sha256) {
            throw "Manifest hash mismatch: $($entry.Path)"
        }
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $packageRoot 'LeanADB.ps1'),
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count) {
        throw "Packaged PowerShell syntax check failed: $($parseErrors[0].Message)"
    }

    Write-Host "LeanADB release test passed: $([System.IO.Path]::GetFileName($artifact))"
}
finally {
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    $resolvedExtractRoot = [System.IO.Path]::GetFullPath($extractRoot).TrimEnd('\')
    if ($resolvedExtractRoot.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Path]::GetFileName($resolvedExtractRoot).StartsWith('LeanADB-Release-Test-', [StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $resolvedExtractRoot) {
            Remove-Item -LiteralPath $resolvedExtractRoot -Recurse -Force
        }
    }
}
