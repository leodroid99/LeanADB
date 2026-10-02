$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'LeanADB.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw $errors[0].Message }
$names = @('Format-Message','Get-StatePath','Get-StateBackupPath','Read-StateFile','Read-State','Write-State',
    'Get-Sha256Hash','Assert-FreeDiskSpace','Enter-UpdateLock','Exit-UpdateLock','New-InstallSnapshot','Restore-InstallSnapshot',
    'Install-Package','Get-UpdateChecks','Test-CheckDue','Test-RemoteChanged','Test-AdbEndpoint',
    'Assert-ProductArchive','Test-NewerProductVersion','Convert-SemVerParts',
    'Get-AdbDeviceRecords','Get-LocalizedDeviceStatus','Get-AdbStatusAdvice','Show-ConnectionDiagnostics',
    'Get-DeviceAlias','Get-DeviceDisplayName','Select-PagedRecord','Select-FastbootDevice',
    'Invoke-ToolProcess','ConvertTo-NativeArgument','Test-CaptureSignature')
foreach ($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names},$true)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$messageDefinition = $ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$script:Messages'},$true)
. ([scriptblock]::Create($messageDefinition.Extent.Text))
$script:ProductId = 'LeanADB'; $script:ProductVersion = '1.0.1'; $script:StateRecoveredFromBackup = $false
$script:MinimumInstallFreeBytes = 64MB; $script:CheckIntervalHours = 24; $script:FailedCheckBackoffHours = 6
$script:ProductManifestUrl = ''; $script:LicenseUrl = 'https://example.test/license'; $script:SourceUrl = 'https://example.test/tools'
$script:PinDeviceSelection = $false; $script:SelectedDeviceSerial = ''; $script:MenuState = $null
$script:RequiredFiles = @('adb.exe','source.properties'); $script:FailureStage = ''; $script:FastbootCount = 0
$script:FailGoogle = $false; $script:FailProduct = $false; $script:Confirm = $true
$script:ChildExitCode = 0
$Language = 'Auto'; $Quiet = $true; $Force = $true
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-hardening-' + [guid]::NewGuid().ToString('N'))
$script:RealWriteState = [scriptblock]::Create(($ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-State'},$true)).Body.Extent.Text.Trim().Substring(1).TrimEnd('}'))

function Assert-True { param([bool]$Condition,[string]$Message); if (-not $Condition) { throw $Message } }
function Clear-Host {}
function Wait-ForMenuKey {}
function Write-Info {}
function Get-RegisteredAdbPath { '' }
function Confirm-MenuAction { $script:Confirm }
function Read-MenuChoice { $script:Choices.Dequeue() }
function FakeAdb { $global:LASTEXITCODE = 0; if ($args[0] -eq 'devices') { return @('List of devices attached','USB-A device model:TestPhone') }; 'ADB test version' }
function FakeFastboot { $global:LASTEXITCODE = 0; if ($args[0] -eq '--version') { return 'Fastboot test version' }; for ($i=0; $i -lt $script:FastbootCount; $i++) { "FB$i`tfastboot" } }
function Get-RemoteMetadata { if ($script:FailGoogle) { throw 'Simulated Google failure' }; [pscustomobject]@{ETag='new';LastModified='new';ContentLength='1'} }
function Get-ProductManifest { if ($script:FailProduct) { throw 'Simulated GitHub failure' }; [pscustomobject]@{Version='1.0.2'} }
function Copy-ProductFiles { if ($script:FailureStage -eq 'Copy') { throw 'Injected failure after bin replacement' } }
function Write-Launchers { param($Root); Set-Content -LiteralPath (Join-Path $Root 'Open LeanADB.cmd') -Value 'new launcher' -Encoding ASCII }
function Stop-AdbServer {}
function Get-AuthenticodeSignature { [pscustomobject]@{Status='NotSigned'} }
function Expand-AndValidatePackage { [pscustomobject]@{Version='38.0.0';Path=(Join-Path $testRoot 'package')} }
function Write-State {
    param($Root,$State)
    if ($script:FailureStage -eq 'State') { throw 'Injected state-save failure' }
    & $script:RealWriteState -Root $Root -State $State
}
function Install-ProductUpdate {
    param($Root,$ManifestUrl,$Manifest)
    $latest = Read-State -Root $Root
    $latest.LeanADBVersion = $Manifest.Version
    Write-State -Root $Root -State $latest
    Set-Content -LiteralPath (Join-Path $Root 'VERSION') -Value $Manifest.Version -Encoding ASCII
    $newScript = @'
param($Action,$InstallPath,[switch]$SkipProductUpdate,[switch]$Force,[switch]$Quiet,$Language)
if ($Action -ne 'Update' -or -not $SkipProductUpdate) { throw 'Invalid update handoff.' }
@{Version=(Get-Content (Join-Path $InstallPath 'VERSION') -Raw).Trim();Language=$Language;Force=[bool]$Force} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallPath 'handoff.json') -Encoding UTF8
$global:LASTEXITCODE = CHILD_EXIT_CODE
'@
    Set-Content -LiteralPath (Join-Path $Root 'LeanADB.ps1') -Value ($newScript.Replace('CHILD_EXIT_CODE',[string]$script:ChildExitCode)) -Encoding UTF8
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $legacy = [pscustomobject]@{ProductId='LeanADB';InstalledVersion='37.0.1'}
    Write-State -Root $testRoot -State $legacy
    $migrated = Read-State -Root $testRoot
    Assert-True ($migrated.StateSchemaVersion -eq 2 -and -not $migrated.PathRegistered -and @($migrated.RecentDevices).Count -eq 0) 'Legacy settings did not migrate safely.'
    $invalid = $migrated | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $invalid.PathRegistered = 'false'
    $invalid | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Get-StatePath -Root $testRoot) -Encoding UTF8
    $recovered = Read-State -Root $testRoot
    Assert-True ($script:StateRecoveredFromBackup -and $recovered.PathRegistered -is [bool]) 'Malformed Boolean setting did not fall back to the valid backup.'
    Write-State -Root $testRoot -State $migrated

    foreach ($endpoint in @('host.local:5555','192.168.1.2:65535','[::1]:5555')) { Assert-True (Test-AdbEndpoint $endpoint) "Valid endpoint rejected: $endpoint" }
    foreach ($endpoint in @('host:0','host:65536','host:99999','-bad:5555','192.168.999.2:1234')) { Assert-True (-not (Test-AdbEndpoint $endpoint)) "Invalid endpoint accepted: $endpoint" }
    foreach ($count in @(0,1,2)) {
        $script:FastbootCount = $count
        Show-ConnectionDiagnostics -Root $testRoot -AdbPath 'FakeAdb' -FastbootPath 'FakeFastboot' -State $migrated *> $null
    }
    $script:PinDeviceSelection = $true; $script:SelectedDeviceSerial = 'USB-A'; $script:FastbootCount = 1; $script:Confirm = $false
    Assert-True ($null -eq (Select-FastbootDevice -FastbootPath 'FakeFastboot')) 'Fastboot silently selected a different physical target.'
    $script:Confirm = $true
    Assert-True ((Select-FastbootDevice -FastbootPath 'FakeFastboot') -eq 'FB0') 'Confirmed Fastboot selection failed.'
    $script:PinDeviceSelection = $false
    $script:Choices = New-Object 'System.Collections.Generic.Queue[string]'
    $script:Choices.Enqueue('N'); $script:Choices.Enqueue('1')
    $records = @(0..10 | ForEach-Object { [pscustomobject]@{Serial="S$_";Model='';Status='device'} })
    Assert-True ((Select-PagedRecord -Records $records -Title 'Test') -eq 'S9') 'Devices beyond the first page cannot be selected.'

    $script:ProductManifestUrl = 'https://example.test/manifest'; $script:FailProduct = $true
    $checks = Get-UpdateChecks
    Assert-True ($checks.ToolsStatus -eq 'Success' -and $checks.ProductStatus -eq 'Failed') 'GitHub failure blocked the Google check.'
    $script:FailProduct = $false; $script:FailGoogle = $true
    $checks = Get-UpdateChecks
    Assert-True ($checks.ProductStatus -eq 'Success' -and $checks.ToolsStatus -eq 'Failed') 'Google failure blocked the app check.'
    $script:ProductManifestUrl = ''
    $InstallPath = $testRoot
    $switch = $ast.Find({param($node) $node -is [Management.Automation.Language.SwitchStatementAst] -and $node.Condition.Extent.Text -eq '$Action'},$true)
    $body = @($switch.Clauses | Where-Object {$_.Item1.Extent.Text -eq "'AutoUpdate'"})[0].Item2.Extent.Text
    $autoUpdate = [scriptblock]::Create($body.Substring(1,$body.Length-2))
    $state = Read-State -Root $testRoot
    & $autoUpdate
    $script:FailGoogle = $false; $state = Read-State -Root $testRoot
    & $autoUpdate
    $state = Read-State -Root $testRoot
    Assert-True (-not $state.PackageComparisonKnown -and -not $state.UpdateAvailable) 'Network retry invented an online baseline for an offline package.'

    $binaryPath = Join-Path $testRoot 'native-bytes.bin'
    $child = '$bytes=[byte[]](0,10,13,128,137,255); $s=[Console]::OpenStandardOutput(); $s.Write($bytes,0,$bytes.Length); $s.Flush()'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child))
    $result = Invoke-ToolProcess -Executable 'powershell.exe' -Arguments @('-NoProfile','-EncodedCommand',$encoded) -OutputFile $binaryPath -QuietProgress
    Assert-True ($result.ExitCode -eq 0 -and [BitConverter]::ToString([IO.File]::ReadAllBytes($binaryPath)) -eq '00-0A-0D-80-89-FF') 'Native process runner corrupted binary output.'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Sleep -Seconds 10'))
    $result = Invoke-ToolProcess -Executable 'powershell.exe' -Arguments @('-NoProfile','-EncodedCommand',$encoded) -TimeoutSeconds 1 -QuietProgress
    Assert-True ($result.TimedOut -and $result.ExitCode -eq 124) 'Native process timeout did not stop the client.'

    $argumentScript = Join-Path $testRoot 'echo arguments.cs'
    $argumentExecutable = Join-Path $testRoot 'echo arguments.exe'
    $argumentFixture = @'
