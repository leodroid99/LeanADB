$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'LeanADB.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'LeanADB.ps1 has parser errors.' }
$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-Launchers' }, $true)
if ($null -eq $definition) { throw 'Write-Launchers was not found.' }
. ([scriptblock]::Create($definition.Extent.Text))

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-drop-test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $fakeScript = @'
param([string]$Action, [string]$InstallPath, [string[]]$DroppedPaths)
$DroppedPaths | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'received-paths.txt') -Encoding UTF8
'@
    Set-Content -LiteralPath (Join-Path $testRoot 'LeanADB.ps1') -Value $fakeScript -Encoding ASCII
    Write-Launchers -Root $testRoot
    $unicode = -join @([char]0xD55C, [char]0xAE00)
    $fileOne = Join-Path $testRoot ($unicode + ' & one.txt')
    $fileTwo = Join-Path $testRoot 'bang! percent% two.apk'
    Set-Content -LiteralPath $fileOne -Value 'one' -Encoding ASCII
    Set-Content -LiteralPath $fileTwo -Value 'two' -Encoding ASCII
    & (Join-Path $testRoot 'Drop files on LeanADB.cmd') $fileOne $fileTwo
    if ($LASTEXITCODE -ne 0) { throw "Drag-and-drop launcher exited with $LASTEXITCODE." }
    $received = @(Get-Content -LiteralPath (Join-Path $testRoot 'received-paths.txt') -Encoding UTF8)
    if ($received.Count -ne 2 -or $received[0] -ne $fileOne -or $received[1] -ne $fileTwo) {
        throw "Drag-and-drop paths were damaged: $($received -join ' | ')"
    }
    Write-Host 'LeanADB drag-and-drop launcher test passed.'
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $resolved = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolved.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved).StartsWith('LeanADB-drop-test-', [StringComparison]::Ordinal) -and
        (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
