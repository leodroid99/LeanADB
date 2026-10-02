[CmdletBinding()]
param(
    [ValidateSet('Install', 'Update', 'AutoUpdate', 'Check', 'Status', 'Devices', 'Menu', 'Terminal', 'Drop', 'SelfUpdate', 'Repair', 'FailureHelp', 'Uninstall')]
    [string]$Action = 'Install',

    [string]$InstallPath = (Join-Path $env:LOCALAPPDATA 'LeanADB'),

    [string]$ProductManifestUrl = '',

    [string]$OfflineZipPath = '',

    [string[]]$DroppedPaths = @(),

    [ValidateSet('Auto', 'English', 'Korean')]
    [string]$Language = 'Auto',

    [switch]$AcceptSdkLicense,
    [switch]$NoPath,
    [switch]$NoShortcut,
    [switch]$Force,
    [switch]$ConfirmUninstall,
    [switch]$SkipProductUpdate,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:ProductId = 'LeanADB'
$script:ActiveOutputFolder = ''
$script:SelectedDeviceSerial = ''
$script:PinDeviceSelection = $false
$script:MenuInstallRoot = ''
$script:MenuState = $null
$script:LastBatch = $null
$script:AnyBatchFailure = $false
$script:LastSavedPath = ''
$script:StateRecoveredFromBackup = $false
$script:ProductVersion = '1.1.0'
$versionFile = Join-Path $PSScriptRoot 'VERSION'
if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
    $versionText = (Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8).Trim()
    if ($versionText) {
        $script:ProductVersion = $versionText
    }
}
$script:SourceUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
$script:ReleaseNotesUrl = 'https://developer.android.com/tools/releases/platform-tools'
$script:LicenseUrl = 'https://developer.android.com/studio/terms'
$script:ProductManifestUrl = $ProductManifestUrl
if (-not $script:ProductManifestUrl) {
    $updateUrlFile = Join-Path $PSScriptRoot 'UPDATE_URL'
    if (Test-Path -LiteralPath $updateUrlFile -PathType Leaf) {
        $script:ProductManifestUrl = (Get-Content -LiteralPath $updateUrlFile -Raw -Encoding UTF8).Trim()
    }
}
$script:CheckIntervalHours = 24
$script:FailedCheckBackoffHours = 6
$script:MetadataTimeoutSeconds = 30
$script:DownloadTimeoutSeconds = 180
$script:MinimumInstallFreeBytes = 64MB
$script:ErrorLogPath = Join-Path ([System.IO.Path]::GetTempPath()) 'LeanADB-install-error.log'
if ($Action -eq 'Install' -and (Test-Path -LiteralPath $script:ErrorLogPath -PathType Leaf)) {
    Remove-Item -LiteralPath $script:ErrorLogPath -Force -ErrorAction SilentlyContinue
}
$script:Messages = @{
    Error = 'ERROR'
    ErrorLog = 'Error log'
    ProductDescription = 'LeanADB will download Android SDK Platform-Tools directly from Google.'
    GoogleLicense = 'Platform-Tools: Copyright Google LLC / Android SDK License'
    ScriptLicense = 'LeanADB scripts: Copyright 2026 leodroid99 / MIT License'
    AcceptInstall = '[ ENTER ]  ACCEPT THE GOOGLE SDK LICENSE AND INSTALL'
    Cancel = '[  ESC  ]  CANCEL'
    LicenseAccepted = 'License accepted. Starting installation...'
    InstallationCancelled = 'Installation cancelled. Nothing was changed.'
    ChooseLocation = 'WHERE SHOULD LEANADB BE INSTALLED?'
    DownloadsOption = '[ D ] Downloads folder'
    DesktopOption = '[ B ] Desktop'
    StandardOption = '[ ENTER or S ] Standard app folder - recommended'
    StandardOtherOption = '[ S ] Standard app folder'
    ExistingOption = '[ ENTER ] Keep this existing installation'
    PortableOption = '[ P ] Beside this installer (portable, no PATH or Start Menu changes)'
    LocationHelp = 'Press Enter, S, D, B, P, or C. Press Esc to cancel.'
    Downloading = 'Downloading the official Android SDK Platform-Tools package...'
    InstalledVersion = 'Installed Platform-Tools {0}.'
    InstallationFolder = 'Installation folder: {0}'
    InstallCompleted = 'LEANADB INSTALLATION COMPLETED'
    AdbFolder = 'ADB and Fastboot folder:'
    StartMenu = 'Start Menu: LeanADB'
    PortableInstallHint = 'Portable installation: use the launchers in this folder; PATH and Start Menu were not changed.'
    DownloadsHint = 'The terminal starts in the selected file folder. Choose 6 (Settings), then 3 (Save location) in the easy menu to change it.'
    OpeningFolder = 'Opening the ADB and Fastboot folder now...'
    CloseKey = 'Press Enter to open LeanADB, or Esc to close.'
    AlreadyInstalled = 'LeanADB {0} is already installed. Checking for updates...'
    UpToDateRefreshed = 'Already up to date. LeanADB launchers were refreshed.'
    AlreadyUpToDate = 'Already up to date: {0}'
    UpdateAvailable = 'An updated Google package is available.'
    AutoUpdateFailed = 'Automatic update check failed; existing tools remain available. {0}'
    NotInstalled = 'LeanADB is not installed at {0}'
    Uninstalled = 'Uninstalled LeanADB.'
    UninstalledDeferred = 'Uninstalled LeanADB. Installation files will be removed momentarily.'
    MenuTitle = 'LEANADB EASY MENU'
    MenuVersion = 'LeanADB {0} / Google Platform-Tools {1}'
    MenuAdbDevices = '[ 1 ] Connect or check a device'
    MenuFastbootDevices = '[ 2 ] Check Fastboot devices'
    MenuInstallApk = '[ 3 ] Select and install an APK'
    MenuPushFile = '[ 4 ] Send one or more files to device Downloads'
    MenuTerminal = '[ 5 ] Open advanced terminal'
    MenuUpdate = '[ 6 ] Check for updates'
    MenuOpenFolder = '[ 7 ] Open LeanADB folder'
    MenuScreenshot = '[ S ] Save a device screenshot'
    MenuWireless = '[ W ] Wireless debugging'
    MenuReceive = '[ R ] Receive a device path manually'
    MenuLogcat = '[ L ] Save device logs'
    MenuHelpTools = '[ H ] Connection and USB driver help'
    MenuLanguage = '[ G ] Language'
    MenuDeviceInfo = '[ D ] Device details and compatibility'
    MenuExtras = '[ T ] Files and diagnostics'
    MenuDiagnose = '[ X ] Diagnose a connection problem'
    MenuBrowse = '[ F ] Browse and receive device files'
    MenuBugreport = '[ E ] Save a device bug report'
    MenuOutput = '[ O ] Choose where files are saved'
    MenuOfflineZip = '[ U ] Install a local Google Platform-Tools ZIP'
    MenuScreenrecord = '[ V ] Record the device screen'
    MenuSideload = '[ I ] Sideload an update ZIP'
    MenuReboot = '[ B ] Reboot a device'
    MenuExit = '[ ESC or Q ] Exit'
    MenuHelp = 'Enable USB debugging for ADB. Fastboot works only while the device is in bootloader mode.'
    PressAnyKey = 'Press any key to return to the menu.'
    ChooseApk = 'Choose an APK to install'
    ChooseFile = 'Choose a file to send to the device'
    InstallingApk = 'Installing: {0}'
    SendingFile = 'Sending to /sdcard/Download/{0}'
    CommandSucceeded = 'Completed successfully.'
    CommandFailed = 'The command failed (exit code {0}). Read the output above.'
    AdbDeviceHint = 'If the list is empty, connect the device, enable USB debugging, and accept the authorization prompt.'
    FastbootDeviceHint = 'If the list is empty, boot into fastboot/bootloader mode and check the USB driver.'
    TerminalOpened = 'The advanced terminal was opened in a new window.'
    ChooseDevice = 'CHOOSE AN ADB DEVICE'
    ChooseDeviceHelp = 'Press a device number. Press Esc to cancel.'
    NoReadyDevice = 'No authorized ADB device is ready. Check USB debugging and device authorization.'
    UpdateCheckRunning = 'Checking for Platform-Tools updates in the background...'
    UpdateReady = 'An update is available. Choose 6 (Settings) > 1 (Update) to install it.'
    UninstallTitle = 'REMOVE LEANADB?'
    UninstallConfirm = '[ ENTER ]  REMOVE LEANADB'
    UninstallKeep = '[  ESC  ]  CANCEL AND KEEP LEANADB'
    UninstallCancelled = 'Uninstall cancelled. Nothing was changed.'
    UpdateBusy = 'Another LeanADB installation or update is already running.'
    CustomOption = '[ C ] Choose another folder'
    StandardRecommended = '[ ENTER or S ] Standard app folder - recommended'
    PathConflict = 'Another adb may take priority in regular terminals: {0}'
    ChooseApks = 'Choose one or more APK files to install'
    InstallingApks = 'Installing {0} split APK files on {1}'
    ScreenshotSaved = 'Screenshot saved: {0}'
    WirelessTitle = 'WIRELESS DEBUGGING'
    WirelessPair = '[ P ] Pair a new device'
    WirelessConnect = '[ C ] Connect to a paired device'
    WirelessDisconnect = '[ D ] Disconnect all wireless devices'
    WirelessLegacy = '[ L ] Older Android: Wi-Fi with USB setup'
    WirelessReturnUsb = '[ U ] Return a legacy Wi-Fi device to USB'
    WirelessBack = '[ ESC ] Back'
    PairAddress = 'Pairing address shown on the device (IP:port)'
    PairCode = 'Six-digit pairing code'
    ConnectAddress = 'Wireless debugging address (IP:port)'
    InvalidEndpoint = 'Enter an address in the form IP:port, for example 192.168.0.10:37099.'
    InvalidPairCode = 'Enter the six-digit pairing code shown on the device.'
    DeviceStatus = '{0}  {1}  {2}'
    ExistingLocation = 'Existing LeanADB installation found. Reusing: {0}'
    ProductUpdateReady = 'LeanADB {0} is available. Choose 6 (Settings) > 1 (Update) to install it.'
    ProductUpdating = 'Updating LeanADB to {0}...'
    ProductUpdated = 'LeanADB was updated to {0}.'
    ProductUpToDate = 'LeanADB is already up to date: {0}'
    ProductUpdatesNotConfigured = 'LeanADB app updates are not configured in this build. Google Platform-Tools updates are still checked.'
    InvalidManifest = 'The LeanADB update manifest is invalid.'
    RemotePathPrompt = 'Device path to receive (for example /sdcard/Download/file.zip)'
    InvalidRemotePath = 'For safety, enter a path under /sdcard/ or /storage/.'
    ReceiveCompleted = 'Received files are in: {0}'
    LogcatSaved = 'Device log saved: {0}'
    HelpTitle = 'CONNECTION HELP'
    HelpDrivers = '[ D ] Open official OEM USB driver guide'
    HelpDeviceManager = '[ M ] Open Windows Device Manager'
    HelpLicense = '[ T ] Open Android SDK license'
    HelpBack = '[ ESC ] Back'
    TerminalByline = 'LeanADB by leodroid99'
    TerminalWorking = 'Working folder: %CD%'
    TerminalTry = 'Try: adb devices'
    InstallFailed = 'LeanADB installation failed. Review the error shown above.'
    SeeErrorLog = 'Error log: {0}'
    RepairRecoveredBackup = 'Recovered LeanADB settings from the last valid state backup.'
    RepairRebuiltState = 'Rebuilt LeanADB state from the verified installed Platform-Tools.'
    RepairCompleted = 'LeanADB repair completed. Settings and launchers were refreshed.'
    RepairMenuHint = 'Choose 6 (Settings) > 2 (Repair), or run Repair LeanADB.cmd if settings cannot be read.'
    MenuRepair = '[ Y ] Repair LeanADB installation'
    MenuChooseDevice = '[ C ] Choose target device'
    MenuNameDevice = '[ A ] Name the selected device'
    MenuTargetNone = 'Target device: not selected'
    MenuTargetSelected = 'Target device: {0} ({1})'
    MenuTargetUnavailable = 'Target device: {0} (disconnected or unavailable)'
    MenuRecentDevice = 'Recent device: {0} (press C to select it)'
    SelectedDeviceUnavailable = 'The selected device {0} is unavailable for this action. Press C in the main menu to choose a device.'
    SelectedDeviceWrongState = 'The selected device {0} is {1}, which this action cannot use. Check the device mode or press C to choose another.'
    DeviceAliasPrompt = 'Name for {0} (up to 32 characters; blank removes the name)'
    DeviceAliasSaved = 'Device name saved: {0}'
    DeviceAliasRemoved = 'Device name removed.'
    DeviceAliasInvalid = 'Use up to 32 characters without control characters.'
    DeviceAliasNoTarget = 'Choose an ADB target with C first.'
    DevicePreferenceSaveFailed = 'Could not save the recent device: {0}'
    UnsupportedWindows = 'LeanADB supports 64-bit Windows 10 and Windows 11.'
    UnsupportedPowerShell = 'LeanADB requires Windows PowerShell 5.1 or newer.'
    StatusDevice = 'Connected'
    StatusUnauthorized = 'Authorization required'
    StatusOffline = 'Offline'
    StatusRecovery = 'Recovery'
    StatusSideload = 'Sideload'
    InsufficientSpace = 'Not enough free disk space on {0}. LeanADB needs at least {1} MB free.'
    UnsafeInstallPath = 'Refusing to use an unsafe installation path: {0}'
    NonEmptyInstallPath = 'The selected folder is not an existing LeanADB installation and is not empty: {0}'
    LanguageTitle = 'DISPLAY LANGUAGE'
    LanguageAuto = '[ A ] Automatic (Windows display language)'
    LanguageEnglish = '[ E ] English'
    LanguageKorean = '[ K ] Korean'
    LanguageSaved = 'Language preference saved.'
    SideloadNoDevice = 'No device is in ADB sideload mode. Enable sideload in recovery, then reconnect it.'
    SideloadChooseZip = 'Choose the update ZIP to sideload'
    SideloadConfirm = 'Press Enter to sideload {0} to {1}, or Esc to cancel.'
    SideloadCancelled = 'Sideload cancelled.'
    RebootTitle = 'REBOOT DEVICE'
    RebootSystem = '[ 1 ] Reboot to Android'
    RebootBootloader = '[ 2 ] Reboot to bootloader'
    RebootConfirm = 'Press Enter to reboot {0} to {1}, or Esc to cancel.'
    RebootDestinationSystem = 'Android'
    RebootDestinationBootloader = 'bootloader'
    SideloadInvalidZip = 'Select an existing ZIP file to sideload.'
    UninstallIncomplete = 'LeanADB could not remove all files in {0}. {1}'
    DeviceInfoTitle = 'DEVICE DETAILS'
    DeviceInfoLine = '{0}: {1}'
    DeviceInfoModel = 'Model'
    DeviceInfoAndroid = 'Android version'
    DeviceInfoSdk = 'API level'
    DeviceInfoAbi = 'CPU architecture'
    DeviceInfoUnknown = 'Unknown'
    DeviceInfoOldWifi = 'For Android 10 or older, use Wireless > L after connecting USB.'
    DeviceInfoNewWifi = 'Android 11 or newer can use Wireless > P pairing.'
    SplitApkUnsupported = 'This device is below Android 5.0 (API 21). Select one compatible APK instead of split APKs.'
    NoUsbDevice = 'No authorized USB device is ready. Connect a USB cable and enable debugging first.'
    NoLegacyNetworkDevice = 'No legacy Wi-Fi device is connected.'
    LegacyWifiHelp = 'Use the same trusted Wi-Fi network on the PC and phone. Keep USB connected for setup.'
    LegacyWifiAddress = 'Phone Wi-Fi IPv4 address (example 192.168.1.50)'
    InvalidLocalIp = 'Enter a private IPv4 address from the phone Wi-Fi settings.'
    LegacyWifiConfirm = 'Press Enter to enable port 5555 on {0} and connect to {1}, or Esc to cancel.'
    LegacyWifiDisabled = 'The device returned to USB mode. Reconnect the cable if needed.'
    HelpLegacyUsb = '[ L ] Restart ADB with legacy USB backend'
    HelpDefaultUsb = '[ N ] Restart ADB with default USB backend'
    UsbBackendChanged = 'ADB USB backend: {0}. This setting applies to LeanADB launchers.'
    UsbBackendLegacy = 'Legacy'
    UsbBackendStandard = 'Default'
    UsbBackendFailed = 'ADB could not restart with the selected USB backend.'
    RebootFastboot = '[ 3 ] Reboot a Fastboot device to Android'
    NoFastbootDevice = 'No device is in Fastboot mode. Check the bootloader screen and USB driver.'
    ScreenshotFallback = 'Direct screenshot failed; trying the older shell-and-pull method...'
    OutputFolderTitle = 'FILE SAVE LOCATION'
    OutputFolderCurrent = 'Current: {0}'
    OutputFolderDownloads = '[ D ] Windows Downloads folder'
    OutputFolderPortable = '[ P ] Beside LeanADB (kept when LeanADB is uninstalled)'
    OutputFolderCustom = '[ C ] Choose a folder'
    OutputFolderSaved = 'File save location changed to: {0}'
    OutputFolderUnavailable = 'The selected file save location is unavailable: {0}'
    SavedFilesFolder = 'Screenshots, logs, received files, and bug reports: {0}'
    DiagnoseTitle = 'CONNECTION DIAGNOSIS'
    DiagnoseAdbVersion = 'ADB: {0}'
    DiagnoseFastbootVersion = 'Fastboot: {0}'
    DiagnoseNoDevice = 'No ADB device is visible. Check the cable, USB debugging, and the Windows OEM USB driver.'
    DiagnoseUnauthorized = 'Authorization is pending. Unlock the phone and accept its USB debugging prompt.'
    DiagnoseOffline = 'ADB sees an offline device. Reconnect USB, then try the USB backend option in Help.'
    DiagnoseReady = 'ADB connection is ready.'
    DiagnoseRecovery = 'Device is in recovery; normal Android commands may be unavailable.'
    DiagnoseSideload = 'Device is in sideload mode; only sideload-related commands are available.'
    DiagnoseFastboot = 'Fastboot sees a bootloader device: {0}'
    DiagnoseNoFastboot = 'No Fastboot device is visible. Fastboot requires bootloader mode and the correct USB driver.'
    DiagnosePathConflict = 'Another ADB may run in a regular terminal: {0}'
    DiagnoseUsbBackend = 'Windows ADB USB backend: {0}'
    ConnectionGuideTitle = 'CONNECT A DEVICE'
    ConnectionGuideRefresh = '[ R ] Refresh connections'
    ConnectionGuideChoose = '[ C ] Choose an ADB target'
    ConnectionGuideDiagnose = '[ X ] Full connection diagnosis'
    ConnectionGuideHelp = '[ H ] USB and driver help'
    ConnectionGuideBack = '[ ESC ] Back to main menu'
    ConnectionGuideMultiple = 'Multiple ADB devices are visible. Press C to choose the target.'
    ConnectionGuideFastbootOnly = 'A device is in Fastboot mode. Use the Fastboot actions, or reboot it to Android for ADB.'
    BrowseTitle = 'BROWSE DEVICE FILES'
    BrowseDownload = '[ D ] Download'
    BrowseDcim = '[ C ] Camera photos (DCIM)'
    BrowsePictures = '[ P ] Pictures'
    BrowseDocuments = '[ O ] Documents'
    BrowseRoot = '[ R ] Shared storage root'
    BrowseEmpty = 'This folder is empty or not available. You can still use R to enter a path manually.'
    BrowseListFailed = 'Could not list this folder on the device. Try another folder or manual path entry.'
    BrowseChoose = 'Number: open a folder or receive a file; G: receive this folder; B: back; N/P: page; blank: cancel'
    BrowseListing = 'Device folder: {0} (page {1} of {2})'
    BrowseFolderConfirm = 'Press Enter to receive the entire folder {0}, or Esc to cancel.'
    OutputInsideInstall = 'Choose a folder outside the LeanADB installation so uninstall cannot delete your saved files.'
    BugreportTitle = 'SAVE DEVICE BUG REPORT'
    BugreportPrivacy = 'Bug reports can contain accounts, app data, logs, and other private information. Share the result only with people you trust.'
    BugreportConfirm = 'Press Enter to collect a bug report from {0}, or Esc to cancel.'
    BugreportSaved = 'Bug report saved in: {0}'
    BugreportFailed = 'Bug report failed or produced no file. Check the output above; partial files may remain in: {0}'
    ChooseFiles = 'Choose one or more files to send to the device'
    SendBatchItem = 'Sending {0} of {1}: {2}'
    SendBatchSummary = 'Transfer finished: {0} succeeded, {1} failed.'
    InstallBatchItem = 'Installing APK {0} of {1}: {2}'
    InstallBatchSummary = 'APK installation finished: {0} succeeded, {1} failed.'
    BatchSkipped = 'Skipping missing or unsupported file: {0}'
    DropTitle = 'LEANADB DRAG AND DROP'
    DropAllApks = 'All dropped files are APKs. LeanADB will install them one at a time.'
    DropMixed = 'Dropped files include APKs and other files.'
    DropSendAll = '[ ENTER ] Send all files to device Downloads'
    DropInstallAndSend = '[ I ] Install APKs and send the other files'
    DropCancel = '[ ESC ] Cancel'
    DropNoFiles = 'Drop one or more existing files onto Drop files on LeanADB.cmd.'
    DropSplitHint = 'For split APKs belonging to one app, choose Apps > Install APK > One split-APK set.'
    OfflineZipChoose = 'Choose the official Google Platform-Tools Windows ZIP'
    OfflineZipConfirm = 'Press Enter to install this local ZIP: {0}. Press Esc to cancel.'
    OfflineZipInvalid = 'Select an existing .zip file. Only a package with valid Google-signed ADB and Fastboot is accepted.'
    OfflineZipOlder = 'The local Platform-Tools package is older than the installed version ({0} < {1}). Refusing to downgrade.'
    OfflineZipStatus = 'Installed from a local ZIP. Online update availability is unknown until an online package is installed.'
    ScreenrecordTitle = 'RECORD DEVICE SCREEN'
    ScreenrecordDuration = 'Recording duration in seconds (1-180, Enter = 30)'
    ScreenrecordUnsupported = 'Screen recording requires Android 4.4 (API 19) or newer. This device reports API {0}.'
    ScreenrecordUnknownApi = 'Could not determine the Android API level. Use the advanced terminal if this device supports screenrecord.'
    ScreenrecordInvalidDuration = 'Enter a whole number between 1 and 180 seconds.'
    ScreenrecordNoAudio = 'The built-in Android screen recorder does not capture audio and stops after at most 180 seconds.'
    ScreenrecordRunning = 'Recording for {0} seconds. Keep the device connected...'
    ScreenrecordSaved = 'Screen recording saved: {0}'
    ScreenrecordFailed = 'Screen recording failed; no video was saved.'
    HomeConnect = 'Connect / check a device'
    HomeApps = 'Install apps'
    HomeFiles = 'Send / receive / capture files'
    HomeDevice = 'Device tools'
    HomeTerminal = 'Advanced terminal'
    HomeSettings = 'Settings / updates / repair'
    HomeSaved = 'Open saved files'
    HomeShortcuts = 'C: choose device   A: name device   Q / Esc: exit'
    MenuBackHint = 'Choose a number. Esc: back'
    ActionInstall = 'Choose APK files'
    ActionSend = 'Send files to the device'
    ActionBrowse = 'Browse and receive device files'
    ActionReceive = 'Receive a path manually'
    ActionScreenshot = 'Save a screenshot'
    ActionRecord = 'Record the screen'
    ActionRecent = 'Open a recent saved file'
    ActionInfo = 'Device information'
    ActionReboot = 'Restart Android / bootloader'
    ActionSideload = 'Install a recovery update ZIP'
    ActionWireless = 'Wireless connection'
    ActionLogcat = 'Save device logs'
    ActionBugreport = 'Save a bug report'
    ActionFastboot = 'Check Fastboot devices'
    ActionUpdate = 'Check and install updates'
    ActionRepair = 'Repair LeanADB'
    ActionOutput = 'Choose where files are saved'
    ActionLanguage = 'Display language'
    ActionInstallFolder = 'Open the installation folder'
    ActionDiagnose = 'Connection diagnosis'
    ActionDriver = 'USB driver help'
    ActionOffline = 'Update from an official Google ZIP'
    ApkModeTitle = 'You selected {0} APK files. How should they be installed?'
    ApkModeIndependent = '[ 1 ] Separate apps: install each APK individually'
    ApkModeSplit = '[ 2 ] One app: install all files as a split-APK set'
    ApkModeHint = 'Choose 2 only when all APKs belong to the same app and version. Esc: cancel.'
    MenuRetry = '[ R ] Retry failed items from the last batch'
    NoFailedBatch = 'There are no failed batch items to retry in this session.'
    RetryWrongDevice = 'Choose the original device before retrying. No files were sent to another device.'
    RetryConfirm = 'Press Enter to retry {0} items on {1}, or Esc to cancel.'
    ResultSaved = 'Operation results saved: {0}'
    OperationProgress = 'Working... {0}s elapsed. Esc: stop this command.'
    OperationCancelled = 'The PC command was stopped. Check the device: its operation may still be finishing.'
    OperationTimedOut = 'The command exceeded its time limit. Check the connection and retry.'
    ApkSignatureAdvice = 'The existing app has a different signature. Use a matching APK; removing the existing app can erase its data.'
    StorageAdvice = 'Free some storage on the device, then retry.'
    ApkAbiAdvice = 'Choose an APK that supports this device CPU architecture.'
    ApkDowngradeAdvice = 'The installed app is newer. Choose the same or a newer version.'
    ApkSplitAdvice = 'This APK set is incomplete or invalid. Choose the base APK and matching splits from the same app/version.'
    PermissionAdvice = 'This device denied access. Choose a shared-storage folder or check the device permissions.'
    CommandRetryAdvice = 'Check the device connection and the error above, then retry. Connection diagnosis is available in Settings.'
    ActionError = 'This action could not finish: {0}'
    ProductCheckFailed = 'LeanADB update check failed. Google tools can still be updated. {0}'
    ToolsCheckFailed = 'Google tools update check failed. Installed tools remain usable. {0}'
    CheckFailedHint = 'The last update check failed. Open Settings > Updates to retry.'
    RemovalPending = 'Uninstall is finishing. Wait for the installation folder to disappear before reinstalling.'
    DevicePage = 'Devices: page {0} of {1}. N: next / P: previous / Esc: cancel'
    FastbootTargetConfirm = 'Fastboot target {0} differs from ADB target {1}. Press Enter to use it, or Esc to cancel.'
    WirelessUsbConfirm = 'Press Enter to return {0} to USB mode, or Esc to cancel.'
    WirelessDiscovery = '[ M ] Find wireless-debugging services on this network'
    WirelessSuggestedIp = 'Detected Wi-Fi address: {0}. Enter: use it, or type another address'
    WirelessSelected = 'Wireless target selected: {0}'
    RecentEmpty = 'There are no LeanADB saved files in this folder yet.'
    RestartMenuHint = 'If LeanADB itself was updated, reopen it to load the new menu.'
}
$script:EnglishMessages = $script:Messages.Clone()
function Set-DisplayLanguage {
    param([ValidateSet('Auto', 'English', 'Korean')][string]$Preference)
    $script:Messages = $script:EnglishMessages.Clone()
    $useKorean = if ($Preference -eq 'Korean') { $true } elseif ($Preference -eq 'English') { $false } else {
        [Globalization.CultureInfo]::CurrentUICulture.Name -match '^ko(?:-|$)'
    }
    if ($useKorean) {
        $localePath = Join-Path $PSScriptRoot 'locales\ko.json'
        if (Test-Path -LiteralPath $localePath -PathType Leaf) {
            try {
                $localized = Get-Content -LiteralPath $localePath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($property in $localized.PSObject.Properties) {
                    $script:Messages[$property.Name] = [string]$property.Value
                }
            }
            catch {
                # English remains available if a localization file is damaged.
            }
        }
    }
}
Set-DisplayLanguage -Preference $Language
$script:RequiredFiles = @(
    'adb.exe',
    'fastboot.exe',
    'AdbWinApi.dll',
    'AdbWinUsbApi.dll',
    'libwinpthread-1.dll',
    'mke2fs.exe',
    'mke2fs.conf',
    'make_f2fs.exe',
    'make_f2fs_casefold.exe',
    'NOTICE.txt',
    'source.properties'
)