using System;
using System.Text;
using System.IO;
using System.Diagnostics;
using System.Threading;
class ArgumentFixture {
    static void Main(string[] args) {
        string dir = Path.GetDirectoryName(typeof(ArgumentFixture).Assembly.Location);
        if (args.Length == 1 && args[0] == "hold-output") {
            File.WriteAllText(Path.Combine(dir,"output-holder.pid"),Process.GetCurrentProcess().Id.ToString());
            Stopwatch watch = Stopwatch.StartNew();
            while (watch.ElapsedMilliseconds < 10000 && !File.Exists(Path.Combine(dir,"release-output-holder"))) Thread.Sleep(50);
            return;
        }
        if (args.Length == 1 && args[0] == "spawn-holder") {
            ProcessStartInfo info = new ProcessStartInfo(typeof(ArgumentFixture).Assembly.Location,"hold-output");
            info.UseShellExecute = false; info.CreateNoWindow = true;
            Process.Start(info);
            Thread.Sleep(10000);
            return;
        }
        foreach (string arg in args) Console.WriteLine(Convert.ToBase64String(Encoding.UTF8.GetBytes(arg)));
    }
}
'@
    Set-Content -LiteralPath $argumentScript -Value $argumentFixture -Encoding UTF8
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $compiled = Invoke-ToolProcess -Executable $compiler -Arguments @('/nologo','/target:exe',('/out:' + $argumentExecutable),$argumentScript) -TimeoutSeconds 60 -QuietProgress
    Assert-True ($compiled.ExitCode -eq 0) ('Native argument fixture compilation failed: ' + $compiled.Output)
    $unicodeArgument = (-join @([char]0xD55C,[char]0xAE00)) + ' path & bang! 100%.apk'
    $expectedArguments = @($unicodeArgument,'say "hello"','C:\ends\')
    $result = Invoke-ToolProcess -Executable $argumentExecutable -Arguments $expectedArguments -QuietProgress
    $actualArguments = @($result.Output -split '\r?\n' | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
    Assert-True ($result.ExitCode -eq 0 -and ($actualArguments -join '|') -ceq ($expectedArguments -join '|')) ('Native argument quoting damaged Unicode, quotes, shell characters, or trailing slashes: ' + ($actualArguments -join ' | '))
    $pipeWatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $heldOutput = Invoke-ToolProcess -Executable $argumentExecutable -Arguments @('spawn-holder') -TimeoutSeconds 3 -QuietProgress
    }
    finally {
        $pipeWatch.Stop()
        Set-Content -LiteralPath (Join-Path $testRoot 'release-output-holder') -Value 'release' -Encoding ASCII
        $holderPidFile = Join-Path $testRoot 'output-holder.pid'
        if (Test-Path -LiteralPath $holderPidFile) {
            $holderPid = [int](Get-Content -LiteralPath $holderPidFile -Raw)
            $holder = Get-Process -Id $holderPid -ErrorAction SilentlyContinue
            if ($null -ne $holder -and $holder.MainModule.FileName -ceq $argumentExecutable) { Wait-Process -Id $holderPid -Timeout 5 -ErrorAction SilentlyContinue }
        }
    }
    Assert-True ($heldOutput.ExitCode -eq 124 -and $pipeWatch.Elapsed.TotalSeconds -lt 9) 'A descendant holding output pipes bypassed the client timeout.'

    $installRoot = Join-Path $testRoot 'installed'
    New-Item -ItemType Directory -Path (Join-Path $installRoot 'bin'),(Join-Path $testRoot 'package') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $installRoot 'bin\adb.exe') -Value 'old tools' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $installRoot 'Open LeanADB.cmd') -Value 'old launcher' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $testRoot 'package\adb.exe') -Value 'new tools' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $testRoot 'package\source.properties') -Value 'Pkg.Revision=38.0.0' -Encoding ASCII
    $zip = Join-Path $testRoot 'fixture.zip'
    Set-Content -LiteralPath $zip -Value 'isolated fixture' -Encoding ASCII
    Write-State -Root $installRoot -State $migrated
    $originalStateHash = Get-Sha256Hash -FilePath (Get-StatePath $installRoot)
    foreach ($stage in @('Copy','State')) {
        $script:FailureStage = $stage; $failed = $false
        try { Install-Package -Root $installRoot -RemoteMetadata $null -RegisterPath $false -RegisterShortcut $false -ExistingState (Read-State $installRoot) -LocalZipPath $zip | Out-Null }
        catch { $failed = $true }
        Assert-True $failed "Failure injection $stage did not run."
        Assert-True ((Get-Content -LiteralPath (Join-Path $installRoot 'bin\adb.exe') -Raw).Trim() -eq 'old tools') "$stage failure did not restore the old tools."
        Assert-True ((Get-Content -LiteralPath (Join-Path $installRoot 'Open LeanADB.cmd') -Raw).Trim() -eq 'old launcher') "$stage failure did not restore launchers."
        Assert-True ((Get-Sha256Hash -FilePath (Get-StatePath $installRoot)) -eq $originalStateHash) "$stage failure did not restore exact state bytes."
    }
    $script:FailureStage = ''
    $updated = Install-Package -Root $installRoot -RemoteMetadata $null -RegisterPath $false -RegisterShortcut $false -ExistingState (Read-State $installRoot) -LocalZipPath $zip
    Assert-True ($updated.InstalledVersion -eq '38.0.0' -and -not $updated.PackageComparisonKnown) 'Successful offline update has invalid state.'
    Assert-True (@(Get-ChildItem -LiteralPath $installRoot -Filter '.bin-*').Count -eq 0) 'Successful update left temporary bin directories.'
    $pendingState = Read-State -Root $installRoot
    $pendingState | Add-Member -NotePropertyName PendingRemovalId -NotePropertyValue ([guid]::NewGuid().ToString('N')) -Force
    Write-State -Root $installRoot -State $pendingState
    $pendingStateHash = Get-Sha256Hash -FilePath (Get-StatePath $installRoot)
    $pendingBlocked = $false
    try { Install-Package -Root $installRoot -RemoteMetadata $null -RegisterPath $false -RegisterShortcut $false -ExistingState $updated -LocalZipPath $zip | Out-Null }
    catch { $pendingBlocked = $_.Exception.Message -eq $script:Messages.RemovalPending }
    Assert-True ($pendingBlocked -and (Get-Sha256Hash -FilePath (Get-StatePath $installRoot)) -eq $pendingStateHash) 'Stale installer state bypassed a removal marker after acquiring the lock.'

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    $archiveCases = @(
        [pscustomobject]@{Entries=@('LeanADB/VERSION');Reject=$false},
        [pscustomobject]@{Entries=@('LeanADB\VERSION');Reject=$false},
        [pscustomobject]@{Entries=@('LeanADB/../outside');Reject=$true},
        [pscustomobject]@{Entries=@('LeanADB\..\outside');Reject=$true},
        [pscustomobject]@{Entries=@('LeanADB/VERSION','LeanADB\version');Reject=$true},
        [pscustomobject]@{Entries=@('LeanADB/VERSION.');Reject=$true},
        [pscustomobject]@{Entries=@(0..64 | ForEach-Object { "LeanADB/file$_" });Reject=$true}
    )
    foreach ($case in $archiveCases) {
        $archivePath = Join-Path $testRoot ('product-' + [guid]::NewGuid().ToString('N') + '.zip')
        $archive = [IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
        try { foreach ($name in $case.Entries) { [void]$archive.CreateEntry($name) } } finally { $archive.Dispose() }
        $rejected = $false
        try { Assert-ProductArchive -ZipPath $archivePath } catch { $rejected = $true }
        Assert-True ($rejected -eq $case.Reject) ('Product archive traversal, duplicate, or entry-count checks failed: ' + ($case.Entries -join '|'))
    }

    $updateBody = @($switch.Clauses | Where-Object {$_.Item1.Extent.Text -eq "'Update'"})[0].Item2.Extent.Text
    $updateAction = [scriptblock]::Create($updateBody.Substring(1,$updateBody.Length-2))
    $script:ProductManifestUrl = 'https://example.test/manifest'
    $SkipProductUpdate = $false; $OfflineZipPath = ''; $Language = 'Korean'
    foreach ($childExit in @(0,9)) {
        $script:ChildExitCode = $childExit
        $previous = Read-State -Root $testRoot; $previous.LeanADBVersion = '1.0.1'
        Write-State -Root $testRoot -State $previous
        $state = Read-State -Root $testRoot
        $handoffFailed = $false
        try { & $updateAction } catch { $handoffFailed = $true }
        $handoff = Get-Content -LiteralPath (Join-Path $testRoot 'handoff.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($handoff.Version -eq '1.0.2' -and $handoff.Language -eq 'Korean' -and $handoff.Force) 'Combined update did not run the newly installed script with the original preferences.'
        Assert-True ($handoffFailed -eq ($childExit -ne 0)) 'Combined update ignored the new script failure.'
        Assert-True ((Read-State -Root $testRoot).LeanADBVersion -eq '1.0.2') 'The old process overwrote the updated app version.'
    }
    $global:LASTEXITCODE = 0
    Write-Host 'LeanADB hardening tests passed: strict settings, device counts, paging, independent checks, native timeout/binary/quoting, transactional recovery, archive safety, and combined update handoff.'
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $resolved = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolved.StartsWith($tempRoot + '\',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('LeanADB-hardening-') -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
