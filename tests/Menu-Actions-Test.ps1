$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'LeanADB.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'LeanADB.ps1 has parser errors.' }
$names = @(
    'Select-AdbDevice', 'Start-AdbSideload', 'Format-Message', 'Remove-InstallationRoot',
    'Test-PrivateIpv4', 'Start-LegacyWireless', 'Return-LegacyWirelessToUsb',
    'Get-AdbProperty', 'Get-AdbSdkLevel', 'Select-FastbootDevice', 'Set-UsbBackend',
    'Save-AdbScreenshot', 'Get-ActiveOutputFolder', 'Get-OutputFolder',
    'Get-PortableFilesPath', 'Get-DeviceFolderEntries', 'Save-AdbBugreport',
    'Receive-AdbPath', 'Show-ConnectionDiagnostics', 'Get-LocalizedDeviceStatus',
    'ConvertTo-AndroidShellLiteral', 'Test-AdbRemoteDirectory',
    'Send-FilesToDevice', 'Install-ApkBatch', 'Save-AdbScreenrecord',
    'Get-AdbStatusAdvice', 'Show-ConnectionGuide', 'Get-DeviceAlias',
    'Get-DeviceDisplayName', 'Set-SelectedAdbDevice', 'Set-DeviceAlias',
    'Invoke-ToolProcess', 'ConvertTo-NativeArgument', 'Get-CommandAdvice',
    'Save-OperationReport', 'Test-CaptureSignature', 'Select-PagedRecord', 'Read-MenuChoice'
)
$definitions = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names }, $true))
if ($definitions.Count -ne $names.Count) { throw 'Expected menu or cleanup function was not found.' }
foreach ($definition in $definitions) {
    . ([scriptblock]::Create($definition.Extent.Text))
}

$script:Messages = @{
    SideloadConfirm = 'Sideload {0} to {1}?'
    SideloadInvalidZip = 'Invalid ZIP.'
    SideloadCancelled = 'Cancelled.'
    SideloadNoDevice = 'No sideload device.'
    NoReadyDevice = 'No device.'
    NoUsbDevice = 'No USB device.'
    NoLegacyNetworkDevice = 'No network device.'
    SelectedDeviceUnavailable = 'Selected device {0} is unavailable.'
    SelectedDeviceWrongState = 'Selected device {0} has status {1}.'
    LegacyWifiHelp = 'Trusted network.'
    LegacyWifiAddress = 'IP address'
    InvalidLocalIp = 'Invalid local IP.'
    LegacyWifiConfirm = 'Connect {0} to {1}?'
    LegacyWifiDisabled = 'Returned to USB.'
    CommandFailed = 'Command failed: {0}'
    UsbBackendChanged = 'USB backend: {0}'
    UsbBackendLegacy = 'Legacy'
    UsbBackendStandard = 'Default'
    UsbBackendFailed = 'USB backend failed.'
    NoFastbootDevice = 'No Fastboot device.'
    ScreenshotFallback = 'Using legacy screenshot method.'
    ScreenshotSaved = 'Screenshot saved: {0}'
    OutputFolderUnavailable = 'Output folder unavailable: {0}'
    BugreportTitle = 'Bug report'
    BugreportPrivacy = 'Private report.'
    BugreportConfirm = 'Collect from {0}?'
    BugreportSaved = 'Saved in: {0}'
    BugreportFailed = 'Failed in: {0}'
    BrowseListFailed = 'Could not list folder.'
    DiagnoseTitle = 'Diagnose'
    DiagnoseAdbVersion = 'ADB: {0}'
    DiagnoseFastbootVersion = 'Fastboot: {0}'
    DiagnoseNoDevice = 'No ADB device.'
    DiagnoseReady = 'ADB ready.'
    DiagnoseUnauthorized = 'Unlock the phone and allow debugging.'
    DiagnoseOffline = 'Reconnect USB.'
    DiagnoseRecovery = 'Recovery mode.'
    DiagnoseSideload = 'Sideload mode.'
    DiagnoseFastboot = 'Fastboot device: {0}'
    DiagnoseNoFastboot = 'No Fastboot device.'
    DiagnoseUsbBackend = 'Backend: {0}'
    DiagnosePathConflict = 'Other ADB: {0}'
    DeviceStatus = '{0} {1} {2}'
    StatusOffline = 'Offline'
    StatusDevice = 'Connected'
    StatusSideload = 'Sideload'
    StatusUnauthorized = 'Unauthorized'
    StatusRecovery = 'Recovery'
    SendBatchItem = 'Sending {0}/{1}: {2}'
    SendBatchSummary = 'Sent: {0} success, {1} failed.'
    InstallBatchItem = 'Installing {0}/{1}: {2}'
    InstallBatchSummary = 'Installed: {0} success, {1} failed.'
    BatchSkipped = 'Skipped: {0}'
    DropSplitHint = 'Use menu 3 for split APKs.'
    ScreenrecordTitle = 'Screen recording'
    ScreenrecordUnknownApi = 'Unknown API.'
    ScreenrecordUnsupported = 'Unsupported API {0}.'
    ScreenrecordNoAudio = 'No audio.'
    ScreenrecordDuration = 'Duration'
    ScreenrecordInvalidDuration = 'Invalid duration.'
    ScreenrecordRunning = 'Recording {0} seconds.'
    ScreenrecordSaved = 'Recording saved: {0}'
    ScreenrecordFailed = 'Recording failed.'
    UninstallIncomplete = 'Uninstall failed: {0} {1}'
    DeviceAliasInvalid = 'Invalid device alias.'
    DevicePreferenceSaveFailed = 'Device preference could not be saved: {0}'
    CommandRetryAdvice = 'Check connection and retry.'
    OperationCancelled = 'Cancelled.'
    OperationTimedOut = 'Timed out.'
    ResultSaved = 'Result saved: {0}'
    WirelessUsbConfirm = 'Return {0} to USB?'
}
$testMessages = $script:Messages
$messageDefinition = $ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$script:Messages'},$true)
. ([scriptblock]::Create($messageDefinition.Extent.Text))
foreach ($name in $testMessages.Keys) { $script:Messages[$name] = $testMessages[$name] }
$script:SelectedZip = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-menu-test-' + [guid]::NewGuid().ToString('N') + '.zip')
$script:RemoveRoot = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-removal-test-' + [guid]::NewGuid().ToString('N'))
$script:ScreenshotRoot = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-screenshot-test-' + [guid]::NewGuid().ToString('N'))
$originalUsbBackend = [Environment]::GetEnvironmentVariable('ADB_USB_LEGACY', 'Process')
$script:TestState = [pscustomobject]@{ ProductId = 'LeanADB'; UsbBackend = 'Standard' }
$script:FakeAdbCalls = @()
$script:ActiveOutputFolder = ''
$script:MockSdk = '19'
$script:MockNormalStatus = 'device'
$script:FailPushPath = ''
$script:PinDeviceSelection = $false
$script:SelectedDeviceSerial = ''
$script:MenuInstallRoot = ''
$script:MenuState = $null
$script:LastBatch = $null
$script:LastSavedPath = ''

