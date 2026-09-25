$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'LeanADB.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'LeanADB.ps1 has parser errors.' }
$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ProductManifest' }, $true)
if ($null -eq $definition) { throw 'Get-ProductManifest was not found.' }
. ([scriptblock]::Create($definition.Extent.Text))
$script:ProductId = 'LeanADB'
$script:Messages = @{ InvalidManifest = 'Invalid manifest.' }
$manifestJson = '{"ProductId":"LeanADB","Version":"1.0.1","Package":{"FileName":"LeanADB-bootstrap-v1.0.1.zip","Sha256":"abc"},"Files":[{"Path":"VERSION","Sha256":"def"}]}'

function Invoke-WebRequest {
    param([string]$Uri)
    if ($Uri -like '*octet*') {
        return [pscustomobject]@{ Content = [Text.Encoding]::UTF8.GetBytes(([char]0xFEFF) + $manifestJson) }
    }
    return [pscustomobject]@{ Content = $manifestJson }
}

foreach ($url in @('https://example.test/octet', 'https://example.test/json')) {
    $manifest = Get-ProductManifest -ManifestUrl $url
    if ($manifest.ProductId -ne 'LeanADB' -or $manifest.Version -ne '1.0.1' -or
        $manifest.Package.FileName -ne 'LeanADB-bootstrap-v1.0.1.zip') {
        throw "Manifest parsing failed for $url"
    }
}
Write-Host 'LeanADB manifest response parsing test passed.'
