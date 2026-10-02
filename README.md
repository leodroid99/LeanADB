# LeanADB

LeanADB is a small Windows installer and launcher for Google's official Android SDK Platform-Tools. It preserves the simple workflow of the old Minimal ADB and Fastboot package while downloading current, unmodified tools directly from Google.

Created by **leodroid99**.

Download the latest bootstrap ZIP from [GitHub Releases](https://github.com/leodroid99/LeanADB/releases/latest), extract it, and run `Install.cmd`. Google binaries are not bundled; the installer downloads them separately after license acceptance.

Supported systems: 64-bit Windows 10 and Windows 11 with Windows PowerShell 5.1 or newer. PowerShell 7 is also tested.

Automatic language selection follows the Windows display language. Korean (`ko-*`) receives a Korean interface; other languages currently use English. The easy menu can save a manual English or Korean preference with **G**, and `-Language English` or `-Language Korean` overrides it for one command.

## What it does

- Downloads Platform-Tools from Google's permanent Windows download URL.
- Requires the user to review and accept the Android SDK license.
- Verifies valid Google Authenticode signatures on `adb.exe` and `fastboot.exe`.
- Installs only ADB/Fastboot and the DLL/helper files needed for full fastboot formatting support.
- Adds the `bin` directory to the current user's PATH without administrator rights.
- Creates a Start Menu shortcut for a localized, keyboard-driven easy menu.
- Guides ADB/Fastboot connection checks with status-specific advice, refresh, diagnosis, and USB driver help.
- Shows ADB serials, model names, and connection states without requiring commands. Press **C** to choose a target and **A** to give it a short name; the menu remembers five recent choices without automatically selecting one on the next launch.
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

The interactive installer uses `%LOCALAPPDATA%\LeanADB` as the default when no known installation exists. It also offers Downloads, Desktop, a folder picker, and **P** for a portable `LeanADB-Portable` folder beside the extracted installer. If an installation exists, it becomes the Enter default; you can still choose another location. Portable mode leaves PATH and the Start Menu unchanged, so you can keep it on an external drive. Installation shows the chosen path prominently and opens its `bin` folder. Standard installations have a Start Menu entry. **Open LeanADB Terminal.cmd** opens the advanced terminal; PATH registration also makes `adb` and `fastboot` available in newly opened terminals.

Standard installations save files in Windows Downloads by default. Portable installations use a sibling `LeanADB-Portable-Files` folder outside the installation directory. The terminal opens in this output folder. Choose **6 > 3** to change the save location; **7** opens it, and **3 > 7** browses recent LeanADB results. Uninstall preserves the sibling output folder.

The Google ZIP itself is downloaded to a temporary directory, validated, and deleted after its selected files are installed. The usable `adb.exe`, `fastboot.exe`, and their required support files remain together in the selected installation folder's `bin` directory. The installer opens that exact folder after completion.

If LeanADB settings or launchers become damaged, run `Repair LeanADB.cmd` in the installation folder. Repair uses the last valid state backup when available; if both state files are unusable, it rebuilds minimal settings only after checking the installed Google-signed Platform-Tools. The easy menu also offers **6 > 2** for Repair. If the Google tools are missing or invalid, Repair reports failure instead of claiming success.

For an offline first install, drag a previously downloaded official Windows Platform-Tools ZIP onto `Install.cmd`, then choose the installation folder and accept the Google SDK license. After installation, drop one or more local files on `Drop files on LeanADB.cmd`. APKs are installed individually; other files go to the phone's Downloads folder. For mixed files, choose whether to transfer all or install APKs and transfer the rest. Use **2 > 1**, then choose **2** for a split APK set belonging to one app.

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

Opening LeanADB or LeanADB Terminal starts a lightweight background metadata check only when 24 hours have elapsed since the previous successful check. The menu appears immediately and refreshes update notices when the check finishes. Google tools and LeanADB app checks are independent: a failed feed does not block the other. Network errors are non-fatal and use a six-hour retry backoff. Choose **6 > 1** to explicitly install an available update. A changed package is downloaded to a temporary directory, validated, and swapped into place. Tools, app files, launchers, and settings are restored if a subsequent installation step fails.

The **6 > 8** menu accepts a local Google ZIP without contacting Google. LeanADB checks archive paths and size, verifies the Google signatures on ADB and Fastboot, and refuses an older package. A local ZIP has no trustworthy online ETag baseline, so LeanADB reports online update availability as unknown until an online package is installed; a successful metadata check alone does not claim that a local package is the latest online version.

## Easy menu

The home screen groups actions by what you want to do:

| Key | Task |
| --- | --- |
| 1 | Connect a device, authorization guidance, refresh, and driver help |
| 2 | Install apps: separate APKs or one split-APK set |
| 3 | Send/receive files, browse device storage, screenshots, and screen recording |
| 4 | Device details, reboot, sideload, wireless debugging, logs, and bug reports |
| 5 | Advanced ADB/Fastboot terminal |
| 6 | Update, repair, save location, language, and diagnostics |
| 7 | Open saved files or browse recent LeanADB outputs |

The current target, connection state, versions, and save location stay visible on the home screen. Press **C** to choose a target, **A** to give it a short name, **Esc** to go back, or **Q/Esc** at home to exit. Device selection supports multiple pages. The first ADB action selects a target for this session; if it disappears, LeanADB stops the action instead of silently switching phones. Fastboot also requires confirmation if its only device has a different serial.

When selecting multiple APKs, choose separate apps or a split set belonging to one app. File transfers and APK batches show per-file results, save a result report in your chosen folder, and offer **R** inside Apps/Files to retry only failed items on the original target. A failed transfer can leave an incomplete remote file; LeanADB records its path and does not automatically delete device files. Long operations show elapsed time, accept **Esc** to stop the local ADB client, and have a timeout. Stopping the client is not a rollback of changes already performed on the phone.

Screen recording supports 1–180 seconds, requires Android 4.4/API 19 or newer, and does not capture audio. Bug reports may contain sensitive data and require a privacy confirmation. APK and ZIP paths use the standard Windows picker, so spaces and Korean characters do not need manual quoting. Sideload requires recovery to enter sideload mode first. Flashing, wiping, and unlocking remain in the advanced terminal. Existing letter shortcuts such as **S**, **W**, **R**, **L**, **H**, **D**, and **G** remain available from home.

## Older device compatibility

Google states that current Platform-Tools remain backward compatible with older Android versions, although newer features require newer Android versions. LeanADB's host application supports 64-bit Windows 10 and 11. An OEM USB driver and Fastboot-capable bootloader are still needed for those connections.

Use **D** in the easy menu to check an authorized device's Android version and API level. Split APKs need Android 5.0 (API 21) or newer; LeanADB blocks their installation on an identified older device. The **W** menu offers Android 11+ pairing under **P** and older USB-first Wi-Fi setup under **L**. The older method opens port 5555 on the phone, so use a trusted local Wi-Fi network and choose **U** to return to USB mode when done. The **H** help menu can restart ADB using Google's legacy Windows USB backend. This setting persists for LeanADB launchers; an ADB server started by another application may need restarting again. If direct screenshots fail, LeanADB tries `adb shell screencap` followed by `adb pull`.

Google references: https://developer.android.com/tools/releases/platform-tools, https://developer.android.com/tools/adb, and https://developer.android.com/guide/app-bundle/app-bundle-format.

## Validation scope

Automated tests cover Windows PowerShell 5.1 and PowerShell 7, isolated installation/update/removal, archive and signature checks, rollback, localization, command timeouts, and simulated menu/device workflows. No physical Android device testing was performed for version 1.1.0. USB/Fastboot drivers, wireless debugging, APK installation, and capture behavior on individual devices are not hardware-verified.

## Licensing and trademarks

LeanADB's scripts are copyright 2026 leodroid99 and available under the MIT License. Android SDK Platform-Tools are copyright Google LLC and other contributors, are downloaded separately from Google, and remain governed by the Android SDK License Agreement and their included notices. LeanADB is an independent project and is not affiliated with or endorsed by Google. Android is a trademark of Google LLC.

- Platform-Tools releases and SDK license: https://developer.android.com/tools/releases/platform-tools
- Android SDK License Agreement: https://developer.android.com/studio/terms
- Official download host: https://dl.google.com/android/repository/platform-tools-latest-windows.zip