trap {
    $message = "[$([DateTime]::Now.ToString('s'))] $($_.Exception.Message)"
    $logPath = $script:ErrorLogPath
    try {
        $details = @(
            $message,
            $_.InvocationInfo.PositionMessage,
            $_.ScriptStackTrace
        ) -join [Environment]::NewLine
        Set-Content -LiteralPath $logPath -Value $details -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        # Error reporting must not hide the original installation error.
    }
    Write-Host ''
    Write-Host "[LeanADB] $($script:Messages.Error): $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[LeanADB] $($script:Messages.ErrorLog): $logPath" -ForegroundColor Yellow
    exit 1
}

if ($env:OS -ne 'Windows_NT' -or [Environment]::OSVersion.Version.Major -lt 10 -or
    -not [Environment]::Is64BitOperatingSystem) {
    throw $script:Messages.UnsupportedWindows
}
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    throw $script:Messages.UnsupportedPowerShell
}

function Write-Info {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host "[LeanADB] $Message"
    }
}

function Format-Message {
    param(
        [string]$Name,
        [object[]]$Values = @()
    )
    return ([string]$script:Messages[$Name]) -f $Values
}

function Get-Sha256Hash {
    param([string]$FilePath)
    $stream = [System.IO.File]::OpenRead($FilePath)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $algorithm.ComputeHash($stream)
        return ([BitConverter]::ToString($bytes)).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Assert-FreeDiskSpace {
    param(
        [string]$Path,
        [long]$RequiredBytes = $script:MinimumInstallFreeBytes
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($fullPath))
    if ($drive.AvailableFreeSpace -lt $RequiredBytes) {
        $requiredMb = [Math]::Ceiling($RequiredBytes / 1MB)
        throw (Format-Message -Name 'InsufficientSpace' -Values @($drive.Name, $requiredMb))
    }
}

function Get-NormalizedInstallPath {
    param([string]$Path)
    $cleanPath = $Path.Trim().Trim('"')
    $expanded = [Environment]::ExpandEnvironmentVariables($cleanPath)
    return [System.IO.Path]::GetFullPath($expanded).TrimEnd('\')
}

function Assert-SafeInstallPath {
    param([string]$Root)
    $forbidden = @(
        ([IO.Path]::GetPathRoot($Root).TrimEnd('\')),
        (Get-NormalizedInstallPath -Path $env:USERPROFILE),
        (Get-NormalizedInstallPath -Path $env:LOCALAPPDATA),
        (Get-NormalizedInstallPath -Path $env:APPDATA),
        (Get-NormalizedInstallPath -Path $env:ProgramData),
        (Get-NormalizedInstallPath -Path (Split-Path -Parent $env:USERPROFILE)),
        (Get-NormalizedInstallPath -Path $env:windir),
        (Get-NormalizedInstallPath -Path ([IO.Path]::GetTempPath())),
        (Get-NormalizedInstallPath -Path (Get-DownloadsFolder)),
        (Get-NormalizedInstallPath -Path ([Environment]::GetFolderPath('Desktop')))
    )
    foreach ($programRoot in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($programRoot) { $forbidden += (Get-NormalizedInstallPath -Path $programRoot) }
    }
    if ($forbidden -contains $Root) {
        throw (Format-Message -Name 'UnsafeInstallPath' -Values @($Root))
    }
}

function Get-StatePath {
    param([string]$Root)
    return Join-Path $Root 'state.json'
}

function Get-StateBackupPath {
    param([string]$Root)
    return Join-Path $Root 'state.json.bak'
}

function Read-StateFile {
    param([string]$Path)
    $state = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.ProductId -ne $script:ProductId) {
        throw 'The state file does not belong to LeanADB.'
    }
    if (-not $state.InstalledVersion -or [string]$state.InstalledVersion -notmatch '^\d+\.\d+(?:\.\d+){0,2}$') {
        throw 'The state file has no installed Platform-Tools version.'
    }
    if ($null -ne $state.PSObject.Properties['StateSchemaVersion'] -and
        ([int]$state.StateSchemaVersion -gt 2 -or [int]$state.StateSchemaVersion -lt 1)) { throw 'Unsupported LeanADB settings version.' }
    $defaults = @{
        PathRegistered = $false; ShortcutRegistered = $false; UninstallRegistered = $false
        ProductSigned = $false; ProductUpdateAvailable = $false; UpdateAvailable = $false
        LastCheckUtc = ''; LastCheckStatus = 'Recovered'; InstalledAtUtc = ''; UpdatedAtUtc = ''
        ETag = ''; LastModified = ''; ContentLength = ''; ZipSha256 = ''
        OutputFolder = ''; LanguagePreference = 'Auto'; UsbBackend = 'Standard'; LeanADBVersion = $script:ProductVersion
        DeviceAliases = @(); RecentDevices = @(); LayoutVersion = 1
    }
    foreach ($name in $defaults.Keys) {
        if ($null -eq $state.PSObject.Properties[$name]) { $state | Add-Member -NotePropertyName $name -NotePropertyValue $defaults[$name] }
    }
    foreach ($name in @('PathRegistered','ShortcutRegistered','UninstallRegistered','ProductSigned','ProductUpdateAvailable','UpdateAvailable')) {
        if ($state.$name -isnot [bool]) { throw "Invalid Boolean setting: $name" }
    }
    if ($state.LanguagePreference -notin @('Auto','English','Korean') -or $state.UsbBackend -notin @('Standard','Legacy')) { throw 'Invalid language or USB setting.' }
    if ($state.OutputFolder -and (-not [IO.Path]::IsPathRooted([string]$state.OutputFolder) -or [string]$state.OutputFolder -match '[\x00-\x1F]')) { throw 'Invalid saved-files location.' }
    $aliases = @()
    foreach ($entry in @($state.DeviceAliases)) {
        if ($null -eq $entry) { continue }
        if ($null -eq $entry.PSObject.Properties['Serial'] -or $null -eq $entry.PSObject.Properties['Alias'] -or
            -not [string]$entry.Serial -or [string]$entry.Serial -match '[\p{C}]' -or
            ([string]$entry.Alias).Length -gt 32 -or [string]$entry.Alias -match '[\p{C}]') { throw 'Invalid device name setting.' }
        $aliases += [pscustomobject]@{ Serial = [string]$entry.Serial; Alias = [string]$entry.Alias }
    }
    $recent = @()
    foreach ($serial in @($state.RecentDevices)) {
        if ($null -eq $serial) { continue }
        if ($serial -isnot [string] -or $serial -match '[\p{C}]') { throw 'Invalid recent-device setting.' }
        if ($serial -and -not @($recent | Where-Object { $_ -ceq $serial }).Count -and $recent.Count -lt 5) { $recent += $serial }
    }
    $state | Add-Member -NotePropertyName DeviceAliases -NotePropertyValue $aliases -Force
    $state | Add-Member -NotePropertyName RecentDevices -NotePropertyValue $recent -Force
    if ($null -eq $state.PSObject.Properties['PackageComparisonKnown']) {
        $state | Add-Member -NotePropertyName PackageComparisonKnown -NotePropertyValue ([bool](($state.ETag -or $state.LastModified) -and $state.LastCheckStatus -ne 'Offline'))
    }
    if ($state.PackageComparisonKnown -isnot [bool]) { throw 'Invalid package comparison setting.' }
    $state | Add-Member -NotePropertyName StateSchemaVersion -NotePropertyValue 2 -Force
    return $state
}

function Read-State {
    param([string]$Root)
    $path = Get-StatePath -Root $Root
    $backupPath = Get-StateBackupPath -Root $Root
    $script:StateRecoveredFromBackup = $false
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -and
        -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        return $null
    }

    $primaryError = $null
    try {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return Read-StateFile -Path $path
        }
    }
    catch {
        $primaryError = $_.Exception.Message
    }

    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        try {
            $state = Read-StateFile -Path $backupPath
            $script:StateRecoveredFromBackup = $true
            return $state
        }
        catch {
            $backupError = $_.Exception.Message
            if ($primaryError) {
                throw "Cannot read LeanADB state or backup. Primary: $primaryError Backup: $backupError"
            }
            throw "Cannot read LeanADB state backup: $backupError"
        }
    }

    if ($primaryError) {
        throw "Cannot read LeanADB state: $primaryError"
    }
    return $null
}

function Write-State {
    param(
        [string]$Root,
        [object]$State
    )
    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -ItemType Directory -Path $Root | Out-Null
    }
    $path = Get-StatePath -Root $Root
    $backupPath = Get-StateBackupPath -Root $Root
    $tempPath = "$path.tmp"
    $backupTempPath = "$backupPath.tmp"
    try {
        $State | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $tempPath -Encoding UTF8
        [void](Read-StateFile -Path $tempPath)
        Move-Item -LiteralPath $tempPath -Destination $path -Force
        Copy-Item -LiteralPath $path -Destination $backupTempPath -Force
        [void](Read-StateFile -Path $backupTempPath)
        Move-Item -LiteralPath $backupTempPath -Destination $backupPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) { Remove-Item -LiteralPath $tempPath -Force }
        if (Test-Path -LiteralPath $backupTempPath -PathType Leaf) { Remove-Item -LiteralPath $backupTempPath -Force }
    }
}

function Get-HeaderText {
    param(
        [object]$Headers,
        [string]$Name
    )
    $value = $Headers[$Name]
    if ($null -eq $value) {
        return ''
    }
    return (($value | ForEach-Object { [string]$_ }) -join ',')
}

function Get-RemoteMetadata {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri $script:SourceUrl -Method Head -UseBasicParsing -TimeoutSec $script:MetadataTimeoutSeconds
    return [pscustomobject]@{
        ETag          = Get-HeaderText -Headers $response.Headers -Name 'ETag'
        LastModified  = Get-HeaderText -Headers $response.Headers -Name 'Last-Modified'
        ContentLength = Get-HeaderText -Headers $response.Headers -Name 'Content-Length'
    }
}

function Get-ProductManifest {
    param([string]$ManifestUrl)
    if (-not $ManifestUrl) {
        return $null
    }
    $uri = [Uri]$ManifestUrl
    if ($uri.IsFile) {
        $manifest = Get-Content -LiteralPath $uri.LocalPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        if ($uri.Scheme -ne 'https') {
            throw 'The LeanADB update manifest must use HTTPS.'
        }
        $response = Invoke-WebRequest -Uri $uri.AbsoluteUri -UseBasicParsing -TimeoutSec 10
        $manifestText = if ($response.Content -is [byte[]]) {
            [Text.Encoding]::UTF8.GetString($response.Content)
        }
        else {
            [string]$response.Content
        }
        if ($manifestText.Length -gt 1MB) { throw $script:Messages.InvalidManifest }
        $manifest = $manifestText.TrimStart([char]0xFEFF) | ConvertFrom-Json
    }
    if ($null -eq $manifest -or $manifest.ProductId -ne $script:ProductId -or
        -not $manifest.Version -or -not $manifest.Package -or
        -not $manifest.Package.FileName -or -not $manifest.Package.Sha256 -or
        -not $manifest.Files) {
        throw $script:Messages.InvalidManifest
    }
    if (($null -ne $manifest.PSObject.Properties['SchemaVersion'] -and $manifest.SchemaVersion -ne 1) -or
        [string]$manifest.Package.Sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw $script:Messages.InvalidManifest }
    [void](Convert-SemVerParts -Version ([string]$manifest.Version))
    foreach ($entry in @($manifest.Files)) {
        if ($null -eq $entry -or $null -eq $entry.PSObject.Properties['Path'] -or $null -eq $entry.PSObject.Properties['Sha256'] -or
            [string]$entry.Sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw $script:Messages.InvalidManifest }
    }
    return $manifest
}

function Convert-SemVerParts {
    param([string]$Version)
    if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$') {
        throw "Invalid semantic version: $Version"
    }
    return [pscustomobject]@{
        Major = [int]$Matches[1]
        Minor = [int]$Matches[2]
        Patch = [int]$Matches[3]
        Pre = [string]$Matches[4]
    }
}

function Test-NewerProductVersion {
    param(
        [string]$Current,
        [string]$Candidate
    )
    $left = Convert-SemVerParts -Version $Current
    $right = Convert-SemVerParts -Version $Candidate
    foreach ($name in @('Major', 'Minor', 'Patch')) {
        if ($right.$name -gt $left.$name) { return $true }
        if ($right.$name -lt $left.$name) { return $false }
    }
    if (-not $right.Pre -and $left.Pre) { return $true }
    if ($right.Pre -and -not $left.Pre) { return $false }
    if ($right.Pre -eq $left.Pre) { return $false }
    $leftParts = @($left.Pre -split '\.')
    $rightParts = @($right.Pre -split '\.')
    $count = [Math]::Max($leftParts.Count, $rightParts.Count)
    for ($index = 0; $index -lt $count; $index++) {
        if ($index -ge $leftParts.Count) { return $true }
        if ($index -ge $rightParts.Count) { return $false }
        $leftNumber = 0
        $rightNumber = 0
        $leftNumeric = [int]::TryParse($leftParts[$index], [ref]$leftNumber)
        $rightNumeric = [int]::TryParse($rightParts[$index], [ref]$rightNumber)
        if ($leftNumeric -and $rightNumeric) {
            if ($rightNumber -gt $leftNumber) { return $true }
            if ($rightNumber -lt $leftNumber) { return $false }
        }
        elseif ($leftNumeric -ne $rightNumeric) {
            return -not $rightNumeric
        }
        else {
            $comparison = [string]::Compare($rightParts[$index], $leftParts[$index], [StringComparison]::Ordinal)
            if ($comparison -gt 0) { return $true }
            if ($comparison -lt 0) { return $false }
        }
    }
    return $false
}

function Resolve-ProductPackageUri {
    param(
        [string]$ManifestUrl,
        [object]$Manifest
    )
    if ($null -ne $Manifest.Package.PSObject.Properties['Url'] -and $Manifest.Package.Url) {
        return [Uri][string]$Manifest.Package.Url
    }
    return [Uri]::new([Uri]$ManifestUrl, [string]$Manifest.Package.FileName)
}

function Save-UriToFile {
    param(
        [Uri]$Uri,
        [string]$Destination
    )
    if ($Uri.IsFile) {
        Copy-Item -LiteralPath $Uri.LocalPath -Destination $Destination
    }
    else {
        if ($Uri.Scheme -ne 'https') {
            throw 'LeanADB updates must use HTTPS.'
        }
        Invoke-WebRequest -Uri $Uri.AbsoluteUri -OutFile $Destination -UseBasicParsing -TimeoutSec $script:DownloadTimeoutSeconds
    }
}

function New-InstallSnapshot {
    param([string]$Root, [string]$BackupRoot, [switch]$Integration)
    $paths = @('LeanADB.ps1','VERSION','UPDATE_URL','locales\ko.json','state.json','state.json.bak',
        'README.md','CHANGELOG.md','LICENSE','Open LeanADB.cmd','Open LeanADB Terminal.cmd',
        'Update LeanADB.cmd','Repair LeanADB.cmd','Uninstall LeanADB.cmd','Drop files on LeanADB.cmd','LeanADB-Drop.ps1','Open LeanADB Here.cmd')
    $files = @()
    foreach ($relative in $paths) {
        $target = Join-Path $Root $relative
        $exists = Test-Path -LiteralPath $target -PathType Leaf
        $backup = Join-Path $BackupRoot $relative
        if ($exists) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $backup -Force
        }
        $files += [pscustomobject]@{ Path = $relative; Exists = $exists; Backup = $backup }
    }
    $snapshot = [pscustomobject]@{ Files = $files; Integration = [bool]$Integration; UserPath = ''; ShortcutBytes = $null; Registry = @(); HadRegistry = $false }
    if ($Integration) {
        $snapshot.UserPath = [Environment]::GetEnvironmentVariable('Path','User')
        $shortcut = Get-ShortcutPath
        if (Test-Path -LiteralPath $shortcut -PathType Leaf) { $snapshot.ShortcutBytes = [IO.File]::ReadAllBytes($shortcut) }
        $keyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\LeanADB'
        if (Test-Path -LiteralPath $keyPath) {
            $snapshot.HadRegistry = $true
            $key = Get-Item -LiteralPath $keyPath
            foreach ($name in $key.GetValueNames()) { $snapshot.Registry += [pscustomobject]@{ Name = $name; Value = $key.GetValue($name); Kind = $key.GetValueKind($name).ToString() } }
        }
    }
    return $snapshot
}

function Restore-InstallSnapshot {
    param([string]$Root, [object]$Snapshot)
    $failures = @()
    foreach ($entry in $Snapshot.Files) {
        try {
            $target = Join-Path $Root $entry.Path
            if ($entry.Exists) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
                Copy-Item -LiteralPath $entry.Backup -Destination $target -Force
            }
            elseif (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
        }
        catch { $failures += $_.Exception.Message }
    }
    if ($Snapshot.Integration) {
        try {
            if ([Environment]::GetEnvironmentVariable('Path','User') -ne $Snapshot.UserPath) { [Environment]::SetEnvironmentVariable('Path',$Snapshot.UserPath,'User') }
            $shortcut = Get-ShortcutPath
            if ($null -ne $Snapshot.ShortcutBytes) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $shortcut) -Force | Out-Null
                [IO.File]::WriteAllBytes($shortcut, $Snapshot.ShortcutBytes)
            }
            elseif (Test-Path -LiteralPath $shortcut -PathType Leaf) { Set-StartMenuShortcut -Root $Root -Present $false }
            $keyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\LeanADB'
            if ($Snapshot.HadRegistry) {
                New-Item -Path $keyPath -Force | Out-Null
                foreach ($entry in $Snapshot.Registry) { New-ItemProperty -Path $keyPath -Name $entry.Name -Value $entry.Value -PropertyType $entry.Kind -Force | Out-Null }
            }
            else { Set-UninstallRegistration -Root $Root -Present $false }
        }
        catch { $failures += $_.Exception.Message }
    }
    if ($failures.Count) { throw ('Rollback incomplete: ' + ($failures -join '; ')) }
}

function Assert-ProductArchive {
    param([string]$ZipPath)
    if ((Get-Item -LiteralPath $ZipPath).Length -gt 16MB) { throw 'LeanADB update archive exceeds 16 MB.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        if ($zip.Entries.Count -gt 64) { throw 'Too many LeanADB update entries.' }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        [long]$size = 0
        foreach ($entry in $zip.Entries) {
            # Windows PowerShell's Compress-Archive uses backslashes. Validate
            # canonical separators before checking traversal and duplicates.
            $name = ([string]$entry.FullName).Replace('\','/')
            if ($name -notmatch '^LeanADB/' -or $name -match '[\x00-\x1F\x7F:]|(^|/)\.\.?(/|$)|[. ](/|$)' -or -not $seen.Add($name)) { throw "Unsafe LeanADB update entry: $name" }
            $size += $entry.Length
            if ($size -gt 32MB) { throw 'LeanADB update expands beyond 32 MB.' }
        }
        Assert-FreeDiskSpace -Path (Split-Path -Parent $ZipPath) -RequiredBytes ($size + 16MB)
    }
    finally { $zip.Dispose() }
}

function Install-ProductUpdate {
    param(
        [string]$Root,
        [string]$ManifestUrl,
        [object]$Manifest
    )
    $allowedPaths = @(
        'LeanADB.ps1', 'VERSION', 'README.md', 'CHANGELOG.md', 'LICENSE',
        'locales\ko.json'
    )
    $manifestPaths = @($Manifest.Files | ForEach-Object { ([string]$_.Path).Replace('/', '\') })
    if (@($manifestPaths | Select-Object -Unique).Count -ne $manifestPaths.Count) { throw 'Duplicate LeanADB manifest paths.' }
    foreach ($required in @('LeanADB.ps1', 'VERSION', 'locales\ko.json')) {
        if ($required -notin $manifestPaths) {
            throw "$($script:Messages.InvalidManifest) Missing $required"
        }
    }
    foreach ($relative in $manifestPaths) {
        if ($relative -notin $allowedPaths -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains('..')) {
            throw "$($script:Messages.InvalidManifest) Unsafe path: $relative"
        }
    }

    Assert-FreeDiskSpace -Path ([IO.Path]::GetTempPath()) -RequiredBytes 16MB
    Assert-FreeDiskSpace -Path $Root -RequiredBytes 16MB
    $mutex = Enter-UpdateLock -Root $Root
    $workRoot = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-product-' + [guid]::NewGuid().ToString('N'))
    $applied = @()
    $statePath = Get-StatePath -Root $Root
    $stateBackupPath = Get-StateBackupPath -Root $Root
    $originalStateBytes = $null
    $originalBackupBytes = $null
    $stateSnapshotCaptured = $false
    $snapshot = $null
    $preserveBackup = $false
    $committed = $false
    try {
        $originalStateBytes = if (Test-Path -LiteralPath $statePath -PathType Leaf) { [IO.File]::ReadAllBytes($statePath) } else { $null }
        $originalBackupBytes = if (Test-Path -LiteralPath $stateBackupPath -PathType Leaf) { [IO.File]::ReadAllBytes($stateBackupPath) } else { $null }
        $stateSnapshotCaptured = $true
        New-Item -ItemType Directory -Path $workRoot | Out-Null
        $installedState = Read-State -Root $Root
        if ($null -eq $installedState) { throw (Format-Message -Name 'NotInstalled' -Values @($Root)) }
        if ($null -ne $installedState.PSObject.Properties['PendingRemovalId'] -and $installedState.PendingRemovalId) { throw $script:Messages.RemovalPending }
        $snapshot = New-InstallSnapshot -Root $Root -BackupRoot (Join-Path $workRoot 'snapshot') -Integration:([bool]$installedState.PathRegistered -or [bool]$installedState.ShortcutRegistered)
        $archive = Join-Path $workRoot 'LeanADB.zip'
        Save-UriToFile -Uri (Resolve-ProductPackageUri -ManifestUrl $ManifestUrl -Manifest $Manifest) -Destination $archive
        $archiveHash = Get-Sha256Hash -FilePath $archive
        if ($archiveHash -ine [string]$Manifest.Package.Sha256) {
            throw 'LeanADB update package SHA-256 mismatch.'
        }
        $extractRoot = Join-Path $workRoot 'extract'
        Assert-ProductArchive -ZipPath $archive
        Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot -Force
        $packageRoot = Join-Path $extractRoot 'LeanADB'
        if ((Get-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Raw -Encoding UTF8).Trim() -cne [string]$Manifest.Version) { throw 'LeanADB package version does not match its manifest.' }
        $installedState = Read-State -Root $Root
        $requireSignedUpdate = $null -ne $installedState.PSObject.Properties['ProductSigned'] -and [bool]$installedState.ProductSigned
        if ($requireSignedUpdate) {
            if ($null -eq $Manifest.PSObject.Properties['AuthenticodeSigned'] -or -not [bool]$Manifest.AuthenticodeSigned) {
                throw 'This installation requires an Authenticode-signed LeanADB update.'
            }
            $productSignature = Get-AuthenticodeSignature -LiteralPath (Join-Path $packageRoot 'LeanADB.ps1')
            if ($productSignature.Status -ne 'Valid') {
                throw "LeanADB update signature is invalid: $($productSignature.Status)"
            }
            if ($null -ne $installedState.PSObject.Properties['ProductSignerSubject'] -and
                $installedState.ProductSignerSubject -and
                $productSignature.SignerCertificate.Subject -ne [string]$installedState.ProductSignerSubject) {
                throw 'LeanADB update signer does not match the installed publisher.'
            }
        }
        $backupRoot = Join-Path $workRoot 'backup'
        New-Item -ItemType Directory -Path $backupRoot | Out-Null
        foreach ($entry in $Manifest.Files) {
            $relative = ([string]$entry.Path).Replace('/', '\')
            $source = Join-Path $packageRoot $relative
            if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Get-Sha256Hash -FilePath $source) -ine [string]$entry.Sha256) { throw "LeanADB update file verification failed: $relative" }
        }

        foreach ($entry in $Manifest.Files) {
            $relative = ([string]$entry.Path).Replace('/', '\')
            $source = Join-Path $packageRoot $relative
            if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
                (Get-Sha256Hash -FilePath $source) -ine [string]$entry.Sha256) {
                throw "LeanADB update file verification failed: $relative"
            }
            $target = Join-Path $Root $relative
            $targetDirectory = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $targetDirectory)) {
                New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
            }
            $backup = Join-Path $backupRoot $relative
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                $backupDirectory = Split-Path -Parent $backup
                New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
                Copy-Item -LiteralPath $target -Destination $backup
            }
            $temporaryTarget = "$target.new"
            Copy-Item -LiteralPath $source -Destination $temporaryTarget -Force
            Move-Item -LiteralPath $temporaryTarget -Destination $target -Force
            $applied += $relative
        }

        $state = Read-State -Root $Root
        $state | Add-Member -NotePropertyName LeanADBVersion -NotePropertyValue ([string]$Manifest.Version) -Force
        $state | Add-Member -NotePropertyName ProductManifestUrl -NotePropertyValue $ManifestUrl -Force
        $state | Add-Member -NotePropertyName ProductUpdateAvailable -NotePropertyValue $false -Force
        $updatedSignature = Get-AuthenticodeSignature -LiteralPath (Join-Path $Root 'LeanADB.ps1')
        $state | Add-Member -NotePropertyName ProductSigned -NotePropertyValue ($updatedSignature.Status -eq 'Valid') -Force
        $updatedSigner = if ($updatedSignature.Status -eq 'Valid') { [string]$updatedSignature.SignerCertificate.Subject } else { '' }
        $state | Add-Member -NotePropertyName ProductSignerSubject -NotePropertyValue $updatedSigner -Force
        Write-State -Root $Root -State $state
        Write-Launchers -Root $Root
        if ([bool]$state.ShortcutRegistered) { Set-StartMenuShortcut -Root $Root -Present $true }
        if ([bool]$state.PathRegistered -or [bool]$state.ShortcutRegistered) {
            Set-UninstallRegistration -Root $Root -Present $true -DisplayVersion ([string]$Manifest.Version)
        }
        $committed = $true
    }
    catch {
        $originalError = $_
        if ($null -ne $snapshot) {
            try { Restore-InstallSnapshot -Root $Root -Snapshot $snapshot }
            catch { $preserveBackup = $true; throw "Update failed: $($originalError.Exception.Message) $($_.Exception.Message) Backup: $workRoot" }
            throw $originalError
        }
        $rollbackPaths = @($applied)
        [array]::Reverse($rollbackPaths)
        foreach ($relative in $rollbackPaths) {
            $target = Join-Path $Root $relative
            $backup = Join-Path (Join-Path $workRoot 'backup') $relative
            if (Test-Path -LiteralPath $backup -PathType Leaf) {
                Copy-Item -LiteralPath $backup -Destination $target -Force
            }
            elseif (Test-Path -LiteralPath $target -PathType Leaf) {
                Remove-Item -LiteralPath $target -Force
            }
        }
        if ($stateSnapshotCaptured) {
            if ($null -ne $originalStateBytes) { [IO.File]::WriteAllBytes($statePath, $originalStateBytes) }
            elseif (Test-Path -LiteralPath $statePath -PathType Leaf) { Remove-Item -LiteralPath $statePath -Force }
            if ($null -ne $originalBackupBytes) { [IO.File]::WriteAllBytes($stateBackupPath, $originalBackupBytes) }
            elseif (Test-Path -LiteralPath $stateBackupPath -PathType Leaf) { Remove-Item -LiteralPath $stateBackupPath -Force }
        }
        throw
    }
    finally {
        try {
            if (-not $preserveBackup -and (Test-Path -LiteralPath $workRoot)) {
                try { Remove-Item -LiteralPath $workRoot -Recurse -Force }
                catch { if (-not $committed) { throw }; Write-Warning "Update succeeded; temporary files remain at $workRoot" }
            }
        }
        finally {
            Exit-UpdateLock -Mutex $mutex
        }
    }
}

