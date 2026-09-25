# LeanADB

LeanADB is a small Windows installer and launcher for Google's official Android SDK Platform-Tools. It preserves the simple workflow of the old Minimal ADB and Fastboot package while downloading current, unmodified tools directly from Google.

Created by **leodroid99**.

Supported systems: 64-bit Windows 10 and Windows 11 with Windows PowerShell 5.1 or newer. PowerShell 7 is also tested.

Automatic language selection follows the Windows display language. Korean (`ko-*`) receives a Korean interface; other languages currently use English. The easy menu can save a manual English or Korean preference with **G**, and `-Language English` or `-Language Korean` overrides it for one command.

## What it does

- Downloads Platform-Tools from Google's permanent Windows download URL.
- Requires the user to review and accept the Android SDK license.
- Verifies valid Google Authenticode signatures on `adb.exe` and `fastboot.exe`.
- Installs only ADB/Fastboot and the DLL/helper files needed for full fastboot formatting support.
- Adds the `bin` directory to the current user's PATH without administrator rights.
- Creates a Start Menu shortcut for a localized, keyboard-driven easy menu.
- Shows ADB serials, model names, and connection states without requiring commands.
- Shows Android version, API level, CPU architecture, and compatibility guidance.
- Installs one APK or a selected split-APK set and sends multiple selected files to the device's Downloads folder.
- Accepts files dropped on an installed launcher: APKs are installed one by one; other files are transferred.
- Installs or updates from a local official Google ZIP with archive checks and signature verification.
- Records the device screen to MP4 on Android 4.4+ (maximum 180 seconds; no audio).
- Saves screenshots, received files, logcat snapshots, and bug reports in the selected output folder.
- Lets users browse shared device folders and receive a selected file or entire folder; manual remote paths remain available.
- Diagnoses common ADB/Fastboot connection problems without changing the device.
- Collects an opt-in bug report after a privacy warning.
- Supports Android wireless-debugging pairing, connection, and disconnection.
- Supports USB-first Wi-Fi debugging for older Android devices and return to USB mode.
- Offers Google's legacy Windows USB backend when an older device is not detected.
- Guides ADB sideload of an update ZIP after recovery enters sideload mode, with an explicit confirmation.
- Offers confirmed reboot to Android or the bootloader for an authorized ADB device.
- Reboots a selected Fastboot device to Android with confirmation.
- Keeps a separate advanced terminal for normal `adb` and `fastboot` commands.
- Checks at most once every 24 hours in a non-blocking background process when LeanADB opens.
- Backs off for six hours after a failed check instead of delaying every launch.
- Uses only an HTTP HEAD request when the package is unchanged; it downloads the ZIP only after Google's ETag or modification time changes.
- Replaces the tool directory atomically and restores the previous directory if replacement fails.
- Uses an update mutex to prevent simultaneous installation, update, and removal operations.
- Registers a per-user Windows uninstall entry without requiring administrator rights.
- Runs no service, tray app, scheduled task, or permanent background process.

## Install

First extract the entire ZIP to a normal folder. Do not run the installer from inside Windows Explorer's compressed-folder view. Double-click `Install.cmd`, then choose the standard AppData location, Downloads, Desktop, the portable location beside the extracted installer, or a custom folder. Review the linked Android SDK license and press **Enter** to accept and install. Press **Esc** to cancel.

The interactive installer uses `%LOCALAPPDATA%\LeanADB` as the default when no known installation exists. It also offers the Downloads folder, Desktop, a Windows folder picker, and **P** for a portable `LeanADB-Portable` folder beside the extracted installer. If an existing installation is found, it is shown as the Enter default, but you can choose a different location. Portable mode does not modify the user PATH or Start Menu; keep its folder on the external drive and launch it from there. The installer displays the selected path prominently and opens its `bin` folder after a successful installation. For a standard installation, open **LeanADB** from the Start Menu. Advanced users can open **Open LeanADB Terminal.cmd** or use `adb` and `fastboot` from a newly opened terminal when PATH registration is enabled. A standard installation saves files in Windows Downloads by default; a portable installation saves them in a sibling `LeanADB-Portable-Files` folder by default, outside the installation directory. The terminal opens in this output folder. Press **T**, then **O** in the easy menu to choose Downloads, the sibling folder, or another folder. Uninstall does not remove the sibling output folder.

The Google ZIP itself is downloaded to a temporary directory, validated, and deleted after its selected files are installed. The usable `adb.exe`, `fastboot.exe`, and their required support files remain together in the selected installation folder's `bin` directory. The installer opens that exact folder after completion.

For an offline first install, drag a previously downloaded official Windows Platform-Tools ZIP onto `Install.cmd`, then choose the installation folder and accept the Google SDK license. After installation, drop one or more local files on `Drop files on LeanADB.cmd`. APKs are installed individually; other files go to the phone's Downloads folder. For mixed files, choose whether to transfer all or install APKs and transfer the rest. Use menu option 3 for a split APK set belonging to one app.

## Commands

