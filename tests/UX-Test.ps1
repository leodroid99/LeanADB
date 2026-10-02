$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'LeanADB.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw $errors[0].Message }
$names = @('Show-InstallApks','Retry-LastBatch','Install-SplitApkBatch','Get-CommandAdvice',
    'Format-Message','Invoke-SafeUiAction','Show-TaskGroup','Start-DeferredRemoval')
foreach ($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names},$true)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$messageDefinition = $ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$script:Messages'},$true)
. ([scriptblock]::Create($messageDefinition.Extent.Text))
$script:LastBatch = $null; $script:AnyBatchFailure = $false
$script:SelectedDeviceSerial = ''; $script:MenuState = $null
$script:Mode = '1'; $script:Serial = 'PHONE-A'; $script:Sdk = 30
$script:Calls = @(); $script:Files = @(); $script:Confirm = $true; $script:NativeExit = 0
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-UX-' + [guid]::NewGuid().ToString('N'))

function Assert-True { param([bool]$Condition,[string]$Message); if (-not $Condition) { throw $Message } }
function Clear-Host {}
function Wait-ForMenuKey {}
function Select-AdbDevice { $script:Serial }
function Select-LocalFile { $script:Files }
function Read-MenuChoice { if ($null -ne $script:Choices) { $script:Choices.Dequeue() } else { $script:Mode } }
function Confirm-MenuAction { $script:Confirm }
function Get-AdbSdkLevel { $script:Sdk }
function Install-ApkBatch { param($AdbPath,$Serial,$Paths); $script:Calls += [pscustomobject]@{Kind='Independent';Serial=$Serial;Paths=@($Paths)} }
function Send-FilesToDevice { param($AdbPath,$Serial,$Paths); $script:Calls += [pscustomobject]@{Kind='Send';Serial=$Serial;Paths=@($Paths)} }
function Invoke-ToolProcess { param($Executable,$Arguments,$TimeoutSeconds); $script:Calls += [pscustomobject]@{Kind='Native';Args=@($Arguments)}; [pscustomobject]@{ExitCode=$script:NativeExit;Output='fixture result'} }
function Save-OperationReport { param($Kind,$Serial,$Results); $script:Report=[pscustomobject]@{Kind=$Kind;Serial=$Serial;Results=@($Results)}; 'fixture-report.txt' }
function Invoke-UiAction { param($Name); $script:ActionCalls++; if ($script:ActionThrows) { throw 'Simulated action failure' } }
function Show-ActionError { param($Details); $script:Errors += $Details }
function Read-State { throw 'Simulated state refresh failure' }
function Start-Sleep {}
function Start-Process { param($FilePath,$ArgumentList,$WindowStyle); $script:Cleanup = [scriptblock]::Create([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]))) }
$script:Choices = $null; $script:Report = $null; $script:Cleanup = $null
$script:ActionThrows = $false; $script:ActionCalls = 0; $script:Errors = @()

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $script:Files = @((Join-Path $testRoot 'base.apk'),(Join-Path $testRoot 'config.apk'))
    foreach ($path in $script:Files) { Set-Content -LiteralPath $path -Value 'fixture' -Encoding ASCII }
    Show-InstallApks -AdbPath 'fixture'
    Assert-True ($script:Calls.Count -eq 1 -and $script:Calls[0].Kind -eq 'Independent' -and $script:Calls[0].Paths.Count -eq 2) 'Separate APK mode was not routed to individual installation.'
    $script:Calls = @(); $script:Mode = 'Escape'
    Show-InstallApks -AdbPath 'fixture'
    Assert-True ($script:Calls.Count -eq 0) 'Cancelling APK mode selection installed an app.'
    $script:Mode = '2'; $script:Sdk = 19
    Show-InstallApks -AdbPath 'fixture'
    Assert-True ($script:Calls.Count -eq 0) 'Split APK installation ran on API 19.'
    $script:Sdk = 30; $script:NativeExit = 1
    Show-InstallApks -AdbPath 'fixture'
    Assert-True ($script:Calls.Count -eq 1 -and $script:Calls[0].Args[2] -eq 'install-multiple') 'Split APK mode did not preserve the whole set.'
    Assert-True ($script:LastBatch.Kind -eq 'Split' -and $script:Report.Results.Count -eq 2 -and $script:AnyBatchFailure) 'Split APK failure did not persist results.'
    $script:Calls = @(); $script:Serial = 'PHONE-B'
    Retry-LastBatch -AdbPath 'fixture'
    Assert-True ($script:Calls.Count -eq 0) 'Retry silently used a different phone.'
    $script:Serial = 'PHONE-A'; $script:Confirm = $false
    Retry-LastBatch -AdbPath 'fixture'
    Assert-True ($script:Calls.Count -eq 0) 'Retry ignored cancellation.'
    $script:Confirm = $true; $script:NativeExit = 0
    Retry-LastBatch -AdbPath 'fixture'
    Assert-True ($script:Calls.Count -eq 1 -and $script:Calls[0].Args.Count -eq 6 -and @($script:LastBatch.Results | Where-Object {-not $_.Success}).Count -eq 0) 'Split retry lost files or reported failure after success.'
    $script:Calls = @()
    $script:LastBatch = [pscustomobject]@{Kind='Send';Serial='PHONE-A';Results=@(
        [pscustomobject]@{Path='ok.txt';Success=$true},[pscustomobject]@{Path='failed.txt';Success=$false})}
    Retry-LastBatch -AdbPath 'fixture'
    Assert-True ($script:Calls.Count -eq 1 -and ($script:Calls[0].Paths -join '|') -eq 'failed.txt') 'Retry attempted already successful files.'
    Assert-True ((Get-CommandAdvice -Output 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' -ExitCode 1) -eq $script:Messages.ApkSignatureAdvice) 'Signature error guidance missing.'
    Assert-True ((Get-CommandAdvice -Output '' -ExitCode 124) -eq $script:Messages.OperationTimedOut) 'Timeout guidance missing.'
    $script:ActionThrows = $true
    Invoke-SafeUiAction -Name 'Test' -Root $testRoot -AdbPath 'fixture' -FastbootPath 'fixture'
    Assert-True ($script:Errors.Count -eq 1) 'Action failure escaped the menu error boundary.'
    $script:ActionThrows = $false; $script:Errors = @()
    $script:Choices = New-Object 'System.Collections.Generic.Queue[string]'
    $script:Choices.Enqueue('1'); $script:Choices.Enqueue('Escape')
    Show-TaskGroup -Group HomeApps -Root $testRoot -AdbPath 'fixture' -FastbootPath 'fixture'
    Assert-True ($script:Errors.Count -eq 1 -and $script:Choices.Count -eq 0) 'State refresh failure crashed navigation instead of returning to the submenu.'

    # Run the generated cleanup only against this test-owned child directory.
    $removalRoot = Join-Path $testRoot 'deferred'
    New-Item -ItemType Directory -Path $removalRoot | Out-Null
    Start-DeferredRemoval -Root $removalRoot -RemovalId 'owned-fixture'
    & $script:Cleanup
    Assert-True (Test-Path -LiteralPath $removalRoot -PathType Container) 'Deferred cleanup deleted a folder without its ownership marker.'
    [pscustomobject]@{ProductId='LeanADB';PendingRemovalId='changed'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $removalRoot 'state.json') -Encoding UTF8
    & $script:Cleanup
    Assert-True (Test-Path -LiteralPath $removalRoot -PathType Container) 'Stale deferred cleanup deleted a replacement installation.'
    [pscustomobject]@{ProductId='LeanADB';PendingRemovalId='owned-fixture'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $removalRoot 'state.json') -Encoding UTF8
    $script:RemovalFixtureRoot = $removalRoot; $script:PartialRemovalCalls = 0
    function Remove-Item {
        param([string]$LiteralPath,[switch]$Recurse,[switch]$Force,[string]$ErrorAction)
        if ($LiteralPath -ceq $script:RemovalFixtureRoot) {
            $script:PartialRemovalCalls++
            if ($script:PartialRemovalCalls -eq 1) {
                Microsoft.PowerShell.Management\Remove-Item -LiteralPath (Join-Path $LiteralPath 'state.json') -Force
                throw 'Simulated partial removal after deleting state.json.'
            }
        }
        Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters
    }
    & $script:Cleanup
    Assert-True (-not (Test-Path -LiteralPath $removalRoot) -and $script:PartialRemovalCalls -eq 2) 'Matching deferred cleanup failed to retry after partial removal of state.json.'
    Write-Host 'LeanADB UX tests passed: APK modes, target-safe retries, result reports, resilient navigation, and deferred cleanup ownership.'
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $resolved = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolved.StartsWith($tempRoot + '\',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('LeanADB-UX-') -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