function Confirm-SdkLicense {
    if ($AcceptSdkLicense) {
        return
    }

    if (-not [Environment]::UserInteractive) {
        throw 'SDK license acceptance is required. Run interactively or pass -AcceptSdkLicense after reviewing the license.'
    }

    Clear-Host
    Write-Host ''
    Write-Host '=======================================================================' -ForegroundColor Cyan
    Write-Host '                         LEANADB INSTALLER' -ForegroundColor Cyan
    Write-Host '                          by leodroid99' -ForegroundColor DarkCyan
    Write-Host '=======================================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host " $($script:Messages.ProductDescription)"
    Write-Host " License: $($script:LicenseUrl)"
    Write-Host " $($script:Messages.GoogleLicense)"
    Write-Host " $($script:Messages.ScriptLicense)"
    Write-Host ''
    Write-Host "     $($script:Messages.AcceptInstall)" -ForegroundColor Green
    Write-Host ''
    Write-Host "     $($script:Messages.Cancel)" -ForegroundColor Yellow
    Write-Host ''
    Write-Host '=======================================================================' -ForegroundColor Cyan

    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Enter) {
            Write-Host ''
            Write-Info $script:Messages.LicenseAccepted
            return
        }
        if ($key.Key -eq [ConsoleKey]::Escape) {
            Write-Host ''
            Write-Info $script:Messages.InstallationCancelled
            exit 20
        }
    }
}

function Get-DownloadsFolder {
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.NameSpace('shell:Downloads')
        if ($null -ne $folder -and $null -ne $folder.Self -and $folder.Self.Path) {
            return [string]$folder.Self.Path
        }
    }
    catch {
        # Fall back to the conventional location below.
    }
    return Join-Path $env:USERPROFILE 'Downloads'
}

function Get-PortableFilesPath {
    param([string]$Root)
    $parent = Split-Path -Parent $Root
    $leaf = Split-Path -Leaf $Root
    return Join-Path $parent ($leaf + '-Files')
}

function Get-OutputFolder {
    param([string]$Root, [object]$State)
    if ($null -ne $State -and $null -ne $State.PSObject.Properties['OutputFolder'] -and $State.OutputFolder) {
        return [string]$State.OutputFolder
    }
    if ($null -ne $State -and -not [bool]$State.PathRegistered -and -not [bool]$State.ShortcutRegistered) {
        return Get-PortableFilesPath -Root $Root
    }
    return Get-DownloadsFolder
}

function Get-ActiveOutputFolder {
    $folder = if ($script:ActiveOutputFolder) { $script:ActiveOutputFolder } else { Get-DownloadsFolder }
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        try { New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null }
        catch { throw (Format-Message -Name 'OutputFolderUnavailable' -Values @($folder)) }
    }
    return $folder
}

function Get-PortableInstallPath {
    $installerParent = Split-Path -Parent $PSScriptRoot
    return Join-Path $installerParent 'LeanADB-Portable'
}

function Select-InstallLocation {
    param([string]$ExistingRoot)
    $downloadsRoot = Join-Path (Get-DownloadsFolder) 'LeanADB'
    $desktopRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) 'LeanADB'
    $standardRoot = Join-Path $env:LOCALAPPDATA 'LeanADB'
    $portableRoot = Get-PortableInstallPath

    Clear-Host
    Write-Host ''
    Write-Host '=======================================================================' -ForegroundColor Cyan
    Write-Host ("                    " + $script:Messages.ChooseLocation) -ForegroundColor Cyan
    Write-Host '=======================================================================' -ForegroundColor Cyan
    Write-Host ''
    if ($ExistingRoot) {
        Write-Host " $($script:Messages.ExistingOption)" -ForegroundColor Green
        Write-Host "     $ExistingRoot"
        Write-Host ''
    }
    $standardLabel = if ($ExistingRoot) { $script:Messages.StandardOtherOption } else { $script:Messages.StandardOption }
    Write-Host " $standardLabel" -ForegroundColor Green
    Write-Host "     $standardRoot"
    Write-Host ''
    Write-Host " $($script:Messages.DownloadsOption)"
    Write-Host "     $downloadsRoot"
    Write-Host ''
    Write-Host " $($script:Messages.DesktopOption)"
    Write-Host "     $desktopRoot"
    Write-Host ''
    Write-Host " $($script:Messages.PortableOption)"
    Write-Host "     $portableRoot"
    Write-Host ''
    Write-Host " $($script:Messages.CustomOption)"
    Write-Host ''
    Write-Host " $($script:Messages.LocationHelp)" -ForegroundColor Yellow

    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Enter' { if ($ExistingRoot) { return $ExistingRoot }; return $standardRoot }
            'D' { return $downloadsRoot }
            'B' { return $desktopRoot }
            'S' { return $standardRoot }
            'P' { $script:SelectedPortableMode = $true; return $portableRoot }
            'C' {
                Add-Type -AssemblyName System.Windows.Forms
                $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                try {
                    $dialog.Description = $script:Messages.ChooseLocation
                    $dialog.ShowNewFolderButton = $true
                    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $selectedPath = [string]$dialog.SelectedPath
                        if ([IO.Path]::GetFileName($selectedPath.TrimEnd('\')) -ieq 'LeanADB') {
                            return $selectedPath
                        }
                        return (Join-Path $selectedPath 'LeanADB')
                    }
                }
                finally {
                    $dialog.Dispose()
                }
            }
            'Escape' {
                Write-Host ''
                Write-Info $script:Messages.InstallationCancelled
                exit 20
            }
        }
    }
}

function Find-KnownInstallation {
    $roots = @(
        (Get-PortableInstallPath),
        (Join-Path $env:LOCALAPPDATA 'LeanADB'),
        (Join-Path (Get-DownloadsFolder) 'LeanADB'),
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'LeanADB')
    ) | Select-Object -Unique
    foreach ($root in $roots) {
        try {
            if ($null -ne (Read-State -Root $root)) {
                return [System.IO.Path]::GetFullPath($root).TrimEnd('\')
            }
        }
        catch {
            # A damaged candidate is handled if the user explicitly selects that folder.
        }
    }
    return $null
}

function Show-InstallCompletion {
    param([string]$Root)
    $binPath = Join-Path $Root 'bin'
    Clear-Host
    Write-Host ''
    Write-Host '=======================================================================' -ForegroundColor Cyan
    Write-Host ("                       " + $script:Messages.InstallCompleted) -ForegroundColor Green
    Write-Host '                          by leodroid99' -ForegroundColor DarkCyan
    Write-Host '=======================================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host (Format-Message -Name 'InstallationFolder' -Values @($Root))
    Write-Host $script:Messages.AdbFolder
    Write-Host "  $binPath"
    Write-Host ''
    Write-Host $script:Messages.ScriptLicense
    Write-Host $script:Messages.GoogleLicense
    Write-Host ''
    $installedState = Read-State -Root $Root
    Write-Host (Format-Message -Name 'SavedFilesFolder' -Values @((Get-OutputFolder -Root $Root -State $installedState)))
    if ($null -ne $installedState -and -not [bool]$installedState.PathRegistered -and -not [bool]$installedState.ShortcutRegistered) {
        Write-Host $script:Messages.PortableInstallHint
    }
    else {
        Write-Host $script:Messages.StartMenu
    }
    Write-Host $script:Messages.DownloadsHint
    Write-Host ''
    Write-Host $script:Messages.OpeningFolder -ForegroundColor Green
    Start-Process -FilePath 'explorer.exe' -ArgumentList @('"' + $binPath + '"')
    Write-Host ''
    Write-Host $script:Messages.CloseKey
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Enter) {
            Start-Process -FilePath (Join-Path $Root 'Open LeanADB.cmd')
            return
        }
        if ($key.Key -eq [ConsoleKey]::Escape) {
            return
        }
    }
}

function Wait-ForMenuKey {
    Write-Host ''
    Write-Host $script:Messages.PressAnyKey -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

function Select-LocalFile {
    param(
        [string]$Title,
        [string]$Filter,
        [switch]$Multiple
    )
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = $Title
        $dialog.Filter = $Filter
        $dialog.CheckFileExists = $true
        $dialog.Multiselect = [bool]$Multiple
        $downloads = Get-DownloadsFolder
        if (Test-Path -LiteralPath $downloads -PathType Container) {
            $dialog.InitialDirectory = $downloads
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            if ($Multiple) {
                return @($dialog.FileNames)
            }
            return [string]$dialog.FileName
        }
        return $null
    }
    finally {
        $dialog.Dispose()
    }
}

function ConvertTo-NativeArgument {
    param([string]$Value)
    $escaped = [regex]::Replace($Value, '(\\*)"', { param($match) $match.Groups[1].Value + $match.Groups[1].Value + '\"' })
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-ToolProcess {
    param([string]$Executable, [string[]]$Arguments, [int]$TimeoutSeconds = 300, [string]$OutputFile = '', [switch]$QuietProgress)
    $command = Get-Command $Executable -ErrorAction Stop
    if ($command.CommandType -eq 'Function') {
        $previous = $ErrorActionPreference
        try { $ErrorActionPreference = 'Continue'; $output = @(& $Executable @Arguments 2>&1); $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $previous }
        return [pscustomobject]@{ ExitCode = $code; Output = ($output | Out-String).Trim(); Cancelled = $false; TimedOut = $false }
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $command.Source
    $info.Arguments = (@($Arguments | ForEach-Object { ConvertTo-NativeArgument -Value $_ }) -join ' ')
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $stream = $null; $cancelled = $false; $timedOut = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $shown = -1
    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    try {
        if ($OutputFile) { $stream = [IO.File]::Open($OutputFile, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read) }
        [void]$process.Start()
        $stdout = if ($null -ne $stream) { $process.StandardOutput.BaseStream.CopyToAsync($stream) } else { $process.StandardOutput.ReadToEndAsync() }
        $stderr = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(100)) {
            if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $timedOut = $true; break }
            if ($interactive -and [Console]::KeyAvailable) {
                if ([Console]::ReadKey($true).Key -eq [ConsoleKey]::Escape) { $cancelled = $true; break }
            }
            $elapsed = [int]$watch.Elapsed.TotalSeconds
            if ($interactive -and -not $QuietProgress -and $elapsed -gt $shown) {
                Write-Host ("`r" + (Format-Message -Name 'OperationProgress' -Values @($elapsed))) -NoNewline -ForegroundColor DarkGray
                $shown = $elapsed
            }
        }
        if ($cancelled -or $timedOut) { $process.Kill(); [void]$process.WaitForExit(5000) }
        # A descendant can keep inherited pipe handles open after the client
        # exits. Bound stream draining too, not just the client process itself.
        $drainWatch = [Diagnostics.Stopwatch]::StartNew()
        while ((-not $stdout.IsCompleted -or -not $stderr.IsCompleted) -and $drainWatch.Elapsed.TotalSeconds -lt 2) { [Threading.Thread]::Sleep(25) }
        $drainWatch.Stop()
        if (-not $stdout.IsCompleted -or -not $stderr.IsCompleted) {
            $timedOut = $true
            $process.StandardOutput.Close(); $process.StandardError.Close()
            $global:LASTEXITCODE = if ($cancelled) { 130 } else { 124 }
            return [pscustomobject]@{ ExitCode = $global:LASTEXITCODE; Output = ''; Cancelled = $cancelled; TimedOut = $timedOut }
        }
        $stdout.GetAwaiter().GetResult() | Out-Null
        $errorText = $stderr.GetAwaiter().GetResult()
        $text = if ($null -ne $stream) { $errorText } else { ([string]$stdout.Result + [Environment]::NewLine + $errorText).Trim() }
        $code = if ($cancelled) { 130 } elseif ($timedOut) { 124 } else { $process.ExitCode }
        if ($code -eq 0 -and $Arguments.Count -gt 0 -and $Arguments[0] -in @('connect','pair') -and $text -match '(?im)(?:^|adb: )(?:failed|cannot|unable|error)|failed to connect') { $code = 1 }
        $global:LASTEXITCODE = $code
        return [pscustomobject]@{ ExitCode = $code; Output = $text; Cancelled = $cancelled; TimedOut = $timedOut }
    }
    finally {
        if ($shown -ge 0) { Write-Host '' }
        # Do not leave a client running after a stream or console error.
        try { if ($process.Id -and -not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) } } catch { }
        if ($null -ne $stream) { $stream.Dispose() }
        $process.Dispose(); $watch.Stop()
    }
}

function Get-CommandAdvice {
    param([string]$Output, [int]$ExitCode)
    if ($ExitCode -eq 130) { return $script:Messages.OperationCancelled }
    if ($ExitCode -eq 124) { return $script:Messages.OperationTimedOut }
    switch -Regex ($Output) {
        'INSTALL_FAILED_UPDATE_INCOMPATIBLE|INSTALL_FAILED_SHARED_USER_INCOMPATIBLE' { return $script:Messages.ApkSignatureAdvice }
        'INSTALL_FAILED_INSUFFICIENT_STORAGE|No space left' { return $script:Messages.StorageAdvice }
        'INSTALL_FAILED_NO_MATCHING_ABIS' { return $script:Messages.ApkAbiAdvice }
        'INSTALL_FAILED_VERSION_DOWNGRADE' { return $script:Messages.ApkDowngradeAdvice }
        'INSTALL_FAILED_MISSING_SPLIT|INSTALL_FAILED_INVALID_APK' { return $script:Messages.ApkSplitAdvice }
        'unauthorized' { return $script:Messages.DiagnoseUnauthorized }
        'offline|device .*not found|no devices' { return $script:Messages.DiagnoseOffline }
        'Permission denied' { return $script:Messages.PermissionAdvice }
        default { return $script:Messages.CommandRetryAdvice }
    }
}

function Save-OperationReport {
    param([string]$Kind, [string]$Serial, [object[]]$Results)
    $folder = Get-ActiveOutputFolder
    $path = Join-Path $folder ('LeanADB-Result-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.txt')
    [pscustomobject]@{ Operation = $Kind; Device = $Serial; TimeUtc = [DateTime]::UtcNow.ToString('o'); Results = @($Results) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
    $script:LastSavedPath = $path
    Write-Host (Format-Message -Name 'ResultSaved' -Values @($path)) -ForegroundColor DarkGray
    return $path
}

function Invoke-MenuCommand {
    param(
        [string]$Executable,
        [string[]]$Arguments
    )
    Write-Host ''
    $result = Invoke-ToolProcess -Executable $Executable -Arguments $Arguments
    if ($result.Output) { Write-Host $result.Output }
    $commandExitCode = $result.ExitCode
    Write-Host ''
    if ($commandExitCode -eq 0) {
        Write-Host $script:Messages.CommandSucceeded -ForegroundColor Green
    }
    else {
        Write-Host (Format-Message -Name 'CommandFailed' -Values @($commandExitCode)) -ForegroundColor Red
        Write-Host (Get-CommandAdvice -Output $result.Output -ExitCode $commandExitCode) -ForegroundColor Yellow
    }
    Wait-ForMenuKey
    return $result
}

function Send-FilesToDevice {
    param([string]$AdbPath, [string]$Serial, [string[]]$Paths)
    $success = 0
    $failed = 0
    $results = @(); $cancelled = $false
        for ($index = 0; $index -lt $Paths.Count; $index++) {
            $path = $Paths[$index]
            if ($cancelled -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Write-Host (Format-Message -Name 'BatchSkipped' -Values @($path)) -ForegroundColor Yellow
                $failed++
                $results += [pscustomobject]@{ Path = $path; Success = $false; ExitCode = 130; Details = 'Not attempted' }
                continue
            }
            $remoteName = [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '-' + [IO.Path]::GetFileName($path)
            $remotePath = '/sdcard/Download/' + $remoteName
            Write-Host (Format-Message -Name 'SendBatchItem' -Values @(($index + 1), $Paths.Count, $path))
            $result = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'push',$path,$remotePath)
            if ($result.Output) { Write-Host $result.Output }
            $ok = $result.ExitCode -eq 0
            if ($ok) { $success++ } else { $failed++; Write-Host (Get-CommandAdvice -Output $result.Output -ExitCode $result.ExitCode) -ForegroundColor Yellow }
            $results += [pscustomobject]@{ Path = $path; RemotePath = $remotePath; Success = $ok; ExitCode = $result.ExitCode; Details = $result.Output }
            $cancelled = $result.Cancelled
        }
    $script:LastBatch = [pscustomobject]@{ Kind = 'Send'; Serial = $Serial; Results = $results }
    if ($failed) { $script:AnyBatchFailure = $true }
    Write-Host (Format-Message -Name 'SendBatchSummary' -Values @($success, $failed)) -ForegroundColor $(if ($failed) { 'Yellow' } else { 'Green' })
    try { [void](Save-OperationReport -Kind 'Send' -Serial $Serial -Results $results) } catch { Write-Warning $_.Exception.Message }
    Wait-ForMenuKey
}

function Install-ApkBatch {
    param([string]$AdbPath, [string]$Serial, [string[]]$Paths)
    $success = 0
    $failed = 0
    $results = @(); $cancelled = $false
        for ($index = 0; $index -lt $Paths.Count; $index++) {
            $path = $Paths[$index]
            if ($cancelled -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.Path]::GetExtension($path) -ine '.apk') {
                Write-Host (Format-Message -Name 'BatchSkipped' -Values @($path)) -ForegroundColor Yellow
                $failed++
                $results += [pscustomobject]@{ Path = $path; Success = $false; ExitCode = 130; Details = 'Not attempted' }
                continue
            }
            Write-Host (Format-Message -Name 'InstallBatchItem' -Values @(($index + 1), $Paths.Count, $path))
            $result = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'install','-r',$path) -TimeoutSeconds 180
            if ($result.Output) { Write-Host $result.Output }
            $ok = $result.ExitCode -eq 0
            if ($ok) { $success++ } else { $failed++; Write-Host (Get-CommandAdvice -Output $result.Output -ExitCode $result.ExitCode) -ForegroundColor Yellow }
            $results += [pscustomobject]@{ Path = $path; Success = $ok; ExitCode = $result.ExitCode; Details = $result.Output }
            $cancelled = $result.Cancelled
        }
    $script:LastBatch = [pscustomobject]@{ Kind = 'Install'; Serial = $Serial; Results = $results }
    if ($failed) { $script:AnyBatchFailure = $true }
    Write-Host (Format-Message -Name 'InstallBatchSummary' -Values @($success, $failed)) -ForegroundColor $(if ($failed) { 'Yellow' } else { 'Green' })
    if ($Paths.Count -gt 1) { Write-Host $script:Messages.DropSplitHint -ForegroundColor DarkGray }
    try { [void](Save-OperationReport -Kind 'Install' -Serial $Serial -Results $results) } catch { Write-Warning $_.Exception.Message }
    Wait-ForMenuKey
}

function Install-SplitApkBatch {
    param([string]$AdbPath, [string]$Serial, [string[]]$Paths)
    $sdk = Get-AdbSdkLevel -AdbPath $AdbPath -Serial $Serial
    if ($sdk -gt 0 -and $sdk -lt 21) { Write-Host $script:Messages.SplitApkUnsupported -ForegroundColor Yellow; Wait-ForMenuKey; return }
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.Path]::GetExtension($path) -ine '.apk') { throw $script:Messages.ApkSplitAdvice }
    }
    $result = Invoke-ToolProcess -Executable $AdbPath -Arguments (@('-s',$Serial,'install-multiple','-r') + $Paths) -TimeoutSeconds 180
    if ($result.Output) { Write-Host $result.Output }
    $ok = $result.ExitCode -eq 0
    $results = @($Paths | ForEach-Object { [pscustomobject]@{ Path = $_; Success = $ok; ExitCode = $result.ExitCode; Details = $result.Output } })
    $script:LastBatch = [pscustomobject]@{ Kind = 'Split'; Serial = $Serial; Results = $results }
    if ($ok) { Write-Host $script:Messages.CommandSucceeded -ForegroundColor Green }
    else { $script:AnyBatchFailure = $true; Write-Host (Get-CommandAdvice -Output $result.Output -ExitCode $result.ExitCode) -ForegroundColor Yellow }
    try { [void](Save-OperationReport -Kind 'Split' -Serial $Serial -Results $results) } catch { Write-Warning $_.Exception.Message }
    Wait-ForMenuKey
}

function Retry-LastBatch {
    param([string]$AdbPath)
    if ($null -eq $script:LastBatch) { Write-Host $script:Messages.NoFailedBatch; Wait-ForMenuKey; return }
    $batch = $script:LastBatch
    $failed = @($batch.Results | Where-Object { -not $_.Success } | ForEach-Object { $_.Path })
    if (-not $failed.Count) { Write-Host $script:Messages.NoFailedBatch; Wait-ForMenuKey; return }
    $serial = Select-AdbDevice -AdbPath $AdbPath
    if (-not $serial) { return }
    if ($serial -cne $batch.Serial) { Write-Host $script:Messages.RetryWrongDevice -ForegroundColor Yellow; Wait-ForMenuKey; return }
    if (-not (Confirm-MenuAction -Prompt (Format-Message -Name 'RetryConfirm' -Values @($failed.Count,$serial)))) { return }
    if ($batch.Kind -eq 'Send') { Send-FilesToDevice -AdbPath $AdbPath -Serial $serial -Paths $failed }
    elseif ($batch.Kind -eq 'Split') { Install-SplitApkBatch -AdbPath $AdbPath -Serial $serial -Paths $failed }
    else { Install-ApkBatch -AdbPath $AdbPath -Serial $serial -Paths $failed }
}

function Get-ReadyAdbDevices {
    param([string]$AdbPath)
    $records = @(Get-AdbDeviceRecords -AdbPath $AdbPath)
    return @($records | Where-Object { $_.Status -eq 'device' } | ForEach-Object { $_.Serial })
}