```powershell
# Install without prompts after you have reviewed and accepted Google's license
.\LeanADB.ps1 -Action Install -AcceptSdkLicense

# Check or apply an update
.\LeanADB.ps1 -Action Check
.\LeanADB.ps1 -Action Update

# Install or update from a local official Google ZIP without network access
.\LeanADB.ps1 -Action Update -InstallPath .\portable -OfflineZipPath .\platform-tools-latest-windows.zip

# Show local version and verification data
.\LeanADB.ps1 -Action Status

# List devices in a script-friendly non-interactive action
.\LeanADB.ps1 -Action Devices

# Open the easy menu or advanced terminal
.\LeanADB.ps1 -Action Menu
.\LeanADB.ps1 -Action Terminal

# Override the display language for one command
.\LeanADB.ps1 -Action Status -Language English

# Remove LeanADB, its PATH entry, and its shortcut
.\LeanADB.ps1 -Action Uninstall
```

Maintainers can create the script-only bootstrap release and its SHA-256 file with:

```powershell
.\build\Build-Release.ps1
```

The build also creates `dist\LeanADB-release.json`, which contains the package hash and per-file hashes used by LeanADB's transactional self-updater. The public build includes `UPDATE_URL`, pointing to the latest GitHub release manifest. Publish that manifest and the matching release ZIP together as assets of each versioned release. The installer records this URL in its state. Local `file:` manifests are accepted only to support isolated release testing.

For a signed public build, provide the thumbprint of a trusted current-user code-signing certificate. The staging copy of `LeanADB.ps1` is SHA-256 Authenticode-signed and timestamped before hashes and the release archive are generated:

```powershell
.\build\Build-Release.ps1 -CodeSigningThumbprint YOUR_CERTIFICATE_THUMBPRINT
```

For a portable/test installation, specify another directory and disable PATH and shortcut changes:

```powershell
.\LeanADB.ps1 -Action Install -AcceptSdkLicense -InstallPath .\portable -NoPath -NoShortcut
```

## Update behavior

Opening LeanADB or LeanADB Terminal starts a lightweight background metadata check only when 24 hours have elapsed since the previous successful check. The menu appears immediately. Network errors are non-fatal and use a six-hour retry backoff. When an update is found, the menu displays a notice and option 6 installs it explicitly. A changed package is downloaded to a temporary directory, validated, and then swapped into place.

The **T > U** menu accepts a local Google ZIP without contacting Google. LeanADB checks archive paths and size, verifies the Google signatures on ADB and Fastboot, and refuses an older package. A local ZIP has no trustworthy online ETag baseline, so LeanADB reports online update availability as unknown until an online package is installed; it does not claim that a local package is the latest online version.

## Easy menu

The default launcher provides single-key actions for device discovery, device details, `fastboot devices`, single/split APK installation, multiple-file transfer to `/sdcard/Download/`, safe file/folder receiving, screenshots, logcat export, wireless debugging, ADB sideload, confirmed ADB/Fastboot reboot, language selection, update installation, official USB-driver help, and opening the installation folder. Press **T** for Files and Diagnostics: **X** runs read-only connection diagnosis; **F** browses shared storage, including subfolders, and receives a selected file or an entire folder with confirmation; **E** collects a bug report only after a privacy warning and Enter confirmation; **O** changes where local files are saved; **U** installs a local Google ZIP; **V** records the screen for 1–180 seconds and retrieves the MP4. Screen recording requires Android 4.4/API 19 or newer and does not capture audio. **R** in the main menu retains manual remote-path entry. Bug reports may contain sensitive data. APK and ZIP paths are selected through the standard Windows file picker, so spaces and Korean characters do not need manual quoting. Sideload requires the device to show `sideload` in `adb devices`; recovery must enter sideload mode first. Flashing, wiping, and unlocking remain in the advanced terminal.

## Older device compatibility

Google states that current Platform-Tools remain backward compatible with older Android versions, although newer features require newer Android versions. LeanADB's host application supports 64-bit Windows 10 and 11. An OEM USB driver and Fastboot-capable bootloader are still needed for those connections.

Use **D** in the easy menu to check an authorized device's Android version and API level. Split APKs need Android 5.0 (API 21) or newer; LeanADB blocks their installation on an identified older device. The **W** menu offers Android 11+ pairing under **P** and older USB-first Wi-Fi setup under **L**. The older method opens port 5555 on the phone, so use a trusted local Wi-Fi network and choose **U** to return to USB mode when done. The **H** help menu can restart ADB using Google's legacy Windows USB backend. This setting persists for LeanADB launchers; an ADB server started by another application may need restarting again. If direct screenshots fail, LeanADB tries `adb shell screencap` followed by `adb pull`.

Google references: https://developer.android.com/tools/releases/platform-tools, https://developer.android.com/tools/adb, and https://developer.android.com/guide/app-bundle/app-bundle-format.

## Licensing and trademarks

LeanADB's scripts are copyright 2026 leodroid99 and available under the MIT License. Android SDK Platform-Tools are copyright Google LLC and other contributors, are downloaded separately from Google, and remain governed by the Android SDK License Agreement and their included notices. LeanADB is an independent project and is not affiliated with or endorsed by Google. Android is a trademark of Google LLC.

- Platform-Tools releases and SDK license: https://developer.android.com/tools/releases/platform-tools
- Android SDK License Agreement: https://developer.android.com/studio/terms
- Official download host: https://dl.google.com/android/repository/platform-tools-latest-windows.zip
