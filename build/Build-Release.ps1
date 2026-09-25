[CmdletBinding()]
param(
    [string]$CodeSigningThumbprint = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
$distRoot = Join-Path $projectRoot 'dist'
$artifactPath = Join-Path $distRoot "LeanADB-bootstrap-v$version.zip"
$checksumPath = "$artifactPath.sha256"
$manifestPath = Join-Path $distRoot 'LeanADB-release.json'
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('LeanADB-Release-' + [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $stagingRoot 'LeanADB'

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    foreach ($name in @('LeanADB.ps1', 'Install.cmd', 'README.md', 'CHANGELOG.md', 'LICENSE', 'VERSION')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $name) -Destination $packageRoot
    }
    $updateUrlFile = Join-Path $projectRoot 'UPDATE_URL'
    if (Test-Path -LiteralPath $updateUrlFile -PathType Leaf) {
        Copy-Item -LiteralPath $updateUrlFile -Destination $packageRoot
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'locales') -Destination $packageRoot -Recurse
    $signed = $false
    if ($CodeSigningThumbprint) {
        $certificate = Get-ChildItem -Path "Cert:\CurrentUser\My\$CodeSigningThumbprint" -ErrorAction Stop
        if (-not $certificate.HasPrivateKey -or -not ($certificate.EnhancedKeyUsageList | Where-Object { $_.ObjectId.Value -eq '1.3.6.1.5.5.7.3.3' })) {
            throw 'The selected certificate is not a usable code-signing certificate.'
        }
        $signature = Set-AuthenticodeSignature -LiteralPath (Join-Path $packageRoot 'LeanADB.ps1') `
            -Certificate $certificate -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'
        if ($signature.Status -ne 'Valid') {
            throw "LeanADB.ps1 signing failed: $($signature.StatusMessage)"
        }
        $signed = $true
    }
    New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
    $resolvedProjectRoot = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd('\')
    $resolvedDistRoot = [System.IO.Path]::GetFullPath($distRoot).TrimEnd('\')
    if ([System.IO.Path]::GetDirectoryName($resolvedDistRoot) -ne $resolvedProjectRoot -or
        [System.IO.Path]::GetFileName($resolvedDistRoot) -ne 'dist') {
        throw "Refusing to clean unexpected distribution directory: $resolvedDistRoot"
    }
    $oldArtifacts = Get-ChildItem -LiteralPath $resolvedDistRoot -Force | Where-Object {
        $_.Name -like 'LeanADB-bootstrap-v*'
    }
    foreach ($oldArtifact in $oldArtifacts) {
        $artifactParent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($oldArtifact.FullName))
        if ($artifactParent -ne $resolvedDistRoot) {
            throw "Refusing to remove artifact outside the distribution directory: $($oldArtifact.FullName)"
        }
        Remove-Item -LiteralPath $oldArtifact.FullName -Recurse -Force
    }
    if (Test-Path -LiteralPath $artifactPath) {
        Remove-Item -LiteralPath $artifactPath -Force
    }
    if (Test-Path -LiteralPath $checksumPath) {
        Remove-Item -LiteralPath $checksumPath -Force
    }
    if (Test-Path -LiteralPath $manifestPath) {
        Remove-Item -LiteralPath $manifestPath -Force
    }
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $artifactPath -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([System.IO.Path]::GetFileName($artifactPath))" | Set-Content -LiteralPath $checksumPath -Encoding ASCII
    $updateFiles = foreach ($relative in @(
        'LeanADB.ps1', 'VERSION', 'README.md', 'CHANGELOG.md', 'LICENSE', 'locales\ko.json'
    )) {
        $filePath = Join-Path $packageRoot $relative
        [ordered]@{
            Path = $relative.Replace('\', '/')
            Sha256 = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $manifest = [ordered]@{
        SchemaVersion = 1
        ProductId = 'LeanADB'
        Version = $version
        AuthenticodeSigned = $signed
        Package = [ordered]@{
            FileName = [System.IO.Path]::GetFileName($artifactPath)
            Sha256 = $hash
        }
        Files = @($updateFiles)
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Host "Created $artifactPath"
    Write-Host "SHA-256 $hash"
    Write-Host "Created $manifestPath"
}
finally {
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    $resolvedStaging = [System.IO.Path]::GetFullPath($stagingRoot).TrimEnd('\')
    if ($resolvedStaging.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Path]::GetFileName($resolvedStaging).StartsWith('LeanADB-Release-', [StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $resolvedStaging) {
            Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
        }
    }
}