function Get-AdbDeviceRecords {
    param([string]$AdbPath)
    $result = Invoke-ToolProcess -Executable $AdbPath -Arguments @('devices','-l') -TimeoutSeconds 15 -QuietProgress
    $output = @($result.Output -split '\r?\n')
    $deviceExitCode = $result.ExitCode
    if ($deviceExitCode -ne 0) {
        return @()
    }
    $devices = @()
    foreach ($line in $output) {
        if ([string]$line -match '^([^\s]+)\s+(device|offline|unauthorized|sideload|recovery)(?:\s|$)(.*)$') {
            $serial = [string]$Matches[1]
            $status = [string]$Matches[2]
            $details = [string]$Matches[3]
            $model = ''
            if ($details -match '(?:^|\s)model:([^\s]+)') {
                $model = [string]$Matches[1]
            }
            $devices += [pscustomobject]@{
                Serial = $serial
                Status = $status
                Model = $model
            }
        }
    }
    return $devices
}

function Get-LocalizedDeviceStatus {
    param([string]$Status)
    switch ($Status) {
        'device' { return $script:Messages.StatusDevice }
        'unauthorized' { return $script:Messages.StatusUnauthorized }
        'offline' { return $script:Messages.StatusOffline }
        'recovery' { return $script:Messages.StatusRecovery }
        'sideload' { return $script:Messages.StatusSideload }
        default { return $Status }
    }
}

function Get-DeviceAlias {
    param([object]$State, [string]$Serial)
    if ($null -eq $State -or $null -eq $State.PSObject.Properties['DeviceAliases']) { return '' }
    foreach ($entry in @($State.DeviceAliases)) {
        if ($null -ne $entry -and [string]$entry.Serial -ceq $Serial) {
            $alias = [string]$entry.Alias
            if ($alias.Length -le 32 -and $alias -notmatch '[\p{C}]') { return $alias }
        }
    }
    return ''
}

function Get-DeviceDisplayName {
    param([object]$State, [string]$Serial)
    $alias = Get-DeviceAlias -State $State -Serial $Serial
    if ($alias) { return ('{0} [{1}]' -f $alias, $Serial) }
    return $Serial
}

function Set-SelectedAdbDevice {
    param([string]$Serial)
    $script:SelectedDeviceSerial = $Serial
    if (-not $script:PinDeviceSelection -or -not $script:MenuInstallRoot) { return }
    $selectionMutex = $null
    try {
        $selectionMutex = Enter-UpdateLock -Root $script:MenuInstallRoot
        $state = Read-State -Root $script:MenuInstallRoot
        if ($null -eq $state) { throw (Format-Message -Name 'NotInstalled' -Values @($script:MenuInstallRoot)) }
        $recent = @($Serial)
        if ($null -ne $state.PSObject.Properties['RecentDevices']) {
            foreach ($previous in @($state.RecentDevices)) {
                $previousSerial = [string]$previous
                if (-not $previousSerial -or @($recent | Where-Object { $_ -ceq $previousSerial }).Count) { continue }
                $recent += $previousSerial
                if ($recent.Count -ge 5) { break }
            }
        }
        $state | Add-Member -NotePropertyName RecentDevices -NotePropertyValue $recent -Force
        Write-State -Root $script:MenuInstallRoot -State $state
        $script:MenuState = $state
    }
    catch { Write-Warning (Format-Message -Name 'DevicePreferenceSaveFailed' -Values @($_.Exception.Message)) }
    finally { if ($null -ne $selectionMutex) { Exit-UpdateLock -Mutex $selectionMutex } }
}

function Set-DeviceAlias {
    param([string]$Root, [string]$Serial, [string]$Alias)
    $normalizedAlias = $Alias.Trim()
    if ($normalizedAlias.Length -gt 32 -or $normalizedAlias -match '[\p{C}]') { throw $script:Messages.DeviceAliasInvalid }
    $aliasMutex = Enter-UpdateLock -Root $Root
    try {
        $state = Read-State -Root $Root
        if ($null -eq $state) { throw (Format-Message -Name 'NotInstalled' -Values @($Root)) }
        $aliases = @()
        if ($null -ne $state.PSObject.Properties['DeviceAliases']) {
            $aliases = @($state.DeviceAliases | Where-Object { $null -ne $_ -and [string]$_.Serial -cne $Serial })
        }
        if ($normalizedAlias) { $aliases += [pscustomobject]@{ Serial = $Serial; Alias = $normalizedAlias } }
        $state | Add-Member -NotePropertyName DeviceAliases -NotePropertyValue $aliases -Force
        Write-State -Root $Root -State $state
        $script:MenuState = $state
    }
    finally { Exit-UpdateLock -Mutex $aliasMutex }
    return $normalizedAlias
}

function Show-DeviceAliasMenu {
    param([string]$Root)
    Clear-Host
    if (-not $script:SelectedDeviceSerial) {
        Write-Host $script:Messages.DeviceAliasNoTarget -ForegroundColor Yellow
        Wait-ForMenuKey
        return
    }
    $target = Get-DeviceDisplayName -State $script:MenuState -Serial $script:SelectedDeviceSerial
    $newAlias = Read-Host (Format-Message -Name 'DeviceAliasPrompt' -Values @($target))
    try {
        $savedAlias = Set-DeviceAlias -Root $Root -Serial $script:SelectedDeviceSerial -Alias $newAlias
        if ($savedAlias) { Write-Host (Format-Message -Name 'DeviceAliasSaved' -Values @($savedAlias)) -ForegroundColor Green }
        else { Write-Host $script:Messages.DeviceAliasRemoved -ForegroundColor Green }
    }
    catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Wait-ForMenuKey
}

function Select-AdbDevice {
    param(
        [string]$AdbPath,
        [string[]]$AllowedStatuses = @('device'),
        [switch]$UsbOnly,
        [switch]$NetworkOnly,
        [switch]$ChooseAnother
    )
    $allRecords = @(Get-AdbDeviceRecords -AdbPath $AdbPath)
    $records = @($allRecords | Where-Object { $_.Status -in $AllowedStatuses })
    if ($UsbOnly) { $records = @($records | Where-Object { $_.Serial -notmatch '(^emulator-|:|\._tcp)' }) }
    if ($NetworkOnly) { $records = @($records | Where-Object { $_.Serial -match '^\d{1,3}(?:\.\d{1,3}){3}:5555$' }) }
    if ($script:PinDeviceSelection -and $script:SelectedDeviceSerial -and -not $ChooseAnother) {
        $selectedRecord = @($records | Where-Object { $_.Serial -ceq $script:SelectedDeviceSerial })
        if ($selectedRecord.Count -eq 1) { return [string]$script:SelectedDeviceSerial }
        Clear-Host
        $unusableRecord = @($allRecords | Where-Object { $_.Serial -ceq $script:SelectedDeviceSerial } | Select-Object -First 1)
        if ($unusableRecord.Count -eq 1 -and $unusableRecord[0].Status -notin $AllowedStatuses) {
            $statusText = Get-LocalizedDeviceStatus -Status ([string]$unusableRecord[0].Status)
            Write-Host (Format-Message -Name 'SelectedDeviceWrongState' -Values @($script:SelectedDeviceSerial, $statusText)) -ForegroundColor Yellow
        }
        else {
            Write-Host (Format-Message -Name 'SelectedDeviceUnavailable' -Values @($script:SelectedDeviceSerial)) -ForegroundColor Yellow
        }
        Wait-ForMenuKey
        return $null
    }
    if ($records.Count -eq 0) {
        Clear-Host
        $message = if ($AllowedStatuses.Count -eq 1 -and $AllowedStatuses[0] -eq 'sideload') {
            $script:Messages.SideloadNoDevice
        }
        elseif ($UsbOnly) { $script:Messages.NoUsbDevice }
        elseif ($NetworkOnly) { $script:Messages.NoLegacyNetworkDevice }
        else { $script:Messages.NoReadyDevice }
        Write-Host $message -ForegroundColor Red
        Wait-ForMenuKey
        return $null
    }
    if ($records.Count -eq 1) {
        if ($script:PinDeviceSelection) { Set-SelectedAdbDevice -Serial ([string]$records[0].Serial) }
        return [string]$records[0].Serial
    }

    if ($null -ne $script:MenuState -and $null -ne $script:MenuState.PSObject.Properties['RecentDevices']) {
        $orderedRecords = @()
        foreach ($recentSerial in @($script:MenuState.RecentDevices)) {
            $recentRecord = @($records | Where-Object { $_.Serial -ceq [string]$recentSerial } | Select-Object -First 1)
            if ($recentRecord.Count -eq 1 -and -not @($orderedRecords | Where-Object { $_.Serial -ceq [string]$recentSerial }).Count) {
                $orderedRecords += $recentRecord[0]
            }
        }
        $orderedRecords += @($records | Where-Object { $serial = $_.Serial; -not @($orderedRecords | Where-Object { $_.Serial -ceq $serial }).Count })
        $records = $orderedRecords
    }
    $serial = Select-PagedRecord -Records $records -Title $script:Messages.ChooseDevice -State $script:MenuState
    if ($serial -and $script:PinDeviceSelection) { Set-SelectedAdbDevice -Serial $serial }
    return $serial
}

function Select-PagedRecord {
    param([object[]]$Records, [string]$Title, [object]$State = $null)
    if (-not $Records.Count) { return $null }
    $page = 0; $pageSize = 9; $pageCount = [int][Math]::Ceiling($Records.Count / $pageSize)
    while ($true) {
        Clear-Host
        Write-Host $Title -ForegroundColor Cyan
        $visible = @($Records | Select-Object -Skip ($page * $pageSize) -First $pageSize)
        for ($index = 0; $index -lt $visible.Count; $index++) {
            $record = $visible[$index]
            $label = Get-DeviceDisplayName -State $State -Serial $record.Serial
            if ($record.Model) { $label += '  (' + $record.Model + ')' }
            if ($record.Status) { $label += ' / ' + (Get-LocalizedDeviceStatus -Status $record.Status) }
            Write-Host ('  [ {0} ] {1}' -f ($index+1),$label)
        }
        Write-Host ''
        Write-Host (Format-Message -Name 'DevicePage' -Values @(($page+1),$pageCount)) -ForegroundColor Yellow
        $choice = Read-MenuChoice
        if ($choice -eq 'Escape') { return $null }
        if ($choice -eq 'N' -and $page -lt $pageCount-1) { $page++; continue }
        if ($choice -eq 'P' -and $page -gt 0) { $page--; continue }
        $number = 0
        if ([int]::TryParse($choice,[ref]$number) -and $number -ge 1 -and $number -le $visible.Count) { return [string]$visible[$number-1].Serial }
    }
}

function Get-AdbProperty {
    param(
        [string]$AdbPath,
        [string]$Serial,
        [string]$Property
    )
    try {
        $result = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'shell','getprop',$Property) -TimeoutSeconds 10 -QuietProgress
        if ($result.ExitCode -ne 0 -or -not $result.Output) { return '' }
        return ([string]($result.Output -split '\r?\n')[0]).Trim()
    }
    catch { return '' }
}

function Get-AdbSdkLevel {
    param([string]$AdbPath, [string]$Serial)
    $value = Get-AdbProperty -AdbPath $AdbPath -Serial $Serial -Property 'ro.build.version.sdk'
    $sdk = 0
    if ([int]::TryParse($value, [ref]$sdk) -and $sdk -gt 0) { return $sdk }
    return 0
}

function Show-DeviceInfo {
    param([string]$AdbPath)
    $serial = Select-AdbDevice -AdbPath $AdbPath
    if (-not $serial) { return }
    $model = Get-AdbProperty -AdbPath $AdbPath -Serial $serial -Property 'ro.product.model'
    $android = Get-AdbProperty -AdbPath $AdbPath -Serial $serial -Property 'ro.build.version.release'
    $abi = Get-AdbProperty -AdbPath $AdbPath -Serial $serial -Property 'ro.product.cpu.abi'
    $sdk = Get-AdbSdkLevel -AdbPath $AdbPath -Serial $serial
    Clear-Host
    Write-Host $script:Messages.DeviceInfoTitle -ForegroundColor Cyan
    Write-Host $serial
    foreach ($entry in @(
        @($script:Messages.DeviceInfoModel, $model),
        @($script:Messages.DeviceInfoAndroid, $android),
        @($script:Messages.DeviceInfoSdk, $(if ($sdk) { [string]$sdk } else { '' })),
        @($script:Messages.DeviceInfoAbi, $abi)
    )) {
        $value = if ($entry[1]) { $entry[1] } else { $script:Messages.DeviceInfoUnknown }
        Write-Host (Format-Message -Name 'DeviceInfoLine' -Values @($entry[0], $value))
    }
    if ($sdk -gt 0 -and $sdk -lt 21) { Write-Host $script:Messages.SplitApkUnsupported -ForegroundColor Yellow }
    if ($sdk -gt 0 -and $sdk -le 29) { Write-Host $script:Messages.DeviceInfoOldWifi -ForegroundColor Yellow }
    if ($sdk -ge 30) { Write-Host $script:Messages.DeviceInfoNewWifi -ForegroundColor Green }
    Wait-ForMenuKey
}

function Test-CaptureSignature {
    param([string]$Path, [ValidateSet('PNG','MP4')][string]$Format)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $stream = [IO.File]::OpenRead($Path)
    try {
        $header = New-Object byte[] 12
        $read = $stream.Read($header,0,$header.Length)
        if ($Format -eq 'PNG') { return $read -ge 8 -and [BitConverter]::ToString($header,0,8) -eq '89-50-4E-47-0D-0A-1A-0A' }
        return $read -ge 8 -and [Text.Encoding]::ASCII.GetString($header,4,4) -eq 'ftyp'
    }
    finally { $stream.Dispose() }
}

function Save-AdbScreenshot {
    param(
        [string]$AdbPath,
        [string]$Serial
    )
    $outputFolder = Get-ActiveOutputFolder
    $name = 'LeanADB-Screenshot-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png'
    $destination = Join-Path $outputFolder $name
    $temporary = "$destination.partial"
    $errorFile = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-screenshot-' + [guid]::NewGuid().ToString('N') + '.log')
    try {
        $directSucceeded = $false
        $cancelled = $false
        try {
            $process = Invoke-ToolProcess -Executable $AdbPath -Arguments @(
                '-s', $Serial, 'exec-out', 'screencap', '-p'
            ) -TimeoutSeconds 60 -OutputFile $temporary
            $cancelled = $process.Cancelled
            $directSucceeded = $process.ExitCode -eq 0 -and
                (Test-Path -LiteralPath $temporary -PathType Leaf) -and
                (Test-CaptureSignature -Path $temporary -Format PNG)
        }
        catch {
            $directSucceeded = $false
        }
        if ($cancelled) { throw $script:Messages.OperationCancelled }
        if (-not $directSucceeded) {
            Write-Host $script:Messages.ScreenshotFallback -ForegroundColor Yellow
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
            $remotePath = '/sdcard/LeanADB-screenshot-' + [guid]::NewGuid().ToString('N') + '.png'
            $previousPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $capture = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'shell','screencap','-p',$remotePath) -TimeoutSeconds 60
                if ($capture.ExitCode -ne 0) { throw 'Legacy device screenshot command failed.' }
                $transfer = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'pull',$remotePath,$temporary) -TimeoutSeconds 60
                if ($transfer.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $temporary -PathType Leaf) -or
                    (Get-Item -LiteralPath $temporary).Length -eq 0) {
                    throw 'Legacy device screenshot transfer failed.'
                }
            }
            finally {
                try { [void](Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'shell','rm',$remotePath) -TimeoutSeconds 10 -QuietProgress) } catch { }
                $ErrorActionPreference = $previousPreference
            }
        }
        if (-not (Test-CaptureSignature -Path $temporary -Format PNG)) { throw 'The device did not return a valid PNG header.' }
        Move-Item -LiteralPath $temporary -Destination $destination -Force
        $script:LastSavedPath = $destination
        Write-Host ''
        Write-Host (Format-Message -Name 'ScreenshotSaved' -Values @($destination)) -ForegroundColor Green
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        if (Test-Path -LiteralPath $errorFile) { Remove-Item -LiteralPath $errorFile -Force }
    }
    Wait-ForMenuKey
}

function Save-AdbScreenrecord {
    param([string]$AdbPath, [string]$Serial)
    Clear-Host
    Write-Host $script:Messages.ScreenrecordTitle -ForegroundColor Cyan
    $sdk = Get-AdbSdkLevel -AdbPath $AdbPath -Serial $Serial
    if ($sdk -eq 0) {
        Write-Host $script:Messages.ScreenrecordUnknownApi -ForegroundColor Yellow
        Wait-ForMenuKey
        return
    }
    if ($sdk -lt 19) {
        Write-Host (Format-Message -Name 'ScreenrecordUnsupported' -Values @($sdk)) -ForegroundColor Yellow
        Wait-ForMenuKey
        return
    }
    Write-Host $script:Messages.ScreenrecordNoAudio -ForegroundColor Yellow
    $answer = (Read-Host -Prompt $script:Messages.ScreenrecordDuration).Trim()
    $seconds = 30
    if ($answer -and (-not [int]::TryParse($answer, [ref]$seconds) -or $seconds -lt 1 -or $seconds -gt 180)) {
        Write-Host $script:Messages.ScreenrecordInvalidDuration -ForegroundColor Red
        Wait-ForMenuKey
        return
    }
    $outputFolder = Get-ActiveOutputFolder
    $destination = Join-Path $outputFolder ('LeanADB-Recording-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.mp4')
    $temporary = "$destination.partial"
    $remotePath = '/sdcard/LeanADB-recording-' + [guid]::NewGuid().ToString('N') + '.mp4'
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        Write-Host (Format-Message -Name 'ScreenrecordRunning' -Values @($seconds))
        $record = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'shell','screenrecord','--time-limit',[string]$seconds,$remotePath) -TimeoutSeconds ($seconds + 30)
        if ($record.ExitCode -ne 0) { throw (Get-CommandAdvice -Output $record.Output -ExitCode $record.ExitCode) }
        $transfer = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'pull',$remotePath,$temporary)
        if ($transfer.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $temporary -PathType Leaf) -or
            (Get-Item -LiteralPath $temporary).Length -eq 0) { throw $script:Messages.ScreenrecordFailed }
        if (-not (Test-CaptureSignature -Path $temporary -Format MP4)) { throw $script:Messages.ScreenrecordFailed }
        Move-Item -LiteralPath $temporary -Destination $destination
        $script:LastSavedPath = $destination
        Write-Host (Format-Message -Name 'ScreenrecordSaved' -Values @($destination)) -ForegroundColor Green
    }
    catch {
        Write-Host "$($script:Messages.ScreenrecordFailed) $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        try { [void](Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'shell','rm',$remotePath) -TimeoutSeconds 10 -QuietProgress) } catch { }
        $ErrorActionPreference = $previousPreference
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    Wait-ForMenuKey
}

function Receive-AdbPath {
    param(
        [string]$AdbPath,
        [string]$Serial,
        [string]$RemotePath = ''
    )
    Clear-Host
    if (-not $RemotePath) { $RemotePath = (Read-Host -Prompt $script:Messages.RemotePathPrompt).Trim() }
    if ($RemotePath -notmatch '^/(?:sdcard(?:/|$)|storage/)' -or $RemotePath -match '(^|/)\.\.(/|$)|[\x00-\x1F\x7F]') {
        Write-Host $script:Messages.InvalidRemotePath -ForegroundColor Red
        Wait-ForMenuKey
        return
    }
    $outputFolder = Get-ActiveOutputFolder
    $destination = Join-Path $outputFolder ('LeanADB-Received-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $destination | Out-Null
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $transfer = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'pull',$RemotePath,$destination)
        if ($transfer.Output) { Write-Host $transfer.Output }
        $receiveExitCode = $transfer.ExitCode
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($receiveExitCode -eq 0) {
        Write-Host ''
        Write-Host (Format-Message -Name 'ReceiveCompleted' -Values @($destination)) -ForegroundColor Green
        $script:LastSavedPath = $destination
        Start-Process -FilePath 'explorer.exe' -ArgumentList @('"' + $destination + '"')
    }
    else {
        if (@(Get-ChildItem -LiteralPath $destination -Force).Count -eq 0) { Remove-Item -LiteralPath $destination -Force }
        Write-Host (Format-Message -Name 'CommandFailed' -Values @($receiveExitCode)) -ForegroundColor Red
    }
    Wait-ForMenuKey
}

function Save-AdbLogcat {
    param(
        [string]$AdbPath,
        [string]$Serial
    )
    $outputFolder = Get-ActiveOutputFolder
    $destination = Join-Path $outputFolder ('LeanADB-Logcat-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.txt')
    $errorFile = Join-Path ([IO.Path]::GetTempPath()) ('LeanADB-logcat-' + [guid]::NewGuid().ToString('N') + '.log')
    try {
        $process = Invoke-ToolProcess -Executable $AdbPath -Arguments @(
            '-s', $Serial, 'logcat', '-d', '-v', 'threadtime'
        ) -TimeoutSeconds 60 -OutputFile $destination
        if ($process.ExitCode -ne 0) {
            $details = $process.Output
            throw "Logcat failed (exit code $($process.ExitCode)). $details"
        }
        Write-Host ''
        Write-Host (Format-Message -Name 'LogcatSaved' -Values @($destination)) -ForegroundColor Green
        $script:LastSavedPath = $destination
    }
    catch {
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $errorFile) { Remove-Item -LiteralPath $errorFile -Force }
    }
    Wait-ForMenuKey
}

function Read-SecureConsoleText {
    param([string]$Prompt)
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Test-AdbEndpoint {
    param([string]$Endpoint)
    if ($Endpoint -notmatch '^(\[[0-9A-Fa-f:%.]+\]|[A-Za-z0-9][A-Za-z0-9.-]*):(\d{1,5})$') { return $false }
    $hostName = $Matches[1]; $port = [int]$Matches[2]
    if ($port -lt 1 -or $port -gt 65535) { return $false }
    if ($hostName.StartsWith('[')) {
        $address = $null
        return [Net.IPAddress]::TryParse($hostName.Trim('[',']'), [ref]$address) -and $address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6
    }
    if ($hostName -match '^\d+(?:\.\d+)+$') {
        return $hostName -match '^\d{1,3}(?:\.\d{1,3}){3}$' -and -not @($hostName.Split('.') | Where-Object { [int]$_ -gt 255 }).Count
    }
    return [Uri]::CheckHostName($hostName) -eq [UriHostNameType]::Dns
}

function Test-PrivateIpv4 {
    param([string]$Address)
    if ($Address -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$') { return $false }
    $parts = @($Address.Split('.') | ForEach-Object { [int]$_ })
    if (@($parts | Where-Object { $_ -gt 255 }).Count) { return $false }
    return $parts[0] -eq 10 -or
        ($parts[0] -eq 172 -and $parts[1] -ge 16 -and $parts[1] -le 31) -or
        ($parts[0] -eq 192 -and $parts[1] -eq 168)
}

function Start-LegacyWireless {
    param([string]$AdbPath)
    $serial = Select-AdbDevice -AdbPath $AdbPath -UsbOnly
    if (-not $serial) { return }
    Clear-Host
    Write-Host $script:Messages.LegacyWifiHelp -ForegroundColor Yellow
    $suggested = Get-AdbProperty -AdbPath $AdbPath -Serial $serial -Property 'dhcp.wlan0.ipaddress'
    $prompt = if (Test-PrivateIpv4 -Address $suggested) { Format-Message -Name 'WirelessSuggestedIp' -Values @($suggested) } else { $script:Messages.LegacyWifiAddress }
    $address = (Read-Host -Prompt $prompt).Trim()
    if (-not $address -and (Test-PrivateIpv4 -Address $suggested)) { $address = $suggested }
    if (-not (Test-PrivateIpv4 -Address $address)) {
        Write-Host $script:Messages.InvalidLocalIp -ForegroundColor Red
        Wait-ForMenuKey
        return
    }
    $endpoint = '{0}:5555' -f $address
    $prompt = Format-Message -Name 'LegacyWifiConfirm' -Values @($serial, $endpoint)
    if (-not (Confirm-MenuAction -Prompt $prompt)) { return }
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $tcpip = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$serial,'tcpip','5555') -TimeoutSeconds 30
        $tcpipExit = $tcpip.ExitCode
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($tcpipExit -ne 0) {
        Write-Host (Format-Message -Name 'CommandFailed' -Values @($tcpipExit)) -ForegroundColor Red
        Wait-ForMenuKey
        return
    }
    $connection = Invoke-MenuCommand -Executable $AdbPath -Arguments @('connect', $endpoint)
    if ($null -ne $connection -and $connection.ExitCode -eq 0 -and $script:PinDeviceSelection) {
        $ready = @(Get-AdbDeviceRecords -AdbPath $AdbPath | Where-Object { $_.Serial -ceq $endpoint -and $_.Status -eq 'device' })
        if ($ready.Count) { Set-SelectedAdbDevice -Serial $endpoint; Write-Host (Format-Message -Name 'WirelessSelected' -Values @($endpoint)) }
    }
}

function Return-LegacyWirelessToUsb {
    param([string]$AdbPath)
    $serial = Select-AdbDevice -AdbPath $AdbPath -NetworkOnly -ChooseAnother
    if (-not $serial) { return }
    if (-not (Confirm-MenuAction -Prompt (Format-Message -Name 'WirelessUsbConfirm' -Values @($serial)))) { return }
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $usb = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$serial,'usb') -TimeoutSeconds 30
        $usbExit = $usb.ExitCode
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($usbExit -eq 0) {
        Write-Host $script:Messages.LegacyWifiDisabled -ForegroundColor Green
    }
    else {
        Write-Host (Format-Message -Name 'CommandFailed' -Values @($usbExit)) -ForegroundColor Red
    }
    Wait-ForMenuKey
}