function Get-AdbDeviceRecords {
    @(
        [pscustomobject]@{ Serial = 'normal-device'; Status = $script:MockNormalStatus; Model = 'Phone' },
        [pscustomobject]@{ Serial = 'recovery-device'; Status = 'sideload'; Model = 'Recovery' },
        [pscustomobject]@{ Serial = '192.168.1.20:5555'; Status = 'device'; Model = 'Phone' }
    )
}
function Select-LocalFile { return $script:SelectedZip }
function Confirm-MenuAction { return $true }
function Clear-Host { }
function Wait-ForMenuKey { }
function Read-Host { param([string]$Prompt); if ($Prompt -eq 'Duration') { return '1' }; return '192.168.1.20' }
function FakeAdb {
    $script:FakeAdbCalls += ,@($args)
    $global:LASTEXITCODE = 0
    if ($args.Count -ge 3 -and $args[2] -eq 'bugreport') {
        Set-Content -LiteralPath (Join-Path $args[3] 'report.zip') -Value 'private test data' -Encoding ASCII
    }
    if ($args.Count -ge 4 -and $args[2] -eq 'shell' -and $args[3] -like 'ls -1 *') {
        return @('Photo 1.jpg', '한글 파일.txt', '..', 'bad/name')
    }
    if ($args.Count -ge 4 -and $args[2] -eq 'shell' -and ([string]$args[3]).StartsWith('if [ -d ')) { return 'LEANADB_DIR' }
    if ($args.Count -ge 1 -and $args[0] -eq 'version') { return 'Android Debug Bridge version test' }
    if ($args.Count -ge 5 -and $args[3] -eq 'getprop') { return $script:MockSdk }
    if ($args.Count -ge 5 -and $args[2] -eq 'push' -and $args[3] -eq $script:FailPushPath) { $global:LASTEXITCODE = 1 }
    if ($args.Count -ge 5 -and $args[2] -eq 'pull') {
        $target = if (Test-Path -LiteralPath $args[4] -PathType Container) { Join-Path $args[4] 'received.txt' } else { $args[4] }
        $bytes = if ($target -like '*.mp4.partial') { [byte[]](0,0,0,12,102,116,121,112,105,115,111,109) } else { [byte[]](137,80,78,71,13,10,26,10,0,0,0,0) }
        [IO.File]::WriteAllBytes($target,$bytes)
    }
}
function FakeFastboot { $global:LASTEXITCODE = 0; if ($args[0] -eq '--version') { return 'fastboot test' }; return "FB123`tfastboot" }
function Enter-UpdateLock { return 'test-lock' }
function Exit-UpdateLock { }
function Read-State { return $script:TestState }
function Write-State { param($Root, $State); $script:TestState = $State }
function Stop-AdbServer { }
function Get-DownloadsFolder { return $script:ScreenshotRoot }
function Get-RegisteredAdbPath { return 'C:\OtherAdb\adb.exe' }
function Start-Process { return [pscustomobject]@{ ExitCode = 1 } }
function Invoke-MenuCommand {
    param([string]$Executable, [string[]]$Arguments)
    $script:CapturedExecutable = $Executable
    $script:CapturedArguments = @($Arguments)
}