function Show-WirelessMenu {
    param([string]$AdbPath)
    while ($true) {
        Clear-Host
        Write-Host '=======================================================================' -ForegroundColor Cyan
        Write-Host ("                         " + $script:Messages.WirelessTitle) -ForegroundColor Cyan
        Write-Host '=======================================================================' -ForegroundColor Cyan
        Write-Host ''
        Write-Host "  $($script:Messages.WirelessPair)"
        Write-Host "  $($script:Messages.WirelessConnect)"
        Write-Host "  $($script:Messages.WirelessDisconnect)"
        Write-Host "  $($script:Messages.WirelessLegacy)"
        Write-Host "  $($script:Messages.WirelessReturnUsb)"
        Write-Host "  $($script:Messages.WirelessDiscovery)"
        Write-Host ''
        Write-Host "  $($script:Messages.WirelessBack)" -ForegroundColor Yellow
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Escape' { return }
            'P' {
                Clear-Host
                $endpoint = (Read-Host -Prompt $script:Messages.PairAddress).Trim()
                if (-not (Test-AdbEndpoint -Endpoint $endpoint)) {
                    Write-Host $script:Messages.InvalidEndpoint -ForegroundColor Red
                    Wait-ForMenuKey
                    continue
                }
                $code = Read-SecureConsoleText -Prompt $script:Messages.PairCode
                if ($code -notmatch '^\d{6}$') {
                    Write-Host $script:Messages.InvalidPairCode -ForegroundColor Red
                    Wait-ForMenuKey
                    continue
                }
                [void](Invoke-MenuCommand -Executable $AdbPath -Arguments @('pair', $endpoint, $code))
                $code = $null
            }
            'C' {
                Clear-Host
                $endpoint = (Read-Host -Prompt $script:Messages.ConnectAddress).Trim()
                if (-not (Test-AdbEndpoint -Endpoint $endpoint)) {
                    Write-Host $script:Messages.InvalidEndpoint -ForegroundColor Red
                    Wait-ForMenuKey
                    continue
                }
                $connection = Invoke-MenuCommand -Executable $AdbPath -Arguments @('connect', $endpoint)
                if ($connection.ExitCode -eq 0 -and $script:PinDeviceSelection) {
                    $ready = @(Get-AdbDeviceRecords -AdbPath $AdbPath | Where-Object { $_.Serial -ceq $endpoint -and $_.Status -eq 'device' })
                    if ($ready.Count) { Set-SelectedAdbDevice -Serial $endpoint }
                }
            }
            'D' {
                Clear-Host
                $network = @(Get-AdbDeviceRecords -AdbPath $AdbPath | Where-Object { $_.Serial -match ':|\._tcp' })
                $serial = Select-PagedRecord -Records $network -Title $script:Messages.WirelessDisconnect -State $script:MenuState
                if ($serial) { [void](Invoke-MenuCommand -Executable $AdbPath -Arguments @('disconnect',$serial)) }
            }
            'M' { [void](Invoke-MenuCommand -Executable $AdbPath -Arguments @('mdns','services')) }
            'L' { Start-LegacyWireless -AdbPath $AdbPath }
            'U' { Return-LegacyWirelessToUsb -AdbPath $AdbPath }
        }
    }
}

function Set-UsbBackend {
    param(
        [string]$Root,
        [string]$AdbPath,
        [ValidateSet('Standard', 'Legacy')][string]$Preference
    )
    $mutex = Enter-UpdateLock -Root $Root
    $previousValue = [Environment]::GetEnvironmentVariable('ADB_USB_LEGACY', 'Process')
    try {
        $currentState = Read-State -Root $Root
        if ($null -eq $currentState) { throw (Format-Message -Name 'NotInstalled' -Values @($Root)) }
        Stop-AdbServer -AdbPath $AdbPath
        if ($Preference -eq 'Legacy') { $env:ADB_USB_LEGACY = '1' }
        else { Remove-Item Env:ADB_USB_LEGACY -ErrorAction SilentlyContinue }
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $AdbPath start-server
            $startExit = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
        if ($startExit -ne 0) {
            [Environment]::SetEnvironmentVariable('ADB_USB_LEGACY', $previousValue, 'Process')
            throw $script:Messages.UsbBackendFailed
        }
        $currentState | Add-Member -NotePropertyName UsbBackend -NotePropertyValue $Preference -Force
        Write-State -Root $Root -State $currentState
    }
    finally { Exit-UpdateLock -Mutex $mutex }
    $label = if ($Preference -eq 'Legacy') { $script:Messages.UsbBackendLegacy } else { $script:Messages.UsbBackendStandard }
    Write-Host (Format-Message -Name 'UsbBackendChanged' -Values @($label)) -ForegroundColor Green
    Wait-ForMenuKey
}

function Show-ConnectionHelp {
    param([string]$Root, [string]$AdbPath)
    while ($true) {
        Clear-Host
        Write-Host '=======================================================================' -ForegroundColor Cyan
        Write-Host ("                         " + $script:Messages.HelpTitle) -ForegroundColor Cyan
        Write-Host '=======================================================================' -ForegroundColor Cyan
        Write-Host ''
        Write-Host "  $($script:Messages.HelpDrivers)"
        Write-Host "  $($script:Messages.HelpDeviceManager)"
        Write-Host "  $($script:Messages.HelpLicense)"
        Write-Host "  $($script:Messages.HelpLegacyUsb)"
        Write-Host "  $($script:Messages.HelpDefaultUsb)"
        Write-Host ''
        Write-Host "  $($script:Messages.HelpBack)" -ForegroundColor Yellow
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Escape' { return }
            'D' { Start-Process 'https://developer.android.com/studio/run/oem-usb' }
            'M' { Start-Process -FilePath 'devmgmt.msc' }
            'T' { Start-Process $script:LicenseUrl }
            'L' { Set-UsbBackend -Root $Root -AdbPath $AdbPath -Preference Legacy }
            'N' { Set-UsbBackend -Root $Root -AdbPath $AdbPath -Preference Standard }
        }
    }
}

function Get-AdbStatusAdvice {
    param([string]$Status)
    switch ($Status) {
        'device' { return $script:Messages.DiagnoseReady }
        'unauthorized' { return $script:Messages.DiagnoseUnauthorized }
        'offline' { return $script:Messages.DiagnoseOffline }
        'recovery' { return $script:Messages.DiagnoseRecovery }
        'sideload' { return $script:Messages.DiagnoseSideload }
        default { return '' }
    }
}

function Show-ConnectionDiagnostics {
    param([string]$Root, [string]$AdbPath, [string]$FastbootPath, [object]$State)
    $latestState = Read-State -Root $Root
    if ($null -ne $latestState) { $State = $latestState }
    Clear-Host
    Write-Host $script:Messages.DiagnoseTitle -ForegroundColor Cyan
    Write-Host ''
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $adbVersion = @(& $AdbPath version 2>&1 | Select-Object -First 2)
        $fastbootVersion = @(& $FastbootPath --version 2>&1 | Select-Object -First 1)
        $fastbootDevices = @(& $FastbootPath devices 2>&1)
        $fastbootExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($adbVersion.Count) { Write-Host (Format-Message -Name 'DiagnoseAdbVersion' -Values @(($adbVersion -join ' '))) }
    if ($fastbootVersion.Count) { Write-Host (Format-Message -Name 'DiagnoseFastbootVersion' -Values @($fastbootVersion[0])) }
    Write-Host ''
    $records = @(Get-AdbDeviceRecords -AdbPath $AdbPath)
    if ($records.Count -eq 0) { Write-Host $script:Messages.DiagnoseNoDevice -ForegroundColor Yellow }
    foreach ($record in $records) {
        Write-Host (Format-Message -Name 'DeviceStatus' -Values @($record.Serial, (Get-LocalizedDeviceStatus -Status $record.Status), $record.Model))
        $hint = Get-AdbStatusAdvice -Status $record.Status
        if ($hint) { Write-Host "  $hint" }
    }
    $fastbootSerials = @(if ($fastbootExitCode -eq 0) {
        @($fastbootDevices | ForEach-Object { if ([string]$_ -match '^([^\s]+)\s+fastboot(?:\s|$)') { $Matches[1] } })
    })
    if ($fastbootSerials.Count) {
        foreach ($serial in $fastbootSerials) {
            Write-Host (Format-Message -Name 'DiagnoseFastboot' -Values @($serial)) -ForegroundColor Green
        }
    }
    else { Write-Host $script:Messages.DiagnoseNoFastboot -ForegroundColor DarkGray }
    $resolvedAdb = Get-RegisteredAdbPath
    if ($resolvedAdb -and $resolvedAdb -ine $AdbPath) {
        Write-Host (Format-Message -Name 'DiagnosePathConflict' -Values @($resolvedAdb)) -ForegroundColor Yellow
    }
    $backend = if ($null -ne $State.PSObject.Properties['UsbBackend'] -and $State.UsbBackend -eq 'Legacy') {
        $script:Messages.UsbBackendLegacy
    } else { $script:Messages.UsbBackendStandard }
    Write-Host (Format-Message -Name 'DiagnoseUsbBackend' -Values @($backend))
    Wait-ForMenuKey
}

function Show-ConnectionGuide {
    param([string]$Root, [string]$AdbPath, [string]$FastbootPath)
    while ($true) {
        $records = @(Get-AdbDeviceRecords -AdbPath $AdbPath)
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $fastbootOutput = @(& $FastbootPath devices 2>&1)
            $fastbootExitCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
        $fastbootSerials = @()
        if ($fastbootExitCode -eq 0) {
            foreach ($line in $fastbootOutput) {
                if ([string]$line -match '^([^\s]+)\s+fastboot(?:\s|$)') { $fastbootSerials += [string]$Matches[1] }
            }
        }

        Clear-Host
        Write-Host $script:Messages.ConnectionGuideTitle -ForegroundColor Cyan
        Write-Host ''
        if ($script:SelectedDeviceSerial) {
            $targetName = Get-DeviceDisplayName -State $script:MenuState -Serial $script:SelectedDeviceSerial
            $selectedRecord = @($records | Where-Object { $_.Serial -ceq $script:SelectedDeviceSerial } | Select-Object -First 1)
            if ($selectedRecord.Count -eq 1) {
                $statusText = Get-LocalizedDeviceStatus -Status ([string]$selectedRecord[0].Status)
                Write-Host (Format-Message -Name 'MenuTargetSelected' -Values @($targetName, $statusText)) -ForegroundColor Cyan
            }
            else { Write-Host (Format-Message -Name 'MenuTargetUnavailable' -Values @($targetName)) -ForegroundColor Yellow }
        }
        else { Write-Host $script:Messages.MenuTargetNone -ForegroundColor DarkGray }
        Write-Host ''
        foreach ($record in $records) {
            Write-Host (Format-Message -Name 'DeviceStatus' -Values @($record.Serial, (Get-LocalizedDeviceStatus -Status $record.Status), $record.Model))
            $advice = Get-AdbStatusAdvice -Status $record.Status
            if ($advice) { Write-Host "  $advice" -ForegroundColor Yellow }
        }
        foreach ($serial in $fastbootSerials) {
            Write-Host (Format-Message -Name 'DiagnoseFastboot' -Values @($serial)) -ForegroundColor Green
        }
        if ($records.Count -eq 0) {
            $advice = if ($fastbootSerials.Count) { $script:Messages.ConnectionGuideFastbootOnly } else { $script:Messages.DiagnoseNoDevice }
            Write-Host $advice -ForegroundColor Yellow
        }
        if ($records.Count -gt 1) { Write-Host $script:Messages.ConnectionGuideMultiple -ForegroundColor Yellow }
        Write-Host ''
        Write-Host "  $($script:Messages.ConnectionGuideRefresh)"
        Write-Host "  $($script:Messages.ConnectionGuideChoose)"
        Write-Host "  $($script:Messages.ConnectionGuideDiagnose)"
        Write-Host "  $($script:Messages.ConnectionGuideHelp)"
        Write-Host "  $($script:Messages.ConnectionGuideBack)" -ForegroundColor Yellow
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Escape' { return }
            'R' { continue }
            'C' { [void](Select-AdbDevice -AdbPath $AdbPath -AllowedStatuses @('device', 'offline', 'unauthorized', 'sideload', 'recovery') -ChooseAnother) }
            'X' { Show-ConnectionDiagnostics -Root $Root -AdbPath $AdbPath -FastbootPath $FastbootPath -State (Read-State -Root $Root) }
            'H' { Show-ConnectionHelp -Root $Root -AdbPath $AdbPath }
        }
    }
}

function Show-OutputFolderMenu {
    param([string]$Root)
    while ($true) {
        $currentState = Read-State -Root $Root
        if ($null -eq $currentState) { throw (Format-Message -Name 'NotInstalled' -Values @($Root)) }
        $currentFolder = Get-OutputFolder -Root $Root -State $currentState
        Clear-Host
        Write-Host $script:Messages.OutputFolderTitle -ForegroundColor Cyan
        Write-Host (Format-Message -Name 'OutputFolderCurrent' -Values @($currentFolder))
        Write-Host ''
        Write-Host "  $($script:Messages.OutputFolderDownloads)"
        Write-Host "  $($script:Messages.OutputFolderPortable)"
        Write-Host "  $($script:Messages.OutputFolderCustom)"
        Write-Host "  $($script:Messages.HelpBack)" -ForegroundColor Yellow
        $key = [Console]::ReadKey($true)
        $folder = switch ($key.Key) {
            'D' { Get-DownloadsFolder }
            'P' { Get-PortableFilesPath -Root $Root }
            'C' {
                Add-Type -AssemblyName System.Windows.Forms
                $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                try {
                    $dialog.Description = $script:Messages.OutputFolderTitle
                    $dialog.ShowNewFolderButton = $true
                    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        [string]$dialog.SelectedPath
                    }
                }
                finally { $dialog.Dispose() }
            }
            'Escape' { return }
            default { '' }
        }
        if (-not $folder) { continue }
        $folder = [IO.Path]::GetFullPath($folder)
        $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        if ($folder.TrimEnd('\') -ieq $normalizedRoot -or $folder.StartsWith($normalizedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            Write-Host $script:Messages.OutputInsideInstall -ForegroundColor Red
            Wait-ForMenuKey
            continue
        }
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            try { New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null }
            catch {
                Write-Host (Format-Message -Name 'OutputFolderUnavailable' -Values @($folder)) -ForegroundColor Red
                Wait-ForMenuKey
                continue
            }
        }
        $mutex = Enter-UpdateLock -Root $Root
        try {
            $currentState = Read-State -Root $Root
            $currentState | Add-Member -NotePropertyName OutputFolder -NotePropertyValue $folder -Force
            Write-State -Root $Root -State $currentState
        }
        finally { Exit-UpdateLock -Mutex $mutex }
        $script:ActiveOutputFolder = $folder
        Write-Host (Format-Message -Name 'OutputFolderSaved' -Values @($folder)) -ForegroundColor Green
        Wait-ForMenuKey
        return
    }
}

function Get-DeviceFolderEntries {
    param([string]$AdbPath, [string]$Serial, [string]$Folder)
    if ($Folder -notmatch '^/sdcard(?:/|$)' -or $Folder -match '(^|/)\.\.(/|$)|[\x00-\x1F\x7F]') { throw 'Unsafe browse folder.' }
    $shellPath = ConvertTo-AndroidShellLiteral -Value $Folder
    $previousPreference = $ErrorActionPreference
    $previousEncoding = [Console]::OutputEncoding
    try {
        $ErrorActionPreference = 'Continue'
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $lines = @(& $AdbPath -s $Serial shell ("ls -1 $shellPath") 2>&1)
        $listExitCode = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $previousEncoding
        $ErrorActionPreference = $previousPreference
    }
    if ($listExitCode -ne 0) { throw $script:Messages.BrowseListFailed }
    return @($lines | ForEach-Object { ([string]$_).TrimEnd("`r") } |
        Where-Object { $_ -and $_ -notin @('.', '..') -and $_ -notmatch '[/\x00-\x1F\x7F]' } | Sort-Object)
}

function ConvertTo-AndroidShellLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function Test-AdbRemoteDirectory {
    param([string]$AdbPath, [string]$Serial, [string]$Path)
    if ($Path -notmatch '^/sdcard/' -or $Path -match '(^|/)\.\.(/|$)|[\x00-\x1F\x7F]') { return $false }
    $shellPath = ConvertTo-AndroidShellLiteral -Value $Path
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $result = @(& $AdbPath -s $Serial shell ("if [ -d $shellPath ]; then echo LEANADB_DIR; fi") 2>&1)
        return $LASTEXITCODE -eq 0 -and 'LEANADB_DIR' -in $result
    }
    finally { $ErrorActionPreference = $previousPreference }
}

function Browse-AdbFiles {
    param([string]$AdbPath, [string]$Serial)
    while ($true) {
        Clear-Host
        Write-Host $script:Messages.BrowseTitle -ForegroundColor Cyan
        Write-Host "  $($script:Messages.BrowseDownload)"
        Write-Host "  $($script:Messages.BrowseDcim)"
        Write-Host "  $($script:Messages.BrowsePictures)"
        Write-Host "  $($script:Messages.BrowseDocuments)"
        Write-Host "  $($script:Messages.BrowseRoot)"
        Write-Host "  $($script:Messages.HelpBack)" -ForegroundColor Yellow
        $key = [Console]::ReadKey($true)
        $folder = switch ($key.Key) {
            'D' { '/sdcard/Download' }
            'C' { '/sdcard/DCIM' }
            'P' { '/sdcard/Pictures' }
            'O' { '/sdcard/Documents' }
            'R' { '/sdcard' }
            'Escape' { return }
            default { '' }
        }
        if (-not $folder) { continue }
        while ($true) {
            try { $entries = @(Get-DeviceFolderEntries -AdbPath $AdbPath -Serial $Serial -Folder $folder) }
            catch {
                Write-Host $script:Messages.BrowseListFailed -ForegroundColor Red
                Wait-ForMenuKey
                break
            }
            if ($entries.Count -eq 0) {
                Write-Host $script:Messages.BrowseEmpty -ForegroundColor Yellow
                Wait-ForMenuKey
            }
            $page = 0
            $pageSize = 10
            $pageCount = [Math]::Max(1, [int][Math]::Ceiling($entries.Count / $pageSize))
            $nextFolder = ''
            while ($true) {
            Clear-Host
            Write-Host (Format-Message -Name 'BrowseListing' -Values @($folder, ($page + 1), $pageCount)) -ForegroundColor Cyan
            $first = $page * $pageSize
            $visible = @($entries | Select-Object -Skip $first -First $pageSize)
            for ($index = 0; $index -lt $visible.Count; $index++) {
                Write-Host ('  [ {0} ] {1}' -f ($index + 1), $visible[$index])
            }
            $answer = (Read-Host -Prompt $script:Messages.BrowseChoose).Trim()
            if (-not $answer -or $answer -eq 'q') { return }
            if ($answer -eq 'b') {
                if ($folder -eq '/sdcard') { break }
                $parent = $folder.Substring(0, $folder.LastIndexOf('/'))
                $nextFolder = if ($parent) { $parent } else { '/sdcard' }
                break
            }
            if ($answer -eq 'g') {
                if (Confirm-MenuAction -Prompt (Format-Message -Name 'BrowseFolderConfirm' -Values @($folder))) {
                    Receive-AdbPath -AdbPath $AdbPath -Serial $Serial -RemotePath $folder
                    return
                }
                continue
            }
            if ($answer -eq 'n' -and $page -lt $pageCount - 1) { $page++; continue }
            if ($answer -eq 'p' -and $page -gt 0) { $page--; continue }
            $selection = 0
            if ([int]::TryParse($answer, [ref]$selection) -and $selection -ge 1 -and $selection -le $visible.Count) {
                $selectedPath = $folder.TrimEnd('/') + '/' + $visible[$selection - 1]
                if (Test-AdbRemoteDirectory -AdbPath $AdbPath -Serial $Serial -Path $selectedPath) {
                    $nextFolder = $selectedPath
                    break
                }
                Receive-AdbPath -AdbPath $AdbPath -Serial $Serial -RemotePath $selectedPath
                return
            }
            }
            if (-not $nextFolder) { break }
            $folder = $nextFolder
        }
    }
}

function Save-AdbBugreport {
    param([string]$AdbPath, [string]$Serial)
    Clear-Host
    Write-Host $script:Messages.BugreportTitle -ForegroundColor Cyan
    Write-Host $script:Messages.BugreportPrivacy -ForegroundColor Yellow
    if (-not (Confirm-MenuAction -Prompt (Format-Message -Name 'BugreportConfirm' -Values @($Serial)))) { return }
    $outputFolder = Get-ActiveOutputFolder
    $destination = Join-Path $outputFolder ('LeanADB-Bugreport-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $destination | Out-Null
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $report = Invoke-ToolProcess -Executable $AdbPath -Arguments @('-s',$Serial,'bugreport',$destination) -TimeoutSeconds 600
        if ($report.Output) { Write-Host $report.Output }
        $reportExitCode = $report.ExitCode
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($reportExitCode -eq 0 -and @(Get-ChildItem -LiteralPath $destination -Recurse -File).Count -gt 0) {
        Write-Host (Format-Message -Name 'BugreportSaved' -Values @($destination)) -ForegroundColor Green
        $script:LastSavedPath = $destination
        Start-Process -FilePath 'explorer.exe' -ArgumentList @('"' + $destination + '"')
    }
    else {
        Write-Host (Format-Message -Name 'BugreportFailed' -Values @($destination)) -ForegroundColor Red
    }
    Wait-ForMenuKey
}

function Show-ExtrasMenu {
    param([string]$Root, [string]$AdbPath, [string]$FastbootPath)
    while ($true) {
        Clear-Host
        Write-Host $script:Messages.MenuExtras -ForegroundColor Cyan
        Write-Host (Format-Message -Name 'OutputFolderCurrent' -Values @($script:ActiveOutputFolder))
        Write-Host ''
        Write-Host "  $($script:Messages.MenuDiagnose)"
        Write-Host "  $($script:Messages.MenuRepair)"
        Write-Host "  $($script:Messages.MenuBrowse)"
        Write-Host "  $($script:Messages.MenuBugreport)"
        Write-Host "  $($script:Messages.MenuOutput)"
        Write-Host "  $($script:Messages.MenuOfflineZip)"
        Write-Host "  $($script:Messages.MenuScreenrecord)"
        Write-Host "  $($script:Messages.HelpBack)" -ForegroundColor Yellow
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Escape' { return }
            'X' { Show-ConnectionDiagnostics -Root $Root -AdbPath $AdbPath -FastbootPath $FastbootPath -State (Read-State -Root $Root) }
            'Y' {
                & $PSCommandPath -Action Repair -InstallPath $Root
                Wait-ForMenuKey
            }
            'F' {
                $serial = Select-AdbDevice -AdbPath $AdbPath
                if ($serial) { Browse-AdbFiles -AdbPath $AdbPath -Serial $serial }
            }
            'E' {
                $serial = Select-AdbDevice -AdbPath $AdbPath
                if ($serial) { Save-AdbBugreport -AdbPath $AdbPath -Serial $serial }
            }
            'O' { Show-OutputFolderMenu -Root $Root }
            'U' {
                $zip = Select-LocalFile -Title $script:Messages.OfflineZipChoose -Filter 'ZIP archives (*.zip)|*.zip'
                if ($zip -and (Confirm-MenuAction -Prompt (Format-Message -Name 'OfflineZipConfirm' -Values @($zip)))) {
                    & $PSCommandPath -Action Update -InstallPath $Root -OfflineZipPath $zip
                    Wait-ForMenuKey
                }
            }
            'V' {
                $serial = Select-AdbDevice -AdbPath $AdbPath
                if ($serial) { Save-AdbScreenrecord -AdbPath $AdbPath -Serial $serial }
            }
        }
    }
}

function Confirm-MenuAction {
    param([string]$Prompt)
    Write-Host ''
    Write-Host $Prompt -ForegroundColor Yellow
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Enter) { return $true }
        if ($key.Key -eq [ConsoleKey]::Escape) { return $false }
    }
}

function Show-LanguageMenu {
    param([string]$Root)
    while ($true) {
        Clear-Host
        Write-Host $script:Messages.LanguageTitle -ForegroundColor Cyan
        Write-Host "  $($script:Messages.LanguageAuto)"
        Write-Host "  $($script:Messages.LanguageEnglish)"
        Write-Host "  $($script:Messages.LanguageKorean)"
        Write-Host "  $($script:Messages.HelpBack)" -ForegroundColor Yellow
        $key = [Console]::ReadKey($true)
        $preference = switch ($key.Key) {
            'A' { 'Auto' }
            'E' { 'English' }
            'K' { 'Korean' }
            'Escape' { return }
            default { $null }
        }
        if (-not $preference) { continue }
        $mutex = Enter-UpdateLock -Root $Root
        try {
            $currentState = Read-State -Root $Root
            if ($null -eq $currentState) { throw (Format-Message -Name 'NotInstalled' -Values @($Root)) }
            $currentState | Add-Member -NotePropertyName LanguagePreference -NotePropertyValue $preference -Force
            Write-State -Root $Root -State $currentState
        }
        finally {
            Exit-UpdateLock -Mutex $mutex
        }
        Set-DisplayLanguage -Preference $preference
        Write-Host $script:Messages.LanguageSaved -ForegroundColor Green
        Wait-ForMenuKey
        return
    }
}

function Start-AdbSideload {
    param([string]$AdbPath)
    $serial = Select-AdbDevice -AdbPath $AdbPath -AllowedStatuses @('sideload')
    if (-not $serial) { return }
    $package = Select-LocalFile -Title $script:Messages.SideloadChooseZip -Filter 'ZIP packages (*.zip)|*.zip'
    if (-not $package) { return }
    if (-not (Test-Path -LiteralPath $package -PathType Leaf) -or [IO.Path]::GetExtension($package) -ine '.zip') {
        throw $script:Messages.SideloadInvalidZip
    }
    Clear-Host
    $prompt = Format-Message -Name 'SideloadConfirm' -Values @([IO.Path]::GetFileName($package), $serial)
    if (-not (Confirm-MenuAction -Prompt $prompt)) {
        Write-Host $script:Messages.SideloadCancelled
        Wait-ForMenuKey
        return
    }
    [void](Invoke-MenuCommand -Executable $AdbPath -Arguments @('-s', $serial, 'sideload', $package))
}