try {
    Set-Content -LiteralPath $script:SelectedZip -Value 'test' -Encoding ASCII
    foreach ($case in @(
        @{ Status = 'device'; Expected = $script:Messages.DiagnoseReady },
        @{ Status = 'unauthorized'; Expected = $script:Messages.DiagnoseUnauthorized },
        @{ Status = 'offline'; Expected = $script:Messages.DiagnoseOffline },
        @{ Status = 'recovery'; Expected = $script:Messages.DiagnoseRecovery },
        @{ Status = 'sideload'; Expected = $script:Messages.DiagnoseSideload }
    )) {
        if ((Get-AdbStatusAdvice -Status $case.Status) -ne $case.Expected) { throw "Wrong connection guidance for $($case.Status)." }
    }
    $chosen = Select-AdbDevice -AdbPath 'fake-adb.exe' -AllowedStatuses @('sideload')
    if ($chosen -ne 'recovery-device') { throw 'Sideload selector chose a normal ADB device.' }
    Start-AdbSideload -AdbPath 'fake-adb.exe'
    if ($script:CapturedExecutable -ne 'fake-adb.exe') { throw 'Sideload used the wrong executable.' }
    if (($script:CapturedArguments -join '|') -ne ("-s|recovery-device|sideload|$script:SelectedZip")) {
        throw "Sideload arguments are wrong: $($script:CapturedArguments -join '|')"
    }

    if ((Select-AdbDevice -AdbPath 'FakeAdb' -UsbOnly) -ne 'normal-device') { throw 'USB device filter failed.' }
    if ((Select-AdbDevice -AdbPath 'FakeAdb' -NetworkOnly) -ne '192.168.1.20:5555') { throw 'Network device filter failed.' }
    $script:PinDeviceSelection = $true
    $script:SelectedDeviceSerial = 'disconnected-device'
    if ($null -ne (Select-AdbDevice -AdbPath 'FakeAdb' -UsbOnly)) { throw 'Selector switched to another device after the selected one disappeared.' }
    if ($script:SelectedDeviceSerial -ne 'disconnected-device') { throw 'Selector changed the pinned device without confirmation.' }
    if ((Select-AdbDevice -AdbPath 'FakeAdb' -UsbOnly -ChooseAnother) -ne 'normal-device') { throw 'Explicit device reselection failed.' }
    if ($script:SelectedDeviceSerial -ne 'normal-device') { throw 'Explicit device reselection was not retained.' }
    $script:MenuInstallRoot = $script:RemoveRoot
    $script:TestState | Add-Member -NotePropertyName RecentDevices -NotePropertyValue @() -Force
    foreach ($serial in @('one', 'two', 'three', 'four', 'five', 'six', 'three')) {
        Set-SelectedAdbDevice -Serial $serial
    }
    if ((@($script:TestState.RecentDevices) -join '|') -ne 'three|six|five|four|two') { throw 'Recent device ordering or five-device limit failed.' }
    if ((Set-DeviceAlias -Root $script:RemoveRoot -Serial 'three' -Alias 'Work Phone') -ne 'Work Phone') { throw 'Device alias was not saved.' }
    if ((Get-DeviceDisplayName -State $script:TestState -Serial 'three') -ne 'Work Phone [three]') { throw 'Device alias was not displayed.' }
    $rejectedAlias = $false
    try { Set-DeviceAlias -Root $script:RemoveRoot -Serial 'three' -Alias ('x' * 33) | Out-Null } catch { $rejectedAlias = $true }
    if (-not $rejectedAlias) { throw 'Overlong device alias was accepted.' }
    [void](Set-DeviceAlias -Root $script:RemoveRoot -Serial 'three' -Alias '')
    if ((Get-DeviceAlias -State $script:TestState -Serial 'three') -ne '') { throw 'Device alias removal failed.' }
    $script:MenuInstallRoot = ''
    $script:MenuState = $null
    $script:SelectedDeviceSerial = 'normal-device'
    $script:MockNormalStatus = 'offline'
    if ($null -ne (Select-AdbDevice -AdbPath 'FakeAdb')) { throw 'Selector used an offline target or switched to another device.' }
    if ($script:SelectedDeviceSerial -ne 'normal-device') { throw 'Offline status changed the pinned device.' }
    $script:MockNormalStatus = 'device'
    $script:PinDeviceSelection = $false
    $script:SelectedDeviceSerial = ''
    if (-not (Test-PrivateIpv4 -Address '172.16.1.2') -or
        (Test-PrivateIpv4 -Address '8.8.8.8') -or
        (Test-PrivateIpv4 -Address '192.168.1.999')) { throw 'Private IPv4 validation failed.' }
    if ((Get-AdbSdkLevel -AdbPath 'FakeAdb' -Serial 'normal-device') -ne 19) { throw 'Older Android API detection failed.' }
    if ((Select-FastbootDevice -FastbootPath 'FakeFastboot') -ne 'FB123') { throw 'Fastboot selection failed.' }

    Start-LegacyWireless -AdbPath 'FakeAdb'
    if (($script:CapturedArguments -join '|') -ne 'connect|192.168.1.20:5555') { throw 'Legacy Wi-Fi connect command was wrong.' }
    if (-not @($script:FakeAdbCalls | Where-Object { ($_ -join '|') -eq '-s|normal-device|tcpip|5555' }).Count) {
        throw 'Legacy Wi-Fi did not configure the selected USB device.'
    }
    Return-LegacyWirelessToUsb -AdbPath 'FakeAdb'
    if (-not @($script:FakeAdbCalls | Where-Object { ($_ -join '|') -eq '-s|192.168.1.20:5555|usb' }).Count) {
        throw 'Legacy Wi-Fi did not return the selected network device to USB.'
    }

    Set-UsbBackend -Root $script:RemoveRoot -AdbPath 'FakeAdb' -Preference Legacy
    if ($env:ADB_USB_LEGACY -ne '1' -or $script:TestState.UsbBackend -ne 'Legacy') { throw 'Legacy USB preference was not saved.' }
    Set-UsbBackend -Root $script:RemoveRoot -AdbPath 'FakeAdb' -Preference Standard
    if ($env:ADB_USB_LEGACY -or $script:TestState.UsbBackend -ne 'Standard') { throw 'Default USB preference was not restored.' }

    New-Item -ItemType Directory -Path $script:ScreenshotRoot | Out-Null
    $portableFolder = Get-OutputFolder -Root (Join-Path $script:ScreenshotRoot 'LeanADB') -State ([pscustomobject]@{ PathRegistered = $false; ShortcutRegistered = $false })
    if ($portableFolder -ne (Join-Path $script:ScreenshotRoot 'LeanADB-Files')) { throw 'Portable files would be placed inside the installation.' }
    $entries = @(Get-DeviceFolderEntries -AdbPath 'FakeAdb' -Serial 'normal-device' -Folder '/sdcard/Download')
    if ($entries.Count -ne 2 -or 'Photo 1.jpg' -notin $entries -or '한글 파일.txt' -notin $entries) {
        throw 'Device file listing did not preserve safe Unicode names or reject unsafe names.'
    }
    if ((ConvertTo-AndroidShellLiteral -Value "/sdcard/a'b") -ne "'/sdcard/a'\''b'") { throw 'Remote shell quoting is unsafe.' }
    if (-not (Test-AdbRemoteDirectory -AdbPath 'FakeAdb' -Serial 'normal-device' -Path '/sdcard/DCIM/Camera')) {
        throw 'Remote directory browsing failed.'
    }
    Save-AdbScreenshot -AdbPath 'FakeAdb' -Serial 'normal-device'
    $capturedImages = @(Get-ChildItem -LiteralPath $script:ScreenshotRoot -Filter 'LeanADB-Screenshot-*.png' -File)
    if ($capturedImages.Count -ne 1 -or $capturedImages[0].Length -eq 0) { throw 'Legacy screenshot fallback did not save the image.' }
    if (-not @($script:FakeAdbCalls | Where-Object { $_.Count -ge 4 -and $_[2] -eq 'shell' -and $_[3] -eq 'rm' }).Count) {
        throw 'Legacy screenshot fallback did not clean its remote temporary file.'
    }
    Receive-AdbPath -AdbPath 'FakeAdb' -Serial 'normal-device' -RemotePath '/sdcard/Download/한글 파일.txt'
    if (-not @($script:FakeAdbCalls | Where-Object { $_.Count -ge 4 -and $_[2] -eq 'pull' -and $_[3] -eq '/sdcard/Download/한글 파일.txt' }).Count) {
        throw 'Device file receiving lost a Unicode filename.'
    }
    Save-AdbBugreport -AdbPath 'FakeAdb' -Serial 'normal-device'
    if (-not @(Get-ChildItem -LiteralPath $script:ScreenshotRoot -Directory -Filter 'LeanADB-Bugreport-*').Count) {
        throw 'Bug report was not saved.'
    }
    Show-ConnectionDiagnostics -Root $script:ScreenshotRoot -AdbPath 'FakeAdb' -FastbootPath 'FakeFastboot' -State $script:TestState
    $fileOne = Join-Path $script:ScreenshotRoot ((-join @([char]0xD55C, [char]0xAE00)) + ' file.txt')
    $fileTwo = Join-Path $script:ScreenshotRoot 'second file.txt'
    $apkOne = Join-Path $script:ScreenshotRoot 'example.apk'
    foreach ($path in @($fileOne, $fileTwo, $apkOne)) { Set-Content -LiteralPath $path -Value 'test' -Encoding ASCII }
    Send-FilesToDevice -AdbPath 'FakeAdb' -Serial 'normal-device' -Paths @($fileOne, $fileTwo)
    if (@($script:FakeAdbCalls | Where-Object { $_.Count -ge 3 -and $_[2] -eq 'push' }).Count -ne 2) { throw 'Batch transfer did not send two files.' }
    $script:FailPushPath = $fileOne
    Send-FilesToDevice -AdbPath 'FakeAdb' -Serial 'normal-device' -Paths @($fileOne, $fileTwo)
    $script:FailPushPath = ''
    if (@($script:FakeAdbCalls | Where-Object { $_.Count -ge 3 -and $_[2] -eq 'push' }).Count -ne 4) { throw 'Batch transfer stopped after one failed file.' }
    Install-ApkBatch -AdbPath 'FakeAdb' -Serial 'normal-device' -Paths @($apkOne)
    if (-not @($script:FakeAdbCalls | Where-Object { $_.Count -ge 5 -and $_[2] -eq 'install' -and $_[4] -eq $apkOne }).Count) {
        throw 'Dropped APK was not installed.'
    }
    Save-AdbScreenrecord -AdbPath 'FakeAdb' -Serial 'normal-device'
    if (@(Get-ChildItem -LiteralPath $script:ScreenshotRoot -File -Filter 'LeanADB-Recording-*.mp4').Count -ne 1) {
        throw 'Screen recording was not saved.'
    }
    $screenrecordCount = @($script:FakeAdbCalls | Where-Object { $_.Count -ge 4 -and $_[2] -eq 'shell' -and $_[3] -eq 'screenrecord' }).Count
    $script:MockSdk = '18'
    Save-AdbScreenrecord -AdbPath 'FakeAdb' -Serial 'normal-device'
    if (@($script:FakeAdbCalls | Where-Object { $_.Count -ge 4 -and $_[2] -eq 'shell' -and $_[3] -eq 'screenrecord' }).Count -ne $screenrecordCount) {
        throw 'Screen recording ran on an unsupported Android API.'
    }

    New-Item -ItemType Directory -Path $script:RemoveRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $script:RemoveRoot 'owned.txt') -Value 'test' -Encoding ASCII
    Remove-InstallationRoot -Root $script:RemoveRoot
    if (Test-Path -LiteralPath $script:RemoveRoot) { throw 'Cleanup left its test directory behind.' }
    Write-Host 'LeanADB menu action and cleanup tests passed.'
}
finally {
    [Environment]::SetEnvironmentVariable('ADB_USB_LEGACY', $originalUsbBackend, 'Process')
    if (Test-Path -LiteralPath $script:SelectedZip) { Remove-Item -LiteralPath $script:SelectedZip -Force }
    if (Test-Path -LiteralPath $script:RemoveRoot) { Remove-Item -LiteralPath $script:RemoveRoot -Recurse -Force }
    if (Test-Path -LiteralPath $script:ScreenshotRoot) { Remove-Item -LiteralPath $script:ScreenshotRoot -Recurse -Force }
}