function Show-RebootMenu {
    param([string]$AdbPath, [string]$FastbootPath)
    while ($true) {
        Clear-Host
        Write-Host $script:Messages.RebootTitle -ForegroundColor Cyan
        Write-Host "  $($script:Messages.RebootSystem)"
        Write-Host "  $($script:Messages.RebootBootloader)"
        Write-Host "  $($script:Messages.RebootFastboot)"
        Write-Host "  $($script:Messages.HelpBack)" -ForegroundColor Yellow
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Escape) { return }
        $destination = switch ($key.Key) {
            'D1' { 'system' }; 'NumPad1' { 'system' }
            'D2' { 'bootloader' }; 'NumPad2' { 'bootloader' }
            'D3' { 'fastboot' }; 'NumPad3' { 'fastboot' }
            default { $null }
        }
        if (-not $destination) { continue }
        if ($destination -eq 'fastboot') {
            $fastbootSerial = Select-FastbootDevice -FastbootPath $FastbootPath
            if (-not $fastbootSerial) { continue }
            $prompt = Format-Message -Name 'RebootConfirm' -Values @($fastbootSerial, $script:Messages.RebootDestinationSystem)
            if (-not (Confirm-MenuAction -Prompt $prompt)) { continue }
            [void](Invoke-MenuCommand -Executable $FastbootPath -Arguments @('-s', $fastbootSerial, 'reboot'))
            return
        }
        $serial = Select-AdbDevice -AdbPath $AdbPath
        if (-not $serial) { continue }
        $label = if ($destination -eq 'system') { $script:Messages.RebootDestinationSystem } else { $script:Messages.RebootDestinationBootloader }
        $prompt = Format-Message -Name 'RebootConfirm' -Values @($serial, $label)
        if (-not (Confirm-MenuAction -Prompt $prompt)) { continue }
        $arguments = @('-s', $serial, 'reboot')
        if ($destination -eq 'bootloader') { $arguments += 'bootloader' }
        [void](Invoke-MenuCommand -Executable $AdbPath -Arguments $arguments)
        return
    }
}

function Select-FastbootDevice {
    param([string]$FastbootPath)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FastbootPath devices 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    $serials = @()
    if ($exitCode -eq 0) {
        foreach ($line in $output) {
            if ([string]$line -match '^([^\s]+)\s+fastboot(?:\s|$)') { $serials += [string]$Matches[1] }
        }
    }
    if ($serials.Count -eq 0) {
        Write-Host $script:Messages.NoFastbootDevice -ForegroundColor Red
        Wait-ForMenuKey
        return $null
    }
    if ($script:PinDeviceSelection -and $script:SelectedDeviceSerial -and $script:SelectedDeviceSerial -cin $serials) { return $script:SelectedDeviceSerial }
    if ($serials.Count -eq 1) {
        $serial = [string]$serials[0]
        if ($script:PinDeviceSelection -and $script:SelectedDeviceSerial -and $serial -cne $script:SelectedDeviceSerial) {
            if (-not (Confirm-MenuAction -Prompt (Format-Message -Name 'FastbootTargetConfirm' -Values @($serial,$script:SelectedDeviceSerial)))) { return $null }
        }
        return $serial
    }
    $records = @($serials | ForEach-Object { [pscustomobject]@{Serial=$_;Model='';Status='fastboot'} })
    return Select-PagedRecord -Records $records -Title $script:Messages.ChooseDevice -State $script:MenuState
}

function Read-MenuChoice {
    $key = [Console]::ReadKey($true)
    if ($key.Key -eq [ConsoleKey]::Escape) { return 'Escape' }
    if ($key.Key -eq [ConsoleKey]::Enter) { return 'Enter' }
    return ([string]$key.KeyChar).ToUpperInvariant()
}

function Read-HomeChoice {
    param([string]$Root)
    $path = Get-StatePath -Root $Root
    $stamp = if (Test-Path -LiteralPath $path) { (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks } else { 0 }
    $nextCheck = [DateTime]::UtcNow.AddSeconds(2)
    while ($true) {
        if ([Console]::KeyAvailable) { return Read-MenuChoice }
        if ([DateTime]::UtcNow -ge $nextCheck) {
            $latest = if (Test-Path -LiteralPath $path) { (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks } else { 0 }
            if ($latest -ne $stamp) { return 'Refresh' }
            $nextCheck = [DateTime]::UtcNow.AddSeconds(2)
        }
        Start-Sleep -Milliseconds 100
    }
}

function Show-ActionError {
    param([string]$Details)
    Write-Host (Format-Message -Name 'ActionError' -Values @($Details)) -ForegroundColor Red
    Write-Host $script:Messages.CommandRetryAdvice -ForegroundColor Yellow
    Wait-ForMenuKey
}

function Open-SavedFiles {
    $folder = Get-ActiveOutputFolder
    Start-Process -FilePath 'explorer.exe' -ArgumentList @('"' + $folder + '"')
}

function Open-RecentSavedFiles {
    $folder = Get-ActiveOutputFolder
    $entries = @(Get-ChildItem -LiteralPath $folder -Filter 'LeanADB-*' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 50)
    if (-not $entries.Count) { Write-Host $script:Messages.RecentEmpty; Wait-ForMenuKey; return }
    $records = @($entries | ForEach-Object { [pscustomobject]@{ Serial = $_.Name; Model = ''; Status = '' } })
    $chosen = Select-PagedRecord -Records $records -Title $script:Messages.ActionRecent
    if ($chosen) {
        $path = Join-Path $folder $chosen
        if (Test-Path -LiteralPath $path -PathType Container) { Start-Process -FilePath 'explorer.exe' -ArgumentList @('"' + $path + '"') }
        else { Start-Process -FilePath 'explorer.exe' -ArgumentList @('/select,"' + $path + '"') }
    }
}

function Show-InstallApks {
    param([string]$AdbPath)
    $serial = Select-AdbDevice -AdbPath $AdbPath
    if (-not $serial) { return }
    $files = @(Select-LocalFile -Title $script:Messages.ChooseApks -Filter 'Android packages (*.apk)|*.apk' -Multiple)
    if (-not $files.Count) { return }
    if ($files.Count -eq 1) { Install-ApkBatch -AdbPath $AdbPath -Serial $serial -Paths $files; return }
    Clear-Host
    Write-Host (Format-Message -Name 'ApkModeTitle' -Values @($files.Count)) -ForegroundColor Cyan
    Write-Host $script:Messages.ApkModeIndependent
    Write-Host $script:Messages.ApkModeSplit
    Write-Host $script:Messages.ApkModeHint -ForegroundColor Yellow
    do { $mode = Read-MenuChoice } while ($mode -notin @('1','2','Escape'))
    if ($mode -eq 'Escape') { return }
    if ($mode -eq '1') { Install-ApkBatch -AdbPath $AdbPath -Serial $serial -Paths $files; return }
    Install-SplitApkBatch -AdbPath $AdbPath -Serial $serial -Paths $files
}

function Invoke-UiAction {
    param([string]$Name, [string]$Root, [string]$AdbPath, [string]$FastbootPath)
    switch ($Name) {
        'Connect' { Show-ConnectionGuide -Root $Root -AdbPath $AdbPath -FastbootPath $FastbootPath }
        'Choose' { [void](Select-AdbDevice -AdbPath $AdbPath -AllowedStatuses @('device','offline','unauthorized','sideload','recovery') -ChooseAnother) }
        'Alias' { Show-DeviceAliasMenu -Root $Root }
        'ActionInstall' { Show-InstallApks -AdbPath $AdbPath }
        'ActionSend' {
            $serial = Select-AdbDevice -AdbPath $AdbPath
            if ($serial) {
                $files = @(Select-LocalFile -Title $script:Messages.ChooseFiles -Filter 'All files (*.*)|*.*' -Multiple)
                if ($files.Count) { Send-FilesToDevice -AdbPath $AdbPath -Serial $serial -Paths $files }
            }
        }
        { $_ -in @('ActionBrowse','ActionReceive','ActionScreenshot','ActionRecord','ActionLogcat','ActionBugreport') } {
            $serial = Select-AdbDevice -AdbPath $AdbPath
            if (-not $serial) { return }
            switch ($Name) {
                'ActionBrowse' { Browse-AdbFiles -AdbPath $AdbPath -Serial $serial }
                'ActionReceive' { Receive-AdbPath -AdbPath $AdbPath -Serial $serial }
                'ActionScreenshot' { Save-AdbScreenshot -AdbPath $AdbPath -Serial $serial }
                'ActionRecord' { Save-AdbScreenrecord -AdbPath $AdbPath -Serial $serial }
                'ActionLogcat' { Save-AdbLogcat -AdbPath $AdbPath -Serial $serial }
                'ActionBugreport' { Save-AdbBugreport -AdbPath $AdbPath -Serial $serial }
            }
        }
        'HomeSaved' { Open-SavedFiles }
        'ActionRecent' { Open-RecentSavedFiles }
        'Retry' { Retry-LastBatch -AdbPath $AdbPath }
        'ActionInfo' { Show-DeviceInfo -AdbPath $AdbPath }
        'ActionReboot' { Show-RebootMenu -AdbPath $AdbPath -FastbootPath $FastbootPath }
        'ActionSideload' { Start-AdbSideload -AdbPath $AdbPath }
        'ActionWireless' { Show-WirelessMenu -AdbPath $AdbPath }
        'ActionFastboot' { [void](Invoke-MenuCommand -Executable $FastbootPath -Arguments @('devices')) }
        'ActionOutput' { Show-OutputFolderMenu -Root $Root }
        'ActionLanguage' { Show-LanguageMenu -Root $Root }
        'ActionInstallFolder' { Start-Process -FilePath 'explorer.exe' -ArgumentList @('"' + $Root + '"') }
        'ActionDiagnose' { Show-ConnectionDiagnostics -Root $Root -AdbPath $AdbPath -FastbootPath $FastbootPath -State (Read-State -Root $Root) }
        'ActionDriver' { Show-ConnectionHelp -Root $Root -AdbPath $AdbPath }
        'ActionUpdate' {
            & $PSCommandPath -Action Update -InstallPath $Root
            if ($LASTEXITCODE -ne 0) { throw $script:Messages.CommandRetryAdvice }
            Write-Host $script:Messages.RestartMenuHint -ForegroundColor Yellow
            Wait-ForMenuKey
        }
        'ActionRepair' {
            & $PSCommandPath -Action Repair -InstallPath $Root
            if ($LASTEXITCODE -ne 0) { throw $script:Messages.CommandRetryAdvice }
            Wait-ForMenuKey
        }
        'ActionOffline' {
            $zip = Select-LocalFile -Title $script:Messages.OfflineZipChoose -Filter 'ZIP archives (*.zip)|*.zip'
            if ($zip -and (Confirm-MenuAction -Prompt (Format-Message -Name 'OfflineZipConfirm' -Values @($zip)))) {
                & $PSCommandPath -Action Update -InstallPath $Root -OfflineZipPath $zip
                if ($LASTEXITCODE -ne 0) { throw $script:Messages.CommandRetryAdvice }
                Wait-ForMenuKey
            }
        }
        'Terminal' {
            & $PSCommandPath -Action Terminal -InstallPath $Root
            if ($LASTEXITCODE -ne 0) { throw $script:Messages.CommandRetryAdvice }
        }
    }
}

function Invoke-SafeUiAction {
    param([string]$Name, [string]$Root, [string]$AdbPath, [string]$FastbootPath)
    try { Invoke-UiAction -Name $Name -Root $Root -AdbPath $AdbPath -FastbootPath $FastbootPath }
    catch { Show-ActionError -Details $_.Exception.Message }
}

function Show-TaskGroup {
    param([string]$Group, [string]$Root, [string]$AdbPath, [string]$FastbootPath)
    $actions = switch ($Group) {
        'HomeApps' { @('ActionInstall') }
        'HomeFiles' { @('ActionSend','ActionBrowse','ActionReceive','ActionScreenshot','ActionRecord','HomeSaved','ActionRecent') }
        'HomeDevice' { @('ActionInfo','ActionReboot','ActionSideload','ActionWireless','ActionLogcat','ActionBugreport','ActionFastboot') }
        'HomeSettings' { @('ActionUpdate','ActionRepair','ActionOutput','ActionLanguage','ActionInstallFolder','ActionDiagnose','ActionDriver','ActionOffline') }
    }
    $actions = @($actions)
    while ($true) {
        Clear-Host
        Write-Host $script:Messages[$Group] -ForegroundColor Cyan
        if ($script:SelectedDeviceSerial) { Write-Host (Get-DeviceDisplayName -State $script:MenuState -Serial $script:SelectedDeviceSerial) -ForegroundColor DarkGray }
        Write-Host ''
        for ($index = 0; $index -lt $actions.Count; $index++) { Write-Host ('  [ {0} ] {1}' -f ($index+1),$script:Messages[$actions[$index]]) }
        if ($Group -in @('HomeApps','HomeFiles')) { Write-Host "  $($script:Messages.MenuRetry)" }
        Write-Host ''
        Write-Host $script:Messages.MenuBackHint -ForegroundColor Yellow
        $choice = Read-MenuChoice
        if ($choice -eq 'Escape') { return }
        if ($choice -eq 'R' -and $Group -in @('HomeApps','HomeFiles')) { Invoke-SafeUiAction -Name 'Retry' -Root $Root -AdbPath $AdbPath -FastbootPath $FastbootPath; continue }
        $number = 0
        if ([int]::TryParse($choice,[ref]$number) -and $number -ge 1 -and $number -le $actions.Count) {
            Invoke-SafeUiAction -Name $actions[$number-1] -Root $Root -AdbPath $AdbPath -FastbootPath $FastbootPath
            try {
                $latest = Read-State -Root $Root
                if ($null -ne $latest) { $script:MenuState = $latest }
            }
            catch { Show-ActionError -Details $_.Exception.Message }
        }
    }
}

function Show-LeanAdbMenu {
    param([string]$Root, [object]$State)
    if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) { throw 'The LeanADB menu requires an interactive console.' }
    $adb = Join-Path $Root 'bin\adb.exe'; $fastboot = Join-Path $Root 'bin\fastboot.exe'
    foreach ($tool in @($adb,$fastboot)) { if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Required tool was not found: $tool" } }
    $script:PinDeviceSelection = $true; $script:MenuInstallRoot = $Root; $script:MenuState = $State
    $items = @('HomeConnect','HomeApps','HomeFiles','HomeDevice','HomeTerminal','HomeSettings','HomeSaved')
    $shortcuts = @{ C='Choose'; A='Alias'; S='ActionScreenshot'; W='ActionWireless'; R='ActionReceive'; L='ActionLogcat'; H='ActionDriver'; I='ActionSideload'; B='ActionReboot'; G='ActionLanguage'; D='ActionInfo' }
    while ($true) {
        $refreshError = ''
        try { $latest = Read-State -Root $Root; if ($null -ne $latest) { $script:MenuState = $latest } }
        catch { $refreshError = $_.Exception.Message }
        $State = $script:MenuState
        $script:ActiveOutputFolder = Get-OutputFolder -Root $Root -State $State
        Clear-Host
        Write-Host '=================== LeanADB ===================' -ForegroundColor Cyan
        Write-Host ('by leodroid99  |  ' + (Format-Message -Name 'MenuVersion' -Values @($State.LeanADBVersion,$State.InstalledVersion))) -ForegroundColor DarkGray
        if ($refreshError) { Write-Host $refreshError -ForegroundColor Yellow; Write-Host $script:Messages.RepairMenuHint -ForegroundColor Yellow }
        if ($script:SelectedDeviceSerial) {
            $records = @(Get-AdbDeviceRecords -AdbPath $adb | Where-Object { $_.Serial -ceq $script:SelectedDeviceSerial } | Select-Object -First 1)
            $name = Get-DeviceDisplayName -State $State -Serial $script:SelectedDeviceSerial
            if ($records.Count) { Write-Host (Format-Message -Name 'MenuTargetSelected' -Values @($name,(Get-LocalizedDeviceStatus -Status $records[0].Status))) -ForegroundColor Cyan }
            else { Write-Host (Format-Message -Name 'MenuTargetUnavailable' -Values @($name)) -ForegroundColor Yellow }
        }
        else {
            Write-Host $script:Messages.MenuTargetNone -ForegroundColor DarkGray
            if (@($State.RecentDevices).Count) { Write-Host (Format-Message -Name 'MenuRecentDevice' -Values @((Get-DeviceDisplayName -State $State -Serial $State.RecentDevices[0]))) -ForegroundColor DarkGray }
        }
        Write-Host (Format-Message -Name 'OutputFolderCurrent' -Values @($script:ActiveOutputFolder)) -ForegroundColor DarkGray
        if ($State.UpdateAvailable -or $State.ProductUpdateAvailable) { Write-Host $script:Messages.UpdateReady -ForegroundColor Yellow }
        if (-not $State.PackageComparisonKnown) { Write-Host $script:Messages.OfflineZipStatus -ForegroundColor DarkGray }
        if ($State.LastCheckStatus -eq 'Failed' -or ($null -ne $State.PSObject.Properties['ProductCheckStatus'] -and $State.ProductCheckStatus -eq 'Failed')) { Write-Host $script:Messages.CheckFailedHint -ForegroundColor Yellow }
        Write-Host ''
        for ($index = 0; $index -lt $items.Count; $index++) { Write-Host ('  [ {0} ] {1}' -f ($index+1),$script:Messages[$items[$index]]) }
        Write-Host ''
        Write-Host $script:Messages.HomeShortcuts -ForegroundColor Yellow
        $choice = Read-HomeChoice -Root $Root
        switch ($choice) {
            { $_ -in @('Q','Escape') } { return }
            'Refresh' { continue }
            '1' { Invoke-SafeUiAction -Name 'Connect' -Root $Root -AdbPath $adb -FastbootPath $fastboot }
            '2' { Show-TaskGroup -Group 'HomeApps' -Root $Root -AdbPath $adb -FastbootPath $fastboot }
            '3' { Show-TaskGroup -Group 'HomeFiles' -Root $Root -AdbPath $adb -FastbootPath $fastboot }
            '4' { Show-TaskGroup -Group 'HomeDevice' -Root $Root -AdbPath $adb -FastbootPath $fastboot }
            '5' { Invoke-SafeUiAction -Name 'Terminal' -Root $Root -AdbPath $adb -FastbootPath $fastboot }
            '6' { Show-TaskGroup -Group 'HomeSettings' -Root $Root -AdbPath $adb -FastbootPath $fastboot }
            '7' { Invoke-SafeUiAction -Name 'HomeSaved' -Root $Root -AdbPath $adb -FastbootPath $fastboot }
            'T' { Show-TaskGroup -Group 'HomeFiles' -Root $Root -AdbPath $adb -FastbootPath $fastboot }
            default { if ($shortcuts.ContainsKey($choice)) { Invoke-SafeUiAction -Name $shortcuts[$choice] -Root $Root -AdbPath $adb -FastbootPath $fastboot } }
        }
    }
}

function Get-PlatformToolsVersion {
    param([string]$PlatformToolsPath)
    $propertiesPath = Join-Path $PlatformToolsPath 'source.properties'
    $line = Get-Content -LiteralPath $propertiesPath | Where-Object { $_ -match '^Pkg\.Revision=' } | Select-Object -First 1
    if (-not $line) {
        throw 'source.properties does not contain Pkg.Revision.'
    }
    return ($line -split '=', 2)[1].Trim()
}

function Get-ValidatedInstalledPlatformToolsVersion {
    param([string]$Root)
    $binPath = Join-Path $Root 'bin'
    foreach ($name in $script:RequiredFiles) {
        $candidate = Join-Path $binPath $name
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "LeanADB repair cannot find required Platform-Tools file: $name"
        }
    }
    Assert-GoogleSignature -FilePath (Join-Path $binPath 'adb.exe')
    Assert-GoogleSignature -FilePath (Join-Path $binPath 'fastboot.exe')
    $version = Get-PlatformToolsVersion -PlatformToolsPath $binPath
    $adbOutput = (& (Join-Path $binPath 'adb.exe') version 2>&1 | Out-String)
    $adbExitCode = $LASTEXITCODE
    $fastbootOutput = (& (Join-Path $binPath 'fastboot.exe') --version 2>&1 | Out-String)
    $fastbootExitCode = $LASTEXITCODE
    if ($adbExitCode -ne 0 -or $fastbootExitCode -ne 0 -or
        $adbOutput -notmatch [regex]::Escape($version) -or $fastbootOutput -notmatch [regex]::Escape($version)) {
        throw "Installed executable versions do not match Platform-Tools revision $version."
    }
    return $version
}

function Test-UserPathEntry {
    param([string]$BinPath)
    $target = [IO.Path]::GetFullPath($BinPath).TrimEnd('\\')
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) { return $false }
    foreach ($entry in @($current -split ';')) {
        if (-not $entry) { continue }
        try {
            $expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"'))
            if ([IO.Path]::GetFullPath($expanded).TrimEnd('\\') -ieq $target) { return $true }
        }
        catch { }
    }
    return $false
}

function Test-StartMenuShortcutForRoot {
    param([string]$Root)
    $shortcutPath = Get-ShortcutPath
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { return $false }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $target = [IO.Path]::GetFullPath([string]$shortcut.TargetPath)
        $expected = [IO.Path]::GetFullPath((Join-Path $Root 'Open LeanADB.cmd'))
        return $target -ieq $expected
    }
    catch { return $false }
}

function New-RecoveredState {
    param([string]$Root)
    $binPath = Join-Path $Root 'bin'
    $platformVersion = Get-ValidatedInstalledPlatformToolsVersion -Root $Root
    $productSignature = Get-AuthenticodeSignature -LiteralPath (Join-Path $Root 'LeanADB.ps1')
    $pathRegistered = Test-UserPathEntry -BinPath $binPath
    $shortcutRegistered = Test-StartMenuShortcutForRoot -Root $Root
    return [pscustomobject][ordered]@{
        ProductId = $script:ProductId
        Publisher = 'leodroid99'
        LeanADBVersion = $script:ProductVersion
        InstalledVersion = $platformVersion
        InstalledAtUtc = ''
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
        LastCheckUtc = ''
        SourceUrl = $script:SourceUrl
        ETag = ''
        LastModified = ''
        ContentLength = ''
        ZipSha256 = ''
        LayoutVersion = 1
        LastCheckStatus = 'Recovered'
        PackageComparisonKnown = $false
        StateSchemaVersion = 2
        UpdateAvailable = $false
        PathRegistered = $pathRegistered
        ShortcutRegistered = $shortcutRegistered
        UninstallRegistered = ($pathRegistered -or $shortcutRegistered)
        LicenseAcceptedUtc = ''
        LicenseUrl = $script:LicenseUrl
        ProductManifestUrl = $script:ProductManifestUrl
        UsbBackend = 'Standard'
        LanguagePreference = 'Auto'
        OutputFolder = ''
        DeviceAliases = @()
        RecentDevices = @()
        ProductUpdateAvailable = $false
        ProductSigned = ($productSignature.Status -eq 'Valid')
        ProductSignerSubject = if ($productSignature.Status -eq 'Valid') { [string]$productSignature.SignerCertificate.Subject } else { '' }
    }
}

function Assert-GoogleSignature {
    param([string]$FilePath)
    $signature = Get-AuthenticodeSignature -LiteralPath $FilePath
    if ($signature.Status -ne 'Valid') {
        throw "Invalid Authenticode signature: $FilePath ($($signature.Status))"
    }
    if ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Google LLC(,|$)') {
        throw "Unexpected signer for $FilePath"
    }
}

function Stop-AdbServer {
    param([string]$AdbPath)
    if (-not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) {
        return
    }
    try {
        [void](Invoke-ToolProcess -Executable $AdbPath -Arguments @('kill-server') -TimeoutSeconds 15 -QuietProgress)
    }
    catch {
        # No running server is a valid state during update and uninstall.
    }
}

function Assert-ArchiveSafety {
    param([string]$ZipPath)
    if ((Get-Item -LiteralPath $ZipPath).Length -gt 128MB) {
        throw 'Platform-Tools ZIP is larger than the supported 128 MB limit.'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        if ($archive.Entries.Count -gt 512) { throw 'Platform-Tools ZIP contains too many entries.' }
        [long]$totalBytes = 0
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $archive.Entries) {
            $name = [string]$entry.FullName
            if ($name -notmatch '^platform-tools/' -or $name -match '[\\:]|(^|/)\.\.(/|$)|(^|/)\.(/|$)|^/' -or
                -not $seen.Add($name)) {
                throw "Unsafe or duplicate ZIP entry: $name"
            }
            $totalBytes += [long]$entry.Length
            if ($totalBytes -gt 512MB) { throw 'Platform-Tools ZIP expands beyond the supported 512 MB limit.' }
        }
    }
    finally { $archive.Dispose() }
}

function Expand-AndValidatePackage {
    param(
        [string]$ZipPath,
        [string]$WorkRoot
    )
    Assert-ArchiveSafety -ZipPath $ZipPath
    $extractRoot = Join-Path $WorkRoot 'extracted'
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractRoot -Force
    $platformTools = Join-Path $extractRoot 'platform-tools'

    foreach ($name in $script:RequiredFiles) {
        $candidate = Join-Path $platformTools $name
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Official package is missing required file: $name"
        }
    }

    Assert-GoogleSignature -FilePath (Join-Path $platformTools 'adb.exe')
    Assert-GoogleSignature -FilePath (Join-Path $platformTools 'fastboot.exe')

    $version = Get-PlatformToolsVersion -PlatformToolsPath $platformTools
    $adbOutput = (& (Join-Path $platformTools 'adb.exe') version 2>&1 | Out-String)
    $fastbootOutput = (& (Join-Path $platformTools 'fastboot.exe') --version 2>&1 | Out-String)
    if ($adbOutput -notmatch [regex]::Escape($version) -or $fastbootOutput -notmatch [regex]::Escape($version)) {
        throw "Executable versions do not match package revision $version."
    }

    return [pscustomobject]@{
        Path    = $platformTools
        Version = $version
    }
}

function Set-UserPathEntry {
    param(
        [string]$BinPath,
        [bool]$Present
    )
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if ($current) {
        $entries = @($current -split ';' | Where-Object { $_ -and $_.Trim() })
    }
    $target = $BinPath.TrimEnd('\')
    $filtered = @()
    foreach ($entry in $entries) {
        $normalizedEntry = $entry.Trim().Trim('"').TrimEnd('\')
        if ($normalizedEntry -ieq $target) {
            continue
        }
        if ($Present -and [IO.Path]::GetFileName($normalizedEntry) -ieq 'bin') {
            $candidateRoot = Split-Path -Parent $normalizedEntry
            try {
                if ($null -ne (Read-State -Root $candidateRoot)) {
                    continue
                }
            }
            catch {
                # Preserve an entry if ownership cannot be proven.
            }
        }
        $filtered += $entry
    }
    if ($Present) {
        $filtered = @($target) + $filtered
    }
    [Environment]::SetEnvironmentVariable('Path', ($filtered -join ';'), 'User')
    try {
        if (-not ('LeanADB.NativeMethods' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace LeanADB {
    public static class NativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
            uint flags, uint timeout, out UIntPtr result);
    }
}
'@
        }
        $broadcast = [IntPtr]0xffff
        $result = [UIntPtr]::Zero
        [void][LeanADB.NativeMethods]::SendMessageTimeout(
            $broadcast, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    }
    catch {
        # PATH is already stored; failure to notify existing processes is non-fatal.
    }
}

function Get-RegisteredAdbPath {
    $entries = @()
    foreach ($scope in @('Machine', 'User')) {
        $value = [Environment]::GetEnvironmentVariable('Path', $scope)
        if ($value) {
            $entries += @($value -split ';' | Where-Object { $_ -and $_.Trim() })
        }
    }
    foreach ($entry in $entries) {
        try {
            $directory = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"'))
            $candidate = Join-Path $directory 'adb.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return [System.IO.Path]::GetFullPath($candidate)
            }
        }
        catch {
            # Ignore malformed entries owned by other applications.
        }
    }
    return $null
}

function Enter-UpdateLock {
    param([string]$Root)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant())
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $id = ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').Substring(0, 20)
    }
    finally {
        $hash.Dispose()
    }
    $mutex = New-Object Threading.Mutex($false, "Local\LeanADB-$id")
    try {
        $acquired = $mutex.WaitOne(0)
    }
    catch [Threading.AbandonedMutexException] {
        $acquired = $true
    }
    if (-not $acquired) {
        $mutex.Dispose()
        throw $script:Messages.UpdateBusy
    }
    return $mutex
}

function Exit-UpdateLock {
    param([Threading.Mutex]$Mutex)
    if ($null -ne $Mutex) {
        try { $Mutex.ReleaseMutex() } catch { }
        $Mutex.Dispose()
    }
}

function Set-UninstallRegistration {
    param(
        [string]$Root,
        [bool]$Present,
        [string]$DisplayVersion = $script:ProductVersion
    )
    $keyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\LeanADB'
    if (-not $Present) {
        if (Test-Path -LiteralPath $keyPath) {
            $registered = Get-ItemProperty -LiteralPath $keyPath -ErrorAction SilentlyContinue
            if ($null -ne $registered -and [string]$registered.InstallLocation -ieq $Root) {
                Remove-Item -LiteralPath $keyPath -Recurse -Force
            }
        }
        return
    }
    New-Item -Path $keyPath -Force | Out-Null
    $uninstallPath = Join-Path $Root 'Uninstall LeanADB.cmd'
    New-ItemProperty -Path $keyPath -Name DisplayName -Value 'LeanADB' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name DisplayVersion -Value $DisplayVersion -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name Publisher -Value 'leodroid99' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name InstallLocation -Value $Root -PropertyType String -Force | Out-Null
    $uninstallCommand = ('"{0}" /d /c ""{1}""' -f $env:ComSpec, $uninstallPath)
    New-ItemProperty -Path $keyPath -Name UninstallString -Value $uninstallCommand -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
}

function Write-Launchers {
    param([string]$Root)
    $menu = @'
@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PSModulePath="
title LeanADB Easy Menu
start "" /b powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action AutoUpdate -InstallPath "%~dp0." -Quiet
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action Menu -InstallPath "%~dp0."
set "LEANADB_EXIT_CODE=%ERRORLEVEL%"
if not "%LEANADB_EXIT_CODE%"=="0" pause
exit /b %LEANADB_EXIT_CODE%
'@
    $terminal = @'
@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PSModulePath="
start "" /b powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action AutoUpdate -InstallPath "%~dp0." -Quiet
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action Terminal -InstallPath "%~dp0."
set "LEANADB_EXIT_CODE=%ERRORLEVEL%"
if not "%LEANADB_EXIT_CODE%"=="0" pause
exit /b %LEANADB_EXIT_CODE%
'@
    $update = @'
@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PSModulePath="
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action Update -InstallPath "%~dp0."
set "LEANADB_EXIT_CODE=%ERRORLEVEL%"
if not "%LEANADB_EXIT_CODE%"=="0" pause
exit /b %LEANADB_EXIT_CODE%
'@
    $repair = @'
@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PSModulePath="
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action Repair -InstallPath "%~dp0."
set "LEANADB_EXIT_CODE=%ERRORLEVEL%"
if not "%LEANADB_EXIT_CODE%"=="0" pause
exit /b %LEANADB_EXIT_CODE%
'@
    $uninstall = @'
@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PSModulePath="
if /I "%~1"=="/quiet" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action Uninstall -InstallPath "%~dp0." -Quiet
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeanADB.ps1" -Action Uninstall -InstallPath "%~dp0." -ConfirmUninstall
)
set "LEANADB_EXIT_CODE=%ERRORLEVEL%"
exit /b %LEANADB_EXIT_CODE%
'@
    $drop = @'
@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PSModulePath="
title LeanADB Drag and Drop
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeanADB-Drop.ps1" %*
set "LEANADB_EXIT_CODE=%ERRORLEVEL%"
if not "%LEANADB_EXIT_CODE%"=="0" pause
exit /b %LEANADB_EXIT_CODE%
'@
    $dropBridge = @'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $root 'LeanADB.ps1') -Action Drop -InstallPath $root -DroppedPaths @($args)
if ($LASTEXITCODE) { exit $LASTEXITCODE }
'@
    Set-Content -LiteralPath (Join-Path $Root 'Open LeanADB.cmd') -Value $menu -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'Open LeanADB Terminal.cmd') -Value $terminal -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'Update LeanADB.cmd') -Value $update -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'Repair LeanADB.cmd') -Value $repair -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'Uninstall LeanADB.cmd') -Value $uninstall -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'Drop files on LeanADB.cmd') -Value $drop -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'LeanADB-Drop.ps1') -Value $dropBridge -Encoding ASCII
    $obsoleteHereLauncher = Join-Path $Root 'Open LeanADB Here.cmd'
    if (Test-Path -LiteralPath $obsoleteHereLauncher -PathType Leaf) {
        Remove-Item -LiteralPath $obsoleteHereLauncher -Force
    }
}

function Copy-LocalizationFiles {
    param([string]$Root)
    $sourceDirectory = Join-Path $PSScriptRoot 'locales'
    $destinationDirectory = Join-Path $Root 'locales'
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        return
    }
    if ((Get-NormalizedInstallPath -Path $sourceDirectory) -ieq (Get-NormalizedInstallPath -Path $destinationDirectory)) {
        return
    }
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceDirectory '*') -Destination $destinationDirectory -Recurse -Force
}

function Copy-ProductFiles {
    param([string]$Root)
    if ($PSCommandPath -and ((Get-NormalizedInstallPath -Path (Split-Path -Parent $PSCommandPath)) -ine $Root)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $Root 'LeanADB.ps1') -Force
    }
    $sourceVersion = Join-Path $PSScriptRoot 'VERSION'
    $destinationVersion = Join-Path $Root 'VERSION'
    if ((Test-Path -LiteralPath $sourceVersion -PathType Leaf) -and
        ([System.IO.Path]::GetFullPath($sourceVersion) -ine [System.IO.Path]::GetFullPath($destinationVersion))) {
        Copy-Item -LiteralPath $sourceVersion -Destination $destinationVersion -Force
    }
    $sourceUpdateUrl = Join-Path $PSScriptRoot 'UPDATE_URL'
    $destinationUpdateUrl = Join-Path $Root 'UPDATE_URL'
    if ((Test-Path -LiteralPath $sourceUpdateUrl -PathType Leaf) -and
        ([IO.Path]::GetFullPath($sourceUpdateUrl) -ine [IO.Path]::GetFullPath($destinationUpdateUrl))) {
        Copy-Item -LiteralPath $sourceUpdateUrl -Destination $destinationUpdateUrl -Force
    }
    Copy-LocalizationFiles -Root $Root
}

function Get-ShortcutPath {
    $programs = [Environment]::GetFolderPath('Programs')
    return Join-Path (Join-Path $programs 'LeanADB') 'LeanADB.lnk'
}

function Set-StartMenuShortcut {
    param(
        [string]$Root,
        [bool]$Present
    )
    $shortcutPath = Get-ShortcutPath
    $shortcutDirectory = Split-Path -Parent $shortcutPath
    if (-not $Present) {
        if (Test-Path -LiteralPath $shortcutDirectory) {
            foreach ($name in @('LeanADB.lnk', 'LeanADB Terminal.lnk')) {
                $candidate = Join-Path $shortcutDirectory $name
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    Remove-Item -LiteralPath $candidate -Force
                }
            }
            if (@(Get-ChildItem -LiteralPath $shortcutDirectory -Force).Count -eq 0) {
                Remove-Item -LiteralPath $shortcutDirectory -Force
            }
        }
        return
    }

    New-Item -ItemType Directory -Path $shortcutDirectory -Force | Out-Null
    $oldShortcutPath = Join-Path $shortcutDirectory 'LeanADB Terminal.lnk'
    if (Test-Path -LiteralPath $oldShortcutPath -PathType Leaf) {
        Remove-Item -LiteralPath $oldShortcutPath -Force
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $Root 'Open LeanADB.cmd'
    $shortcut.WorkingDirectory = $Root
    $shortcut.Description = 'LeanADB by leodroid99 - easy ADB and Fastboot menu'
    $shortcut.Save()
}

function Install-Package {
    param(
        [string]$Root,
        [object]$RemoteMetadata,
        [bool]$RegisterPath,
        [bool]$RegisterShortcut,
        [object]$ExistingState,
        [string]$LocalZipPath = ''
    )
    Assert-FreeDiskSpace -Path ([System.IO.Path]::GetTempPath())
    Assert-FreeDiskSpace -Path $Root
    $workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('LeanADB-' + [guid]::NewGuid().ToString('N'))
    $updateMutex = Enter-UpdateLock -Root $Root
    $snapshot = $null
    $newBin = ''; $oldBin = ''; $binSwapped = $false; $hadOldBin = $false
    $preserveBackup = $false
    $committed = $false
    try {
        $ExistingState = Read-State -Root $Root
        if ($null -ne $ExistingState -and $null -ne $ExistingState.PSObject.Properties['PendingRemovalId'] -and $ExistingState.PendingRemovalId) { throw $script:Messages.RemovalPending }
        New-Item -ItemType Directory -Path $workRoot | Out-Null
        $snapshot = New-InstallSnapshot -Root $Root -BackupRoot (Join-Path $workRoot 'snapshot') -Integration:($RegisterPath -or $RegisterShortcut)
        $zipPath = Join-Path $workRoot 'platform-tools.zip'
        if ($LocalZipPath) {
            Copy-Item -LiteralPath $LocalZipPath -Destination $zipPath -ErrorAction Stop
        }
        else {
            Write-Info $script:Messages.Downloading
            Invoke-WebRequest -Uri $script:SourceUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec $script:DownloadTimeoutSeconds
        }
        $zipHash = Get-Sha256Hash -FilePath $zipPath
        $package = Expand-AndValidatePackage -ZipPath $zipPath -WorkRoot $workRoot
        if ($LocalZipPath -and $null -ne $ExistingState -and $ExistingState.InstalledVersion) {
            $candidateVersion = [version]$package.Version
            $installedVersion = [version][string]$ExistingState.InstalledVersion
            if ($candidateVersion -lt $installedVersion) {
                throw (Format-Message -Name 'OfflineZipOlder' -Values @($package.Version, $ExistingState.InstalledVersion))
            }
        }

        if (-not (Test-Path -LiteralPath $Root)) {
            New-Item -ItemType Directory -Path $Root | Out-Null
        }

        $newBin = Join-Path $Root ('.bin-new-' + [guid]::NewGuid().ToString('N'))
        $oldBin = Join-Path $Root ('.bin-old-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $newBin | Out-Null
        foreach ($name in $script:RequiredFiles) {
            Copy-Item -LiteralPath (Join-Path $package.Path $name) -Destination $newBin
        }

        $binPath = Join-Path $Root 'bin'
        $hadOldBin = Test-Path -LiteralPath $binPath
        try {
            if ($hadOldBin) {
                Stop-AdbServer -AdbPath (Join-Path $binPath 'adb.exe')
                Move-Item -LiteralPath $binPath -Destination $oldBin
            }
            Move-Item -LiteralPath $newBin -Destination $binPath
            $binSwapped = $true
        }
        catch {
            if ((-not (Test-Path -LiteralPath $binPath)) -and (Test-Path -LiteralPath $oldBin)) {
                Move-Item -LiteralPath $oldBin -Destination $binPath
            }
            throw
        }

        Copy-ProductFiles -Root $Root
        Write-Launchers -Root $Root

        if ($RegisterPath) {
            Set-UserPathEntry -BinPath $Root -Present $false
            Set-UserPathEntry -BinPath $binPath -Present $true
        }
        if ($RegisterShortcut) {
            Set-StartMenuShortcut -Root $Root -Present $true
        }
        $registerUninstall = $RegisterPath -or $RegisterShortcut
        if ($registerUninstall) {
            Set-UninstallRegistration -Root $Root -Present $true
        }

        $installedAtUtc = [DateTime]::UtcNow.ToString('o')
        if ($null -ne $ExistingState -and $ExistingState.InstalledAtUtc) {
            $installedAtUtc = [string]$ExistingState.InstalledAtUtc
        }
        $deviceAliases = @()
        $recentDevices = @()
        if ($null -ne $ExistingState) {
            if ($null -ne $ExistingState.PSObject.Properties['DeviceAliases']) { $deviceAliases = @($ExistingState.DeviceAliases) }
            if ($null -ne $ExistingState.PSObject.Properties['RecentDevices']) { $recentDevices = @($ExistingState.RecentDevices) }
        }
        $productSignature = Get-AuthenticodeSignature -LiteralPath (Join-Path $Root 'LeanADB.ps1')

        $state = [ordered]@{
            ProductId          = $script:ProductId
            Publisher          = 'leodroid99'
            LeanADBVersion     = $script:ProductVersion
            InstalledVersion   = $package.Version
            InstalledAtUtc     = $installedAtUtc
            UpdatedAtUtc       = [DateTime]::UtcNow.ToString('o')
            LastCheckUtc       = if ($LocalZipPath) { '' } else { [DateTime]::UtcNow.ToString('o') }
            SourceUrl          = $script:SourceUrl
            ETag               = if ($LocalZipPath) { '' } else { $RemoteMetadata.ETag }
            LastModified       = if ($LocalZipPath) { '' } else { $RemoteMetadata.LastModified }
            ContentLength      = if ($LocalZipPath) { '' } else { $RemoteMetadata.ContentLength }
            ZipSha256          = $zipHash
            LayoutVersion      = 1
            LastCheckStatus    = if ($LocalZipPath) { 'Offline' } else { 'Success' }
            PackageComparisonKnown = (-not $LocalZipPath -and $null -ne $RemoteMetadata -and [bool]($RemoteMetadata.ETag -or $RemoteMetadata.LastModified))
            StateSchemaVersion = 2
            UpdateAvailable    = $false
            PathRegistered     = $RegisterPath
            ShortcutRegistered = $RegisterShortcut
            UninstallRegistered = $registerUninstall
            LicenseAcceptedUtc = if ($null -ne $ExistingState -and $null -ne $ExistingState.PSObject.Properties['LicenseAcceptedUtc']) { [string]$ExistingState.LicenseAcceptedUtc } else { [DateTime]::UtcNow.ToString('o') }
            LicenseUrl         = $script:LicenseUrl
            ProductManifestUrl = $script:ProductManifestUrl
            UsbBackend = if ($null -ne $ExistingState -and $null -ne $ExistingState.PSObject.Properties['UsbBackend'] -and $ExistingState.UsbBackend -eq 'Legacy') { 'Legacy' } else { 'Standard' }
            LanguagePreference = if ($Language -ne 'Auto') { $Language } elseif ($null -ne $ExistingState -and $null -ne $ExistingState.PSObject.Properties['LanguagePreference']) { [string]$ExistingState.LanguagePreference } else { 'Auto' }
            OutputFolder = if ($null -ne $ExistingState -and $null -ne $ExistingState.PSObject.Properties['OutputFolder']) { [string]$ExistingState.OutputFolder } else { '' }
            DeviceAliases = $deviceAliases
            RecentDevices = $recentDevices
            ProductUpdateAvailable = $false
            ProductSigned       = ($productSignature.Status -eq 'Valid')
            ProductSignerSubject = if ($productSignature.Status -eq 'Valid') { [string]$productSignature.SignerCertificate.Subject } else { '' }
        }
        Write-State -Root $Root -State $state
        $committed = $true
        if (Test-Path -LiteralPath $oldBin) {
            try { Remove-Item -LiteralPath $oldBin -Recurse -Force }
            catch { Write-Warning "Updated successfully; old tools could not be removed: $oldBin" }
        }
        Write-Info (Format-Message -Name 'InstalledVersion' -Values @($package.Version))
        Write-Info (Format-Message -Name 'InstallationFolder' -Values @($Root))
        if ($RegisterPath) {
            $resolvedAdb = Get-RegisteredAdbPath
            $expectedAdb = Join-Path $binPath 'adb.exe'
            if ($resolvedAdb -and $resolvedAdb -ine $expectedAdb) {
                Write-Warning (Format-Message -Name 'PathConflict' -Values @($resolvedAdb))
            }
        }
        return $state
    }
    catch {
        $originalError = $_
        if ($committed) { throw $originalError }
        try {
            if ($binSwapped) {
                if (Test-Path -LiteralPath (Join-Path $Root 'bin')) { Remove-Item -LiteralPath (Join-Path $Root 'bin') -Recurse -Force }
                if ($hadOldBin -and (Test-Path -LiteralPath $oldBin)) { Move-Item -LiteralPath $oldBin -Destination (Join-Path $Root 'bin') }
            }
            if ($null -ne $snapshot) { Restore-InstallSnapshot -Root $Root -Snapshot $snapshot }
        }
        catch { $preserveBackup = $true; throw "Installation failed: $($originalError.Exception.Message) $($_.Exception.Message) Backup: $workRoot; previous tools: $oldBin" }
        throw $originalError
    }
    finally {
        try {
            if ($newBin -and (Test-Path -LiteralPath $newBin)) { Remove-Item -LiteralPath $newBin -Recurse -Force }
            if (-not $preserveBackup -and (Test-Path -LiteralPath $workRoot)) {
                try { Remove-Item -LiteralPath $workRoot -Recurse -Force }
                catch { if (-not $committed) { throw }; Write-Warning "Installation succeeded; temporary files remain at $workRoot" }
            }
        }
        finally {
            Exit-UpdateLock -Mutex $updateMutex
        }
    }
}

function Convert-ToBinLayout {
    param(
        [string]$Root,
        [object]$State
    )
    $binPath = Join-Path $Root 'bin'
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'adb.exe') -PathType Leaf)) {
        return $State
    }

    Write-Info 'Organizing ADB and Fastboot in the LeanADB bin folder...'
    Stop-AdbServer -AdbPath (Join-Path $Root 'adb.exe')
    if (-not (Test-Path -LiteralPath $binPath)) {
        New-Item -ItemType Directory -Path $binPath | Out-Null
    }
    foreach ($name in $script:RequiredFiles) {
        $flatFile = Join-Path $Root $name
        $binFile = Join-Path $binPath $name
        if (Test-Path -LiteralPath $flatFile -PathType Leaf) {
            if (Test-Path -LiteralPath $binFile -PathType Leaf) {
                Remove-Item -LiteralPath $binFile -Force
            }
            Move-Item -LiteralPath $flatFile -Destination $binFile
        }
    }
    if ([bool]$State.PathRegistered) {
        Set-UserPathEntry -BinPath $Root -Present $false
        Set-UserPathEntry -BinPath $binPath -Present $true
    }
    $State | Add-Member -NotePropertyName LayoutVersion -NotePropertyValue 1 -Force
    Write-State -Root $Root -State $State
    return $State
}

function Get-UpdateChecks {
    $result = [pscustomobject]@{ Remote = $null; Manifest = $null; ToolsStatus = 'Failed'; ProductStatus = 'NotConfigured'; ToolsError = ''; ProductError = '' }
    try { $result.Remote = Get-RemoteMetadata; $result.ToolsStatus = 'Success' }
    catch { $result.ToolsError = $_.Exception.Message }
    if ($script:ProductManifestUrl) {
        try { $result.Manifest = Get-ProductManifest -ManifestUrl $script:ProductManifestUrl; $result.ProductStatus = 'Success' }
        catch { $result.ProductStatus = 'Failed'; $result.ProductError = $_.Exception.Message }
    }
    return $result
}

function Test-CheckDue {
    param([object]$State)
    if ($Force) {
        return $true
    }
    try {
        $lastCheck = [DateTime]::Parse([string]$State.LastCheckUtc).ToUniversalTime()
        $interval = $script:CheckIntervalHours
        if ($State.LastCheckStatus -eq 'Failed' -or ($null -ne $State.PSObject.Properties['ProductCheckStatus'] -and $State.ProductCheckStatus -eq 'Failed')) {
            $interval = $script:FailedCheckBackoffHours
        }
        return ([DateTime]::UtcNow - $lastCheck).TotalHours -ge $interval
    }
    catch {
        return $true
    }
}

function Test-RemoteChanged {
    param(
        [object]$State,
        [object]$RemoteMetadata
    )
    if ($Force) {
        return $true
    }
    if ($RemoteMetadata.ETag -and $State.ETag) {
        return $RemoteMetadata.ETag -ne [string]$State.ETag
    }
    if ($RemoteMetadata.LastModified -and $State.LastModified) {
        return $RemoteMetadata.LastModified -ne [string]$State.LastModified
    }
    if ($RemoteMetadata.ContentLength -and $State.ContentLength) {
        return $RemoteMetadata.ContentLength -ne [string]$State.ContentLength
    }
    return $true
}

function Assert-SafeUninstallPath {
    param([string]$Root)
    $state = Read-State -Root $Root
    if ($null -eq $state -or $state.ProductId -ne $script:ProductId) {
        throw 'Refusing to uninstall: a valid LeanADB state file was not found.'
    }
    $rootPath = [System.IO.Path]::GetPathRoot($Root).TrimEnd('\')
    $forbidden = @(
        $rootPath,
        (Get-NormalizedInstallPath -Path $env:USERPROFILE),
        (Get-NormalizedInstallPath -Path $env:LOCALAPPDATA)
    )
    if ($forbidden -contains $Root) {
        throw "Refusing to remove unsafe path: $Root"
    }
    return $state
}

function Confirm-LeanAdbUninstall {
    if (-not $ConfirmUninstall -or $Quiet) {
        return $true
    }
    Clear-Host
    Write-Host ''
    Write-Host '=======================================================================' -ForegroundColor Cyan
    Write-Host ("                         " + $script:Messages.UninstallTitle) -ForegroundColor Yellow
    Write-Host '=======================================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "  $($script:Messages.UninstallConfirm)" -ForegroundColor Red
    Write-Host ''
    Write-Host "  $($script:Messages.UninstallKeep)" -ForegroundColor Green
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Enter) {
            return $true
        }
        if ($key.Key -eq [ConsoleKey]::Escape) {
            Write-Info $script:Messages.UninstallCancelled
            return $false
        }
    }
}

function Start-DeferredRemoval {
    param([string]$Root, [string]$RemovalId)
    $escapedRoot = $Root.Replace("'", "''")
    $rootBytes = [Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant())
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $lockId = ([BitConverter]::ToString($hash.ComputeHash($rootBytes))).Replace('-', '').Substring(0,20) }
    finally { $hash.Dispose() }
    $cleanupCommand = @"
Start-Sleep -Milliseconds 1000
`$target = '$escapedRoot'
`$lastError = ''
`$mutex = New-Object Threading.Mutex(`$false, 'Local\LeanADB-$lockId')
`$acquired = `$false
try {
try { `$acquired = `$mutex.WaitOne(30000) } catch [Threading.AbandonedMutexException] { `$acquired = `$true }
if (-not `$acquired) { throw 'Uninstall is waiting for another operation.' }
`$statePath = Join-Path `$target 'state.json'
if (-not (Test-Path -LiteralPath `$statePath -PathType Leaf)) { return }
`$state = Get-Content -LiteralPath `$statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (`$state.ProductId -ne 'LeanADB' -or `$state.PendingRemovalId -ne '$RemovalId') { return }
# Validate once while holding the same mutex as installation. Partial removal
# can delete state.json before a locked file is retried; keep the lock throughout.
for (`$attempt = 0; `$attempt -lt 30; `$attempt++) {
    try {
        if (Test-Path -LiteralPath `$target) {
            Remove-Item -LiteralPath `$target -Recurse -Force -ErrorAction Stop
        }
        if (-not (Test-Path -LiteralPath `$target)) { break }
    }
    catch {
        `$lastError = `$_.Exception.Message
    }
    Start-Sleep -Milliseconds 500
}
if (Test-Path -LiteralPath `$target) {
    `$logPath = Join-Path ([IO.Path]::GetTempPath()) 'LeanADB-uninstall-error.log'
    "LeanADB could not remove `$target. `$lastError" | Set-Content -LiteralPath `$logPath -Encoding UTF8
}
} finally { if (`$acquired) { `$mutex.ReleaseMutex() }; `$mutex.Dispose() }
"@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cleanupCommand))
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden',
        '-EncodedCommand', $encodedCommand
    ) -WindowStyle Hidden | Out-Null
}

function Remove-InstallationRoot {
    param([string]$Root)
    $lastError = ''
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Root) {
                Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop
            }
            if (-not (Test-Path -LiteralPath $Root)) { return }
        }
        catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 500
    }
    throw (Format-Message -Name 'UninstallIncomplete' -Values @($Root, $lastError))
}

if ($OfflineZipPath) {
    if ($Action -notin @('Install', 'Update') -or -not (Test-Path -LiteralPath $OfflineZipPath -PathType Leaf) -or
        [IO.Path]::GetExtension($OfflineZipPath) -ine '.zip') {
        throw $script:Messages.OfflineZipInvalid
    }
    $OfflineZipPath = [IO.Path]::GetFullPath($OfflineZipPath)
}

$script:ShowInteractiveCompletion = $Action -eq 'Install' -and -not $AcceptSdkLicense
$script:SelectedPortableMode = $false
if ($Action -eq 'Install') {
    if ($script:ShowInteractiveCompletion -and -not $PSBoundParameters.ContainsKey('InstallPath')) {
        $existingInstall = Find-KnownInstallation
        $InstallPath = Select-InstallLocation -ExistingRoot $existingInstall
    }
    Confirm-SdkLicense
}

$InstallPath = Get-NormalizedInstallPath -Path $InstallPath
Assert-SafeInstallPath -Root $InstallPath
$state = $null
try {
    $state = Read-State -Root $InstallPath
}
catch {
    if ($Action -ne 'Repair') { throw }
    # Repair can rebuild state when both primary and backup are unreadable.
}
if ($null -ne $state -and $null -ne $state.PSObject.Properties['UsbBackend'] -and $state.UsbBackend -eq 'Legacy') {
    $env:ADB_USB_LEGACY = '1'
}
elseif ($null -ne $state) {
    Remove-Item Env:ADB_USB_LEGACY -ErrorAction SilentlyContinue
}
if ($null -ne $state -and $null -ne $state.PSObject.Properties['PendingRemovalId'] -and $state.PendingRemovalId -and $Action -notin @('Uninstall','Status','FailureHelp')) {
    throw $script:Messages.RemovalPending
}
if ($Language -eq 'Auto' -and $null -ne $state -and
    $null -ne $state.PSObject.Properties['LanguagePreference'] -and
    $state.LanguagePreference -in @('English', 'Korean')) {
    Set-DisplayLanguage -Preference ([string]$state.LanguagePreference)
}
if ($Action -eq 'Install' -and $null -eq $state -and (Test-Path -LiteralPath $InstallPath -PathType Container)) {
    $existingItems = @(Get-ChildItem -LiteralPath $InstallPath -Force)
    if ($existingItems.Count -gt 0) {
        $allowedBootstrapItems = @('LeanADB.ps1', 'Install.cmd', 'README.md', 'CHANGELOG.md', 'LICENSE', 'VERSION', 'UPDATE_URL', 'locales')
        $isReleaseBootstrap = $PSCommandPath -and
            ((Get-NormalizedInstallPath -Path (Split-Path -Parent $PSCommandPath)) -ieq $InstallPath) -and
            @($existingItems | Where-Object { $_.Name -notin $allowedBootstrapItems }).Count -eq 0
        if (-not $isReleaseBootstrap) {
            throw (Format-Message -Name 'NonEmptyInstallPath' -Values @($InstallPath))
        }
    }
}
if (-not $script:ProductManifestUrl -and $null -ne $state -and
    $null -ne $state.PSObject.Properties['ProductManifestUrl'] -and $state.ProductManifestUrl) {
    $script:ProductManifestUrl = [string]$state.ProductManifestUrl
}
if ($null -ne $state -and $Action -notin @('Uninstall', 'Repair')) {
    $state = Convert-ToBinLayout -Root $InstallPath -State $state
}

switch ($Action) {
    'Install' {
        if ($null -ne $state -and -not $Force) {
            Write-Info (Format-Message -Name 'AlreadyInstalled' -Values @($state.InstalledVersion))
        }
        $remote = if ($OfflineZipPath) { $null } else { Get-RemoteMetadata }
        if (-not $OfflineZipPath -and $null -ne $state -and -not (Test-RemoteChanged -State $state -RemoteMetadata $remote)) {
            $refreshMutex = Enter-UpdateLock -Root $InstallPath
            try {
                $state = Read-State -Root $InstallPath
                Copy-ProductFiles -Root $InstallPath
                Write-Launchers -Root $InstallPath
                if ([bool]$state.ShortcutRegistered) {
                    Set-StartMenuShortcut -Root $InstallPath -Present $true
                }
                if ([bool]$state.PathRegistered) {
                    Set-UserPathEntry -BinPath (Join-Path $InstallPath 'bin') -Present $true
                }
                $state | Add-Member -NotePropertyName Publisher -NotePropertyValue 'leodroid99' -Force
                $state | Add-Member -NotePropertyName LayoutVersion -NotePropertyValue 1 -Force
                $state | Add-Member -NotePropertyName LeanADBVersion -NotePropertyValue $script:ProductVersion -Force
                $state | Add-Member -NotePropertyName ProductUpdateAvailable -NotePropertyValue $false -Force
                $state | Add-Member -NotePropertyName LicenseUrl -NotePropertyValue $script:LicenseUrl -Force
                $productSignature = Get-AuthenticodeSignature -LiteralPath (Join-Path $InstallPath 'LeanADB.ps1')
                $state | Add-Member -NotePropertyName ProductSigned -NotePropertyValue ($productSignature.Status -eq 'Valid') -Force
                $productSigner = if ($productSignature.Status -eq 'Valid') { [string]$productSignature.SignerCertificate.Subject } else { '' }
                $state | Add-Member -NotePropertyName ProductSignerSubject -NotePropertyValue $productSigner -Force
                if ($script:ProductManifestUrl) {
                    $state | Add-Member -NotePropertyName ProductManifestUrl -NotePropertyValue $script:ProductManifestUrl -Force
                }
                if ($null -eq $state.PSObject.Properties['LicenseAcceptedUtc']) {
                    $state | Add-Member -NotePropertyName LicenseAcceptedUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
                }
                $state.LastCheckUtc = [DateTime]::UtcNow.ToString('o')
                $state | Add-Member -NotePropertyName LastCheckStatus -NotePropertyValue 'Success' -Force
                $state | Add-Member -NotePropertyName UpdateAvailable -NotePropertyValue $false -Force
                Write-State -Root $InstallPath -State $state
                if ([bool]$state.PathRegistered -or [bool]$state.ShortcutRegistered) {
                    Set-UninstallRegistration -Root $InstallPath -Present $true
                    $state | Add-Member -NotePropertyName UninstallRegistered -NotePropertyValue $true -Force
                    Write-State -Root $InstallPath -State $state
                }
            }
            finally {
                Exit-UpdateLock -Mutex $refreshMutex
            }
            Write-Info $script:Messages.UpToDateRefreshed
            Write-Info (Format-Message -Name 'InstallationFolder' -Values @($InstallPath))
            if ([bool]$state.PathRegistered) {
                $resolvedAdb = Get-RegisteredAdbPath
                $expectedAdb = Join-Path $InstallPath 'bin\adb.exe'
                if ($resolvedAdb -and $resolvedAdb -ine $expectedAdb) {
                    Write-Warning (Format-Message -Name 'PathConflict' -Values @($resolvedAdb))
                }
            }
            break
        }
        $registerPath = if ($null -ne $state) { [bool]$state.PathRegistered } else { -not $NoPath -and -not $script:SelectedPortableMode }
        $registerShortcut = if ($null -ne $state) { [bool]$state.ShortcutRegistered } else { -not $NoShortcut -and -not $script:SelectedPortableMode }
        Install-Package -Root $InstallPath -RemoteMetadata $remote -RegisterPath $registerPath -RegisterShortcut $registerShortcut -ExistingState $state -LocalZipPath $OfflineZipPath | Out-Null
    }
    'Update' {
        if ($null -eq $state) {
            throw (Format-Message -Name 'NotInstalled' -Values @($InstallPath))
        }
        if ($OfflineZipPath) {
            Install-Package -Root $InstallPath -RemoteMetadata $null -RegisterPath ([bool]$state.PathRegistered) -RegisterShortcut ([bool]$state.ShortcutRegistered) -ExistingState $state -LocalZipPath $OfflineZipPath | Out-Null
            Write-Info $script:Messages.OfflineZipStatus
            break
        }
        if (-not $script:ProductManifestUrl) {
            Write-Info $script:Messages.ProductUpdatesNotConfigured
        }
        if ($script:ProductManifestUrl -and -not $SkipProductUpdate) {
            $productManifest = $null
            try { $productManifest = Get-ProductManifest -ManifestUrl $script:ProductManifestUrl }
            catch { Write-Warning (Format-Message -Name 'ProductCheckFailed' -Values @($_.Exception.Message)) }
            $currentProductVersion = if ($null -ne $state.PSObject.Properties['LeanADBVersion']) { [string]$state.LeanADBVersion } else { $script:ProductVersion }
            if ($null -ne $productManifest -and (Test-NewerProductVersion -Current $currentProductVersion -Candidate ([string]$productManifest.Version))) {
                Write-Info (Format-Message -Name 'ProductUpdating' -Values @($productManifest.Version))
                Install-ProductUpdate -Root $InstallPath -ManifestUrl $script:ProductManifestUrl -Manifest $productManifest
                Write-Info (Format-Message -Name 'ProductUpdated' -Values @($productManifest.Version))
                & (Join-Path $InstallPath 'LeanADB.ps1') -Action Update -InstallPath $InstallPath -SkipProductUpdate -Force:$Force -Quiet:$Quiet -Language $Language
                if ($LASTEXITCODE -ne 0) { throw 'Platform-Tools update failed after the LeanADB update.' }
                break
            }
        }
        $remote = Get-RemoteMetadata
        if (-not (Test-RemoteChanged -State $state -RemoteMetadata $remote)) {
            $refreshMutex = Enter-UpdateLock -Root $InstallPath
            try {
                $state = Read-State -Root $InstallPath
                $state.LastCheckUtc = [DateTime]::UtcNow.ToString('o')
                $state | Add-Member -NotePropertyName LastCheckStatus -NotePropertyValue 'Success' -Force
                $state | Add-Member -NotePropertyName UpdateAvailable -NotePropertyValue $false -Force
                Write-State -Root $InstallPath -State $state
            }
            finally {
                Exit-UpdateLock -Mutex $refreshMutex
            }
            Write-Info (Format-Message -Name 'AlreadyUpToDate' -Values @($state.InstalledVersion))
            break
        }
        Install-Package -Root $InstallPath -RemoteMetadata $remote -RegisterPath ([bool]$state.PathRegistered) -RegisterShortcut ([bool]$state.ShortcutRegistered) -ExistingState $state | Out-Null
    }
    'AutoUpdate' {
        if ($null -eq $state -or -not (Test-CheckDue -State $state)) {
            break
        }
        $checkMutex = $null
        try {
            $checkMutex = Enter-UpdateLock -Root $InstallPath
            $state = Read-State -Root $InstallPath
            if ($null -eq $state -or -not (Test-CheckDue -State $state)) {
                break
            }
            $state.LastCheckUtc = [DateTime]::UtcNow.ToString('o')
            Write-State -Root $InstallPath -State $state
            Exit-UpdateLock -Mutex $checkMutex
            $checkMutex = $null
            $checks = Get-UpdateChecks
            $checkMutex = Enter-UpdateLock -Root $InstallPath
            $state = Read-State -Root $InstallPath
            if ($null -eq $state) { break }
            if ($checks.ToolsStatus -eq 'Success') {
                $available = [bool]$state.PackageComparisonKnown -and (Test-RemoteChanged -State $state -RemoteMetadata $checks.Remote)
                $state | Add-Member -NotePropertyName UpdateAvailable -NotePropertyValue $available -Force
            }
            $state | Add-Member -NotePropertyName LastCheckStatus -NotePropertyValue $checks.ToolsStatus -Force
            $state | Add-Member -NotePropertyName LastCheckError -NotePropertyValue $checks.ToolsError -Force
            $state | Add-Member -NotePropertyName ProductCheckStatus -NotePropertyValue $checks.ProductStatus -Force
            $state | Add-Member -NotePropertyName ProductCheckError -NotePropertyValue $checks.ProductError -Force
            if ($checks.ProductStatus -eq 'Success') {
                $version = if ($null -ne $state.PSObject.Properties['LeanADBVersion']) { [string]$state.LeanADBVersion } else { $script:ProductVersion }
                $state | Add-Member -NotePropertyName ProductUpdateAvailable -NotePropertyValue (Test-NewerProductVersion -Current $version -Candidate $checks.Manifest.Version) -Force
                $state | Add-Member -NotePropertyName ProductUpdateVersion -NotePropertyValue ([string]$checks.Manifest.Version) -Force
            }
            Write-State -Root $InstallPath -State $state
        }
        catch {
            if ($null -ne $state -and $null -ne $checkMutex) {
                $state.LastCheckUtc = [DateTime]::UtcNow.ToString('o')
                $state | Add-Member -NotePropertyName LastCheckStatus -NotePropertyValue 'Failed' -Force
                $state | Add-Member -NotePropertyName LastCheckError -NotePropertyValue $_.Exception.Message -Force
                Write-State -Root $InstallPath -State $state
            }
            if (-not $Quiet) {
                Write-Warning (Format-Message -Name 'AutoUpdateFailed' -Values @($_.Exception.Message))
            }
        }
        finally {
            Exit-UpdateLock -Mutex $checkMutex
        }
    }
    'Check' {
        if ($null -eq $state) {
            throw (Format-Message -Name 'NotInstalled' -Values @($InstallPath))
        }
        $checks = Get-UpdateChecks
        if ($checks.ProductStatus -eq 'Success') {
            $productManifest = $checks.Manifest
            $currentProductVersion = if ($null -ne $state.PSObject.Properties['LeanADBVersion']) { [string]$state.LeanADBVersion } else { $script:ProductVersion }
            if (Test-NewerProductVersion -Current $currentProductVersion -Candidate ([string]$productManifest.Version)) {
                Write-Info (Format-Message -Name 'ProductUpdateReady' -Values @($productManifest.Version))
            }
            else {
                Write-Info (Format-Message -Name 'ProductUpToDate' -Values @($currentProductVersion))
            }
        }
        elseif ($checks.ProductStatus -eq 'NotConfigured') {
            Write-Info $script:Messages.ProductUpdatesNotConfigured
        }
        else { Write-Warning (Format-Message -Name 'ProductCheckFailed' -Values @($checks.ProductError)) }
        if ($checks.ToolsStatus -eq 'Failed') { Write-Warning (Format-Message -Name 'ToolsCheckFailed' -Values @($checks.ToolsError)); break }
        $remote = $checks.Remote
        if (-not $state.PackageComparisonKnown) {
            Write-Info $script:Messages.OfflineZipStatus
        }
        elseif (Test-RemoteChanged -State $state -RemoteMetadata $remote) {
            Write-Info $script:Messages.UpdateAvailable
        }
        else {
            Write-Info (Format-Message -Name 'AlreadyUpToDate' -Values @($state.InstalledVersion))
        }
    }
    'Status' {
        if ($null -eq $state) {
            Write-Info (Format-Message -Name 'NotInstalled' -Values @($InstallPath))
            break
        }
        $statusLeanVersion = if ($null -ne $state.PSObject.Properties['LeanADBVersion']) { $state.LeanADBVersion } else { $script:ProductVersion }
        $statusUpdateAvailable = if ($null -ne $state.PSObject.Properties['UpdateAvailable']) { [bool]$state.UpdateAvailable } else { $false }
        $statusProductUpdate = if ($null -ne $state.PSObject.Properties['ProductUpdateAvailable']) { [bool]$state.ProductUpdateAvailable } else { $false }
        $statusProductSigned = if ($null -ne $state.PSObject.Properties['ProductSigned']) { [bool]$state.ProductSigned } else { $false }
        $resolvedAdb = Get-RegisteredAdbPath
        [pscustomobject]@{
            InstallPath      = $InstallPath
            LeanADB          = $statusLeanVersion
            PlatformTools    = $state.InstalledVersion
            LastUpdateCheck  = $state.LastCheckUtc
            UpdateAvailable  = $statusUpdateAvailable
            OnlineComparisonKnown = $state.PackageComparisonKnown
            LeanADBUpdate    = $statusProductUpdate
            LeanADBSigned    = $statusProductSigned
            UpdateManifest   = $script:ProductManifestUrl
            LeanADBUpdateConfigured = [bool]$script:ProductManifestUrl
            UsbBackend       = if ($null -ne $state.PSObject.Properties['UsbBackend']) { [string]$state.UsbBackend } else { 'Standard' }
            ZipSha256        = $state.ZipSha256
            UserPath         = $state.PathRegistered
            StartMenuShortcut = $state.ShortcutRegistered
            ResolvedAdb       = $resolvedAdb
            TerminalFolder    = (Get-OutputFolder -Root $InstallPath -State $state)
        } | Format-List
    }
    'Devices' {
        if ($null -eq $state) {
            throw (Format-Message -Name 'NotInstalled' -Values @($InstallPath))
        }
        $records = @(Get-AdbDeviceRecords -AdbPath (Join-Path $InstallPath 'bin\adb.exe'))
        if ($records.Count -eq 0) {
            Write-Info $script:Messages.NoReadyDevice
        }
        else {
            $records | Select-Object Serial, Model, Status | Format-Table -AutoSize
        }
    }
    'Drop' {
        if ($null -eq $state) { throw (Format-Message -Name 'NotInstalled' -Values @($InstallPath)) }
        Clear-Host
        Write-Host $script:Messages.DropTitle -ForegroundColor Cyan
        $files = @()
        foreach ($item in $DroppedPaths) {
            try {
                $path = [IO.Path]::GetFullPath($item)
                if (Test-Path -LiteralPath $path -PathType Leaf) { $files += $path }
                else { Write-Host (Format-Message -Name 'BatchSkipped' -Values @($item)) -ForegroundColor Yellow }
            }
            catch { Write-Host (Format-Message -Name 'BatchSkipped' -Values @($item)) -ForegroundColor Yellow }
        }
        if ($files.Count -eq 0) {
            Write-Host $script:Messages.DropNoFiles -ForegroundColor Yellow
            Wait-ForMenuKey
            break
        }
        $adb = Join-Path $InstallPath 'bin\adb.exe'
        $serial = Select-AdbDevice -AdbPath $adb
        if (-not $serial) { break }
        $apks = @($files | Where-Object { [IO.Path]::GetExtension($_) -ieq '.apk' })
        $others = @($files | Where-Object { [IO.Path]::GetExtension($_) -ine '.apk' })
        if ($others.Count -eq 0) {
            Write-Host $script:Messages.DropAllApks
            Install-ApkBatch -AdbPath $adb -Serial $serial -Paths $apks
        }
        elseif ($apks.Count -eq 0) {
            Send-FilesToDevice -AdbPath $adb -Serial $serial -Paths $others
        }
        else {
            Write-Host $script:Messages.DropMixed
            Write-Host $script:Messages.DropSendAll
            Write-Host $script:Messages.DropInstallAndSend
            Write-Host $script:Messages.DropCancel
            while ($true) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::Escape) { break }
                if ($key.Key -eq [ConsoleKey]::Enter) {
                    Send-FilesToDevice -AdbPath $adb -Serial $serial -Paths $files
                    break
                }
                if ($key.Key -eq [ConsoleKey]::I) {
                    Install-ApkBatch -AdbPath $adb -Serial $serial -Paths $apks
                    Send-FilesToDevice -AdbPath $adb -Serial $serial -Paths $others
                    break
                }
            }
        }
    }
    'SelfUpdate' {
        if ($null -eq $state) {
            throw (Format-Message -Name 'NotInstalled' -Values @($InstallPath))
        }
        if (-not $script:ProductManifestUrl) {
            throw 'LeanADB self-update is not configured for this distribution.'
        }
        $productManifest = Get-ProductManifest -ManifestUrl $script:ProductManifestUrl
        $currentProductVersion = if ($null -ne $state.PSObject.Properties['LeanADBVersion']) { [string]$state.LeanADBVersion } else { $script:ProductVersion }
        if (-not (Test-NewerProductVersion -Current $currentProductVersion -Candidate ([string]$productManifest.Version))) {
            Write-Info (Format-Message -Name 'ProductUpToDate' -Values @($currentProductVersion))
            break
        }
        Write-Info (Format-Message -Name 'ProductUpdating' -Values @($productManifest.Version))
        Install-ProductUpdate -Root $InstallPath -ManifestUrl $script:ProductManifestUrl -Manifest $productManifest
        Write-Info (Format-Message -Name 'ProductUpdated' -Values @($productManifest.Version))
    }
    'Repair' {
        $repairMutex = Enter-UpdateLock -Root $InstallPath
        try {
            $state = $null
            try { $state = Read-State -Root $InstallPath }
            catch { $state = $null }
            $recoveredFromBackup = $script:StateRecoveredFromBackup
            if ($null -eq $state) {
                if (-not (Test-Path -LiteralPath (Join-Path $InstallPath 'LeanADB.ps1') -PathType Leaf)) {
                    throw (Format-Message -Name 'NotInstalled' -Values @($InstallPath))
                }
                $state = New-RecoveredState -Root $InstallPath
                Write-State -Root $InstallPath -State $state
                Write-Info $script:Messages.RepairRebuiltState
            }
            else {
                $state = Convert-ToBinLayout -Root $InstallPath -State $state
                $installedVersion = Get-ValidatedInstalledPlatformToolsVersion -Root $InstallPath
                if ([string]$state.InstalledVersion -ne $installedVersion) {
                    $state | Add-Member -NotePropertyName InstalledVersion -NotePropertyValue $installedVersion -Force
                    $state | Add-Member -NotePropertyName LastCheckStatus -NotePropertyValue 'Recovered' -Force
                    $state | Add-Member -NotePropertyName PackageComparisonKnown -NotePropertyValue $false -Force
                    foreach ($field in @('ETag', 'LastModified', 'ContentLength', 'ZipSha256')) {
                        $state | Add-Member -NotePropertyName $field -NotePropertyValue '' -Force
                    }
                }
                Write-State -Root $InstallPath -State $state
                if ($recoveredFromBackup) { Write-Info $script:Messages.RepairRecoveredBackup }
            }
            Write-Launchers -Root $InstallPath
            if ([bool]$state.PathRegistered) { Set-UserPathEntry -BinPath (Join-Path $InstallPath 'bin') -Present $true }
            if ([bool]$state.ShortcutRegistered) { Set-StartMenuShortcut -Root $InstallPath -Present $true }
            if ([bool]$state.PathRegistered -or [bool]$state.ShortcutRegistered) { Set-UninstallRegistration -Root $InstallPath -Present $true }
            [void](Read-StateFile -Path (Get-StatePath -Root $InstallPath))
            Write-Info $script:Messages.RepairCompleted
        }
        finally { Exit-UpdateLock -Mutex $repairMutex }
    }
    'FailureHelp' {
        Write-Host "[LeanADB] $($script:Messages.InstallFailed)" -ForegroundColor Red
        Write-Host (Format-Message -Name 'SeeErrorLog' -Values @($script:ErrorLogPath)) -ForegroundColor Yellow
    }
    'Terminal' {
        if ($null -eq $state) {
            throw (Format-Message -Name 'NotInstalled' -Values @($InstallPath))
        }
        $env:PATH = (Join-Path $InstallPath 'bin') + ';' + $env:PATH
        $script:ActiveOutputFolder = Get-OutputFolder -Root $InstallPath -State $state
        $workingDirectory = Get-ActiveOutputFolder
        $terminalMessage = 'title LeanADB - Android Platform Tools & echo ' + $script:Messages.TerminalByline +
            ' & echo ' + $script:Messages.TerminalWorking + ' & echo ' + $script:Messages.TerminalTry
        Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/k', $terminalMessage) -WorkingDirectory $workingDirectory
    }
    'Menu' {
        if ($null -eq $state) {
            throw (Format-Message -Name 'NotInstalled' -Values @($InstallPath))
        }
        Show-LeanAdbMenu -Root $InstallPath -State $state
    }
    'Uninstall' {
        if (-not (Confirm-LeanAdbUninstall)) {
            break
        }
        $uninstallMutex = Enter-UpdateLock -Root $InstallPath
        try {
            $installedState = Assert-SafeUninstallPath -Root $InstallPath
            $legacyBinPath = Join-Path $InstallPath 'bin'
            $adb = Join-Path $InstallPath 'adb.exe'
            if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
                $adb = Join-Path $legacyBinPath 'adb.exe'
            }
            Stop-AdbServer -AdbPath $adb
            if ($installedState.PathRegistered) {
                Set-UserPathEntry -BinPath $InstallPath -Present $false
                Set-UserPathEntry -BinPath $legacyBinPath -Present $false
            }
            if ($installedState.ShortcutRegistered) {
                Set-StartMenuShortcut -Root $InstallPath -Present $false
            }
            Set-UninstallRegistration -Root $InstallPath -Present $false
            $scriptDirectory = if ($PSCommandPath) { Get-NormalizedInstallPath -Path (Split-Path -Parent $PSCommandPath) } else { '' }
            if ($scriptDirectory -ieq $InstallPath) {
                $removalId = [guid]::NewGuid().ToString('N')
                $installedState | Add-Member -NotePropertyName PendingRemovalId -NotePropertyValue $removalId -Force
                Write-State -Root $InstallPath -State $installedState
                try { Start-DeferredRemoval -Root $InstallPath -RemovalId $removalId }
                catch {
                    $installedState.PSObject.Properties.Remove('PendingRemovalId')
                    Write-State -Root $InstallPath -State $installedState
                    throw
                }
                Write-Info $script:Messages.UninstalledDeferred
            }
            else {
                Remove-InstallationRoot -Root $InstallPath
                Write-Info $script:Messages.Uninstalled
            }
        }
        finally {
            Exit-UpdateLock -Mutex $uninstallMutex
        }
    }
}

if ($script:ShowInteractiveCompletion -and $Action -eq 'Install') {
    Show-InstallCompletion -Root $InstallPath
}
if ($Action -eq 'Drop' -and $script:AnyBatchFailure) { exit 1 }
$global:LASTEXITCODE = 0
